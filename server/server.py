#! /usr/bin/env python3
# TODO: flock over the database file

import abc
import argparse
import base64
import contextlib
import contextvars
import copy
import functools
import hmac
import io
import json
from pathlib import Path
import random
import secrets
import string
import time
from typing import Iterator, Optional, Container, NewType, Callable, NoReturn, Tuple
import argparse
import logging
import os
import smtplib
from email.mime.text import MIMEText

from PIL import Image, ImageDraw, ImageFont  # type: ignore
import bcrypt  # type: ignore
from aiohttp import web
import google.protobuf.text_format  # type: ignore

from .protobuf import mvp_pb2

logger = logging.getLogger(__name__)

PredictionId = NewType('PredictionId', int)

try: IMAGE_EMBED_FONT = ImageFont.truetype('FreeSans.ttf', 18)
except Exception: IMAGE_EMBED_FONT = ImageFont.load_default()

MAX_LEGAL_STAKE_CENTS = 5_000_00

class UsernameAlreadyRegisteredError(Exception): pass
class NoSuchUserError(Exception): pass
class BadPasswordError(Exception): pass
class ForgottenTokenError(RuntimeError): pass

def weak_rand_not_in(rng: random.Random, limit: int, xs: Container[int]) -> int:
    result = rng.randrange(0, limit)
    while result in xs:
        result = rng.randrange(0, limit)
    return result

def indent(s: str) -> str:
    return '\n'.join('  '+line for line in s.splitlines())

def get_generic_user_info(wstate: mvp_pb2.WorldState, user: mvp_pb2.UserId) -> Optional[mvp_pb2.WorldState.GenericUserInfo]:
    if user.WhichOneof('kind') == 'username':
        username_info = wstate.username_users.get(user.username)
        return username_info.info if (username_info is not None) else None
    else:
        assert False, f'unrecognized UserId kind: {user!r}'

def user_exists(wstate: mvp_pb2.WorldState, user: mvp_pb2.UserId) -> bool:
    return get_generic_user_info(wstate, user) is not None

def trusts(wstate: mvp_pb2.WorldState, a: mvp_pb2.UserId, b: mvp_pb2.UserId) -> bool:
    if a == b:
        return True
    a_info = get_generic_user_info(wstate, a)
    return (a_info is not None) and b in a_info.trusted_users

def describe_username_problems(username: str) -> Optional[str]:
    if not username:
        return 'username must be non-empty'
    if len(username) > 64:
        return 'username must be no more than 64 characters'
    if not username.isalnum():
        return 'username must be alphanumeric'
    return None

def describe_password_problems(password: str) -> Optional[str]:
    if not password:
        return 'password must be non-empty'
    if len(password) > 256:
        return 'password must not exceed 256 characters, good lord'
    return None

def view_prediction(wstate: mvp_pb2.WorldState, viewer: Optional[mvp_pb2.UserId], ws_prediction: mvp_pb2.WorldState.Prediction) -> mvp_pb2.UserPredictionView:
    creator_is_self = (viewer == ws_prediction.creator)
    return mvp_pb2.UserPredictionView(
        prediction=ws_prediction.prediction,
        certainty=ws_prediction.certainty,
        maximum_stake_cents=ws_prediction.maximum_stake_cents,
        remaining_stake_cents_vs_believers=ws_prediction.maximum_stake_cents - sum(t.creator_stake_cents for t in ws_prediction.trades if not t.bettor_is_a_skeptic),
        remaining_stake_cents_vs_skeptics=ws_prediction.maximum_stake_cents - sum(t.creator_stake_cents for t in ws_prediction.trades if t.bettor_is_a_skeptic),
        created_unixtime=ws_prediction.created_unixtime,
        closes_unixtime=ws_prediction.closes_unixtime,
        resolves_at_unixtime=ws_prediction.resolves_at_unixtime,
        special_rules=ws_prediction.special_rules,
        creator=mvp_pb2.UserUserView(
            display_name=ws_prediction.creator.username if ws_prediction.creator.WhichOneof('kind')=='username' else 'TODO',
            is_self=creator_is_self,
            is_trusted=trusts(wstate, viewer, ws_prediction.creator) if (viewer is not None) else False,
            trusts_you=trusts(wstate, ws_prediction.creator, viewer) if (viewer is not None) else False,
        ),
        resolutions=ws_prediction.resolutions,
        your_trades=[
            mvp_pb2.Trade(
                bettor=t.bettor,
                bettor_is_a_skeptic=t.bettor_is_a_skeptic,
                creator_stake_cents=t.creator_stake_cents,
                bettor_stake_cents=t.bettor_stake_cents,
                transacted_unixtime=t.transacted_unixtime,
            )
            for t in ws_prediction.trades
            if (t.bettor == viewer or creator_is_self)
        ],
    )

class Emailer:
    def __init__(self, username: str, password: str) -> None:
        self._username = username
        self._password = password

    def send(self, *, to: str, subject: str, body: str) -> None:
        send_as = f'{self._username}@gmail.com'
        logger.debug('creating SMTP client')
        with smtplib.SMTP_SSL('smtp.gmail.com') as client:
            client.login(self._username, self._password)
            message = MIMEText(body)
            message['Subject'] = subject
            logger.debug('sending from %s to %s:\n%s', send_as, to, message.as_string())
            client.sendmail(send_as, to, message.as_string())


class TokenMint:

    def __init__(self, secret_key: bytes, clock: Callable[[], float] = time.time) -> None:
        self._secret_key = secret_key
        self._clock = clock

    def _compute_token_hmac(self, token: mvp_pb2.AuthToken) -> bytes:
        scratchpad = copy.copy(token)
        scratchpad.hmac_of_rest = b''
        return hmac.digest(key=self._secret_key, msg=scratchpad.SerializeToString(), digest='sha256')

    def _sign_token(self, token: mvp_pb2.AuthToken) -> None:
        token.hmac_of_rest = self._compute_token_hmac(token=token)

    def mint_token(self, owner: mvp_pb2.UserId, ttl_seconds: int) -> mvp_pb2.AuthToken:
        now = int(self._clock())
        token = mvp_pb2.AuthToken(
            owner=owner,
            minted_unixtime=now,
            expires_unixtime=now + ttl_seconds,
        )
        self._sign_token(token=token)
        return token

    def check_token(self, token: Optional[mvp_pb2.AuthToken]) -> Optional[mvp_pb2.AuthToken]:
        if token is None:
            return None
        now = int(self._clock())
        if not (token.minted_unixtime <= now < token.expires_unixtime):
            return None

        alleged_hmac = token.hmac_of_rest
        true_hmac = self._compute_token_hmac(token)
        if not hmac.compare_digest(alleged_hmac, true_hmac):
            return None

        return token

    def revoke_token(self, token: mvp_pb2.AuthToken) -> None:
        pass  # TODO


class Servicer(abc.ABC):
    def Whoami(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse: pass
    def SignOut(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse: pass
    def RegisterUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse: pass
    def LogInUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse: pass
    def CreatePrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse: pass
    def GetPrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse: pass
    def ListMyPredictions(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListMyPredictionsRequest) -> mvp_pb2.ListMyPredictionsResponse: pass
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse: pass
    def Resolve(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse: pass
    def SetTrusted(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse: pass
    def GetUser(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse: pass
    def ChangePassword(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse: pass
    def SetEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetEmailRequest) -> mvp_pb2.SetEmailResponse: pass
    def VerifyEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.VerifyEmailRequest) -> mvp_pb2.VerifyEmailResponse: pass


def checks_token(f):
    @functools.wraps(f)
    def wrapped(self: 'FsBackedServicer', token: Optional[mvp_pb2.AuthToken], *args, **kwargs):
        token = self._token_mint.check_token(token)
        if (token is not None) and not user_exists(self._get_state(), token.owner):
            raise ForgottenTokenError(token)
        return f(self, token, *args, **kwargs)
    return wrapped

class FsBackedServicer(Servicer):
    def __init__(self, state_path: Path, token_mint: TokenMint, emailer: Emailer, random_seed: Optional[int] = None, clock: Callable[[], float] = time.time) -> None:
        self._state_path = state_path
        self._token_mint = token_mint
        self._emailer = emailer
        self._rng = random.Random(random_seed)
        self._clock = clock

    def _get_state(self) -> mvp_pb2.WorldState:
        result = mvp_pb2.WorldState()
        if self._state_path.exists():
            result.ParseFromString(self._state_path.read_bytes())
        return result
    def _set_state(self, wstate: mvp_pb2.WorldState) -> None:
        bak = self._state_path.with_suffix('.bak')
        bak.write_bytes(wstate.SerializeToString())
        bak.rename(self._state_path)
    @contextlib.contextmanager
    def _mutate_state(self) -> Iterator[mvp_pb2.WorldState]:
        wstate = self._get_state()
        yield wstate
        self._set_state(wstate)

    @checks_token
    def Whoami(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse:
        return mvp_pb2.WhoamiResponse(auth=token)

    @checks_token
    def SignOut(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse:
        if token is not None:
            self._token_mint.revoke_token(token)
        return mvp_pb2.SignOutResponse()

    @checks_token
    def RegisterUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse:
        if token is not None:
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='already authenticated; first, log out'))
        username_problems = describe_username_problems(request.username)
        if username_problems is not None:
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall=username_problems))
        password_problems = describe_password_problems(request.password)
        if password_problems is not None:
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall=password_problems))

        with self._mutate_state() as wstate:
            if request.username in wstate.username_users:
                return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='username taken'))
            wstate.username_users[request.username].MergeFrom(mvp_pb2.WorldState.UsernameInfo(
                password_bcrypt=bcrypt.hashpw(request.password.encode('utf8'), bcrypt.gensalt()),
                info=mvp_pb2.WorldState.GenericUserInfo(trusted_users=[]),
            ))
            return mvp_pb2.RegisterUsernameResponse(ok=self._token_mint.mint_token(owner=mvp_pb2.UserId(username=request.username), ttl_seconds=60*60*24*7))

    @checks_token
    def LogInUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse:
        if token is not None:
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='already authenticated; first, log out'))
        username_problems = describe_username_problems(request.username)
        if username_problems is not None:
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall=username_problems))
        password_problems = describe_password_problems(request.password)
        if password_problems is not None:
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall=password_problems))

        info = self._get_state().username_users.get(request.username)
        if info is None:
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='no such user'))
        if not bcrypt.checkpw(request.password.encode('utf8'), info.password_bcrypt):
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='bad password'))

        token = self._token_mint.mint_token(owner=mvp_pb2.UserId(username=request.username), ttl_seconds=86400)
        return mvp_pb2.LogInUsernameResponse(ok=token)

    @checks_token
    def CreatePrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse:
        if token is None:
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must log in to create predictions'))

        now = int(self._clock())

        if not request.prediction:
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must have a prediction field'))
        if not request.certainty:
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must have a certainty'))
        if not (request.certainty.low < request.certainty.high):
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='certainty must have low < high'))
        if not (request.maximum_stake_cents <= MAX_LEGAL_STAKE_CENTS):
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=f'stake must not exceed ${MAX_LEGAL_STAKE_CENTS//100}'))
        if not (request.open_seconds > 0):
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=f'prediction must be open for a positive number of seconds'))
        if not (request.resolves_at_unixtime > now):
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=f'prediction must resolve in the future'))

        with self._mutate_state() as wstate:
            mid = PredictionId(weak_rand_not_in(self._rng, limit=2**32, xs=wstate.predictions.keys()))
            prediction = mvp_pb2.WorldState.Prediction(
                prediction=request.prediction,
                certainty=request.certainty,
                maximum_stake_cents=request.maximum_stake_cents,
                created_unixtime=now,
                closes_unixtime=now + request.open_seconds,
                resolves_at_unixtime=request.resolves_at_unixtime,
                special_rules=request.special_rules,
                creator=token.owner,
                trades=[],
                resolutions=[],
            )
            wstate.predictions[mid].MergeFrom(prediction)
            return mvp_pb2.CreatePredictionResponse(new_prediction_id=mid)

    @checks_token
    def GetPrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse:
        wstate = self._get_state()
        ws_prediction = wstate.predictions.get(request.prediction_id)
        if ws_prediction is None:
            return mvp_pb2.GetPredictionResponse(error=mvp_pb2.GetPredictionResponse.Error(no_such_prediction=mvp_pb2.VOID))

        return mvp_pb2.GetPredictionResponse(prediction=view_prediction(wstate, (token.owner if token is not None else None), ws_prediction))

    @checks_token
    def ListMyPredictions(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListMyPredictionsRequest) -> mvp_pb2.ListMyPredictionsResponse:
        wstate = self._get_state()
        if token is None:
            return mvp_pb2.ListMyPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions={}))

        result = {
            prediction_id: view_prediction(wstate, (token.owner if token is not None else None), prediction)
            for prediction_id, prediction in wstate.predictions.items()
            if prediction.creator == token.owner or any(trade.bettor == token.owner for trade in prediction.trades)
        }

        return mvp_pb2.ListMyPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions=result))

    @checks_token
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse:
        if token is None:
            return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='must log in to bet'))
        assert request.bettor_stake_cents >= 0, 'protobuf should enforce this being a uint, but just in case...'

        with self._mutate_state() as wstate:
            prediction = wstate.predictions.get(request.prediction_id)
            if prediction is None:
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='no such prediction'))
            if not trusts(wstate, prediction.creator, token.owner):
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="creator doesn't trust you"))
            if not trusts(wstate, token.owner, prediction.creator):
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="you don't trust the creator"))
            if request.bettor_is_a_skeptic:
                lowP = prediction.certainty.low
                creator_stake_cents = int(request.bettor_stake_cents * lowP/(1-lowP))
                existing_stake = sum(t.creator_stake_cents for t in prediction.trades if t.bettor_is_a_skeptic)
                if existing_stake + creator_stake_cents > prediction.maximum_stake_cents:
                    return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='bet would exceed creator tolerance'))
            else:
                highP = prediction.certainty.high
                creator_stake_cents = int(request.bettor_stake_cents * (1-highP)/highP)
                existing_stake = sum(t.creator_stake_cents for t in prediction.trades if not t.bettor_is_a_skeptic)
            if existing_stake + creator_stake_cents > prediction.maximum_stake_cents:
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'bet would exceed creator tolerance ({existing_stake} existing + {creator_stake_cents} new stake > {prediction.maximum_stake_cents} max)'))
            existing_bettor_exposure = sum(t.bettor_stake_cents for t in prediction.trades if t.bettor == token.owner and t.bettor_is_a_skeptic == request.bettor_is_a_skeptic)
            if existing_bettor_exposure + request.bettor_stake_cents > MAX_LEGAL_STAKE_CENTS:
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'your existing stake of ~${existing_bettor_exposure//100} plus your new stake ~${request.bettor_stake_cents//100} cents would put you over the limit of ${MAX_LEGAL_STAKE_CENTS//100} staked in a single prediction'))
            prediction.trades.append(mvp_pb2.Trade(
                bettor=token.owner,
                bettor_is_a_skeptic=request.bettor_is_a_skeptic,
                creator_stake_cents=creator_stake_cents,
                bettor_stake_cents=request.bettor_stake_cents,
                transacted_unixtime=int(self._clock()),
            ))
            return mvp_pb2.StakeResponse(ok=mvp_pb2.VOID)

    @checks_token
    def Resolve(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse:
        if token is None:
            return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='must log in to bet'))

        with self._mutate_state() as wstate:
            prediction = wstate.predictions.get(request.prediction_id)
            if prediction is None:
                return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='no such prediction'))
            if token.owner != prediction.creator:
                return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall="you are not the creator"))
            prediction.resolutions.append(mvp_pb2.ResolutionEvent(unixtime=int(self._clock()), resolution=request.resolution, notes=request.notes))
            return mvp_pb2.ResolveResponse(ok=mvp_pb2.VOID)

    @checks_token
    def SetTrusted(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse:
        if token is None:
            return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='must log in to trust folks'))

        with self._mutate_state() as wstate:
            requester_info = get_generic_user_info(wstate, token.owner)
            if requester_info is None:
                raise ForgottenTokenError(token)
            if not user_exists(wstate, request.who):
                return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='no such user'))
            if request.trusted and request.who not in requester_info.trusted_users:
                requester_info.trusted_users.append(request.who)
            elif not request.trusted and request.who in requester_info.trusted_users:
                requester_info.trusted_users.remove(request.who)
            return mvp_pb2.SetTrustedResponse(ok=mvp_pb2.VOID)

    @checks_token
    def GetUser(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse:
        wstate = self._get_state()
        if not user_exists(wstate, request.who):
            return mvp_pb2.GetUserResponse(error=mvp_pb2.GetUserResponse.Error(catchall='no such user'))

        assert request.who.WhichOneof('kind') == 'username'  # TODO: add oauth
        display_name = request.who.username

        return mvp_pb2.GetUserResponse(ok=mvp_pb2.UserUserView(
            display_name=display_name,
            is_self=(token is not None) and (token.owner == request.who),
            is_trusted=trusts(wstate, token.owner, request.who) if (token is not None) else False,
            trusts_you=trusts(wstate, request.who, token.owner) if (token is not None) else False,
        ))

    @checks_token
    def ChangePassword(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse:
        if token is None:
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='must log in to change your password'))
        if token.owner.WhichOneof('kind') != 'username':
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='only username-authenticated users have passwords'))
        password_problems = describe_password_problems(request.new_password)
        if password_problems is not None:
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall=password_problems))

        with self._mutate_state() as wstate:
            info = wstate.username_users.get(token.owner.username)
            if info is None:
                raise ForgottenTokenError(token)

            if not bcrypt.checkpw(request.old_password.encode('utf8'), info.password_bcrypt):
                return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='bad password'))

            info.password_bcrypt = bcrypt.hashpw(request.new_password.encode('utf8'), bcrypt.gensalt())

            return mvp_pb2.ChangePasswordResponse(ok=mvp_pb2.VOID)

    @checks_token
    def SetEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetEmailRequest) -> mvp_pb2.SetEmailResponse:
        if token is None:
            return mvp_pb2.SetEmailResponse(error=mvp_pb2.SetEmailResponse.Error(catchall='must log in to set an email'))

        # TODO: prevent an email address from getting "too many" emails if somebody abuses us
        code = secrets.token_urlsafe(nbytes=16)
        self._emailer.send(
            to=request.email,
            subject='Your Biatob email-verification',
            body=f"Here's your code: {code}",  # TODO: handle abuse
        )  # TODO: this blocks the event loop; toss it to another thread?

        with self._mutate_state() as wstate:
            requester_info = get_generic_user_info(self._get_state(), token.owner)
            if requester_info is None:
                raise ForgottenTokenError(token)
            requester_info.email.MergeFrom(mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email=request.email, code_bcrypt=bcrypt.hashpw(code.encode('ascii'), bcrypt.gensalt()))))
            wstate.username_users[token.owner.username].info.MergeFrom(requester_info) # TODO: hack
            return mvp_pb2.SetEmailResponse(ok=mvp_pb2.VOID)

    @checks_token
    def VerifyEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.VerifyEmailRequest) -> mvp_pb2.VerifyEmailResponse:
        if token is None:
            return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='must log in to change your password'))

        with self._mutate_state() as wstate:
            requester_info = get_generic_user_info(self._get_state(), token.owner)
            if requester_info is None:
                raise ForgottenTokenError(token)
            if not (requester_info.email and requester_info.email.WhichOneof('email_flow_state_kind') == 'code_sent'):
                return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='you have no pending email-verification flow'))
            code_sent_state = requester_info.email.code_sent
            if not bcrypt.checkpw(request.code.encode('ascii'), code_sent_state.code_bcrypt):
                return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='bad code'))
            requester_info.email.Clear()
            requester_info.email.MergeFrom(mvp_pb2.EmailFlowState(verified=code_sent_state.email))
            return mvp_pb2.VerifyEmailResponse(verified_email=code_sent_state.email)


from typing import TypeVar, Type, Tuple, Union, Awaitable
from google.protobuf.message import Message
_Req = TypeVar('_Req', bound=Message)
_Resp = TypeVar('_Resp', bound=Message)
def proto_handler(req_t: Type[_Req], resp_t: Type[_Resp]):
    def wrap(f: Callable[[web.Request, _Req], Awaitable[Tuple[web.Response, _Resp]]]) -> Callable[[web.Request], Awaitable[web.Response]]:
        async def wrapped(http_req: web.Request) -> web.Response:
            pb_req = req_t()
            pb_req.ParseFromString(await http_req.content.read())
            (http_resp, pb_resp) = await f(http_req, pb_req)
            http_resp.content_type = 'application/octet-stream'
            http_resp.body = pb_resp.SerializeToString()
            return http_resp
        return wrapped
    return wrap

async def parse_proto(http_req: web.Request, pb_req_cls: Type[_Req]) -> _Req:
    req = pb_req_cls()
    req.ParseFromString(await http_req.content.read())
    return req
def proto_response(pb_resp: _Resp) -> web.Response:
    return web.Response(status=200, headers={'Content-Type':'application/octet-stream'}, body=pb_resp.SerializeToString())


class HttpTokenGlue:

    _AUTH_COOKIE_NAME = 'auth'

    def __init__(self, token_mint: TokenMint):
        self._mint = token_mint
        self._ctxvar: contextvars.ContextVar[Optional[mvp_pb2.AuthToken]] = contextvars.ContextVar('token', default=None)

    def add_to_app(self, app: web.Application) -> None:
        if self.middleware not in app.middlewares:
            app.middlewares.append(self.middleware)

    def get(self):
        return self._ctxvar.get()

    @web.middleware
    async def middleware(self, request, handler):
        ctxtok = self._ctxvar.set(self.parse_cookie(request))
        try:
            return await handler(request)
        except ForgottenTokenError:
            response = web.HTTPInternalServerError(reason="I, uh, may have accidentally obliterated your entire account. Crap. I'm sorry.")
            self.del_cookie(request, response)
            return response
        finally:
            self._ctxvar.reset(ctxtok)

    def set_cookie(self, token: mvp_pb2.AuthToken, response: web.Response) -> mvp_pb2.AuthToken:
        response.set_cookie(self._AUTH_COOKIE_NAME, base64.b64encode(token.SerializeToString()).decode('ascii'))
        return token

    def del_cookie(self, req: web.Request, resp: web.Response) -> None:
        token = self.parse_cookie(req)
        if token is not None:
            self._mint.revoke_token(token)
        resp.del_cookie(self._AUTH_COOKIE_NAME)

    def parse_cookie(self, req: web.Request) -> Optional[mvp_pb2.AuthToken]:
        cookie = req.cookies.get(self._AUTH_COOKIE_NAME)
        if cookie is None:
            return None
        try:
            token_bytes = base64.b64decode(cookie)
        except ValueError:
            return None

        token = mvp_pb2.AuthToken()
        token.ParseFromString(token_bytes)
        return self._mint.check_token(token)


class ApiServer:

    def __init__(self, token_glue: HttpTokenGlue, servicer: Servicer, clock: Callable[[], float] = time.time) -> None:
        self._token_glue = token_glue
        self._servicer = servicer
        self._clock = clock

    def add_to_app(self, app: web.Application) -> None:
        routes = web.RouteTableDef()

        @routes.post('/api/Whoami')
        async def api_Whoami(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.Whoami(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.WhoamiRequest)))
        @routes.post('/api/SignOut')
        async def api_SignOut(http_req: web.Request) -> web.Response:
            http_resp = proto_response(self._servicer.SignOut(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.SignOutRequest)))
            self._token_glue.del_cookie(http_req, http_resp)
            return http_resp
        @routes.post('/api/RegisterUsername')
        async def api_RegisterUsername(http_req: web.Request) -> web.Response:
            pb_resp = self._servicer.RegisterUsername(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.RegisterUsernameRequest))
            http_resp = proto_response(pb_resp)
            if pb_resp.WhichOneof('register_username_result') == 'ok':
                self._token_glue.set_cookie(pb_resp.ok, http_resp)
            return http_resp
        @routes.post('/api/LogInUsername')
        async def api_LogInUsername(http_req: web.Request) -> web.Response:
            pb_resp = self._servicer.LogInUsername(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.LogInUsernameRequest))
            http_resp = proto_response(pb_resp)
            if pb_resp.WhichOneof('log_in_username_result') == 'ok':
                self._token_glue.set_cookie(pb_resp.ok, http_resp)
            return http_resp
        @routes.post('/api/CreatePrediction')
        async def api_CreatePrediction(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.CreatePrediction(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.CreatePredictionRequest)))
        @routes.post('/api/GetPrediction')
        async def api_GetPrediction(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.GetPrediction(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.GetPredictionRequest)))
        @routes.post('/api/Stake')
        async def api_Stake(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.Stake(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.StakeRequest)))
        @routes.post('/api/Resolve')
        async def api_Resolve(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.Resolve(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.ResolveRequest)))
        @routes.post('/api/SetTrusted')
        async def api_SetTrusted(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.SetTrusted(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.SetTrustedRequest)))
        @routes.post('/api/GetUser')
        async def api_GetUser(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.GetUser(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.GetUserRequest)))
        @routes.post('/api/ChangePassword')
        async def api_ChangePassword(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.ChangePassword(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.ChangePasswordRequest)))
        @routes.post('/api/SetEmail')
        async def api_SetEmail(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.SetEmail(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.SetEmailRequest)))
        @routes.post('/api/VerifyEmail')
        async def api_VerifyEmail(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.VerifyEmail(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.VerifyEmailRequest)))

        self._token_glue.add_to_app(app)
        app.add_routes(routes)


_HERE = Path(__file__).parent
class WebServer:
    def __init__(self, servicer: Servicer, elm_dist: Path, token_glue: HttpTokenGlue) -> None:
        self._servicer = servicer
        self._elm_dist = elm_dist
        self._token_glue = token_glue

    async def get_static(self, req: web.Request) -> web.StreamResponse:
        filename = req.match_info['filename']
        if (not filename) or filename.startswith('.'):
            raise web.HTTPBadRequest()
        return web.FileResponse(_HERE/'static'/filename)  # type: ignore

    async def get_elm_module(self, req: web.Request) -> web.Response:
        module = req.match_info['module']
        return web.Response(content_type='text/javascript', body=(_HERE.parent/f'elm/dist/{module}.js').read_text()) # type: ignore

    async def get_index(self, req: web.Request) -> web.StreamResponse:
        auth = self._token_glue.get()
        if auth is None:
            return await self.get_welcome(req)
        else:
            return await self.get_my_predictions(req)

    async def get_welcome(self, req: web.Request) -> web.Response:
        auth = self._token_glue.get()
        return web.Response(
            content_type='text/html',
            body=(_HERE/'templates'/'Welcome.html').read_text()
                    .replace(r'{{auth_token_pb_b64}}', pb_b64_json(auth) if auth else 'null'))

    async def get_create_prediction_page(self, req: web.Request) -> web.Response:
        auth = self._token_glue.get()
        return web.Response(
            content_type='text/html',
            body=(_HERE/'templates'/'CreatePredictionPage.html').read_text()
                    .replace(r'{{auth_token_pb_b64}}', pb_b64_json(auth) if auth else 'null'))

    async def get_view_prediction_page(self, req: web.Request) -> web.Response:
        auth = self._token_glue.get()
        prediction_id = int(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        return web.Response(
            content_type='text/html',
            body=(_HERE/'templates'/'ViewPredictionPage.html').read_text()
                    .replace(r'{{auth_token_pb_b64}}', pb_b64_json(auth) if auth else 'null')
                    .replace(r'{{prediction_pb_b64}}', pb_b64_json(get_prediction_resp.prediction))
                    .replace(r'{{prediction_id}}', str(prediction_id)))

    async def get_prediction_img_embed(self, req: web.Request) -> web.Response:
        auth = self._token_glue.get()
        prediction_id = int(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        def format_cents(n: int) -> str:
            if n < 0: return '-' + format_cents(-n)
            return f'${n//100}' + ('' if n%100 == 0 else f'.{n%100 :02d}')
        prediction = get_prediction_resp.prediction
        text = f'[{format_cents(prediction.maximum_stake_cents)} @ {round(prediction.certainty.low*100)}-{round(prediction.certainty.high*100)}%]'
        size = IMAGE_EMBED_FONT.getsize(text)
        img = Image.new('RGBA', size, color=(255,255,255,0))
        ImageDraw.Draw(img).text((0,0), text, fill=(0,128,0,255), font=IMAGE_EMBED_FONT)
        buf = io.BytesIO()
        img.save(buf, format='png')
        return web.Response(content_type='image/png', body=buf.getvalue())

    async def get_my_predictions(self, req: web.Request) -> web.Response:
        auth = self._token_glue.get()
        list_my_predictions_resp = self._servicer.ListMyPredictions(auth, mvp_pb2.ListMyPredictionsRequest())
        if list_my_predictions_resp.WhichOneof('list_my_predictions_result') == 'error':
            return web.Response(status=400, body=str(list_my_predictions_resp.error))
        assert list_my_predictions_resp.WhichOneof('list_my_predictions_result') == 'ok'
        return web.Response(
            content_type='text/html',
            body=(_HERE/'templates'/'MyPredictionsPage.html').read_text()
                        .replace(r'{{auth_token_pb_b64}}', pb_b64_json(auth) if auth else 'null')
                        .replace(r'{{predictions_pb_b64}}', pb_b64_json(list_my_predictions_resp.ok)))

    async def get_username(self, req: web.Request) -> web.Response:
        auth = self._token_glue.get()
        user_id = mvp_pb2.UserId(username=req.match_info['username'])
        get_user_resp = self._servicer.GetUser(auth, mvp_pb2.GetUserRequest(who=user_id))
        if get_user_resp.WhichOneof('get_user_result') == 'error':
            return web.Response(status=400, body=str(get_user_resp.error))
        assert get_user_resp.WhichOneof('get_user_result') == 'ok'
        email_flow = mvp_pb2.EmailFlowState()  # TODO
        return web.Response(
            content_type='text/html',
            body=(_HERE/'templates'/'ViewUserPage.html').read_text()
                        .replace(r'{{auth_token_pb_b64}}', pb_b64_json(auth) if auth else 'null')
                        .replace(r'{{userViewPbB64}}', pb_b64_json(get_user_resp.ok))
                        .replace(r'{{userIdPbB64}}', pb_b64_json(user_id))
                        .replace(r'{{emailFlowPbB64}}', pb_b64_json(email_flow))  # TODO: I really don't like how this unfiltered piece of server state gets passed to the client
                        )

    def add_to_app(self, app: web.Application) -> None:

        self._token_glue.add_to_app(app)

        app.router.add_get('/', self.get_index)
        app.router.add_get('/static/{filename}', self.get_static)
        app.router.add_get('/elm/{module}.js', self.get_elm_module)
        app.router.add_get('/welcome', self.get_welcome)
        app.router.add_get('/new', self.get_create_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}', self.get_view_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}/embed.png', self.get_prediction_img_embed)
        app.router.add_get('/my_predictions', self.get_my_predictions)
        app.router.add_get('/username/{username:[a-zA-Z0-9_-]+}', self.get_username)


def pb_b64_json(message: Message) -> str:
    return json.dumps(base64.b64encode(message.SerializeToString()).decode('ascii'))

parser = argparse.ArgumentParser()
parser.add_argument("-H", "--host", default="localhost")
parser.add_argument("-p", "--port", type=int, default=8080)
parser.add_argument("--elm-dist", type=Path, default="elm/dist")
parser.add_argument("--state-path", type=Path, required=True)
parser.add_argument("--credentials-path", type=Path, required=True)

if __name__ == '__main__':
    args = parser.parse_args()
    app = web.Application()

    credentials = google.protobuf.text_format.Parse(args.credentials_path.read_text(), mvp_pb2.CredentialsConfig())

    emailer = Emailer(username=credentials.smtp_username, password=credentials.smtp_password)
    token_mint = TokenMint(secret_key=credentials.token_signing_secret)
    token_glue = HttpTokenGlue(token_mint=token_mint)
    servicer = FsBackedServicer(state_path=args.state_path, token_mint=token_mint, emailer=emailer)

    token_glue.add_to_app(app)
    WebServer(
        token_glue=token_glue,
        elm_dist=args.elm_dist,
        servicer=servicer,
    ).add_to_app(app)
    ApiServer(
        token_glue=token_glue,
        servicer=servicer,
    ).add_to_app(app)

    web.run_app(app, host=args.host, port=args.port)
