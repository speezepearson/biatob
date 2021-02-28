#! /usr/bin/env python3
# TODO: flock over the database file

import abc
import argparse
import asyncio
import base64
import contextlib
import copy
import datetime
import filelock  # type: ignore
import functools
import hashlib
import hmac
import io
import json
from pathlib import Path
import random
import secrets
import string
import sys
import tempfile
import time
from typing import Iterator, Optional, Container, NewType, Callable, NoReturn, Tuple, Iterable, Sequence, TypeVar
import argparse
import logging
import os
import smtplib
from email.message import EmailMessage

import jinja2
from PIL import Image, ImageDraw, ImageFont  # type: ignore
from aiohttp import web
import google.protobuf.text_format  # type: ignore
from google.protobuf.message import Message
import aiosmtplib

from .protobuf import mvp_pb2

# adapted from https://www.structlog.org/en/stable/examples.html?highlight=json#processors
# and https://www.structlog.org/en/stable/contextvars.html
import structlog
import structlog.processors
import structlog.contextvars
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,  # type: ignore
        structlog.processors.TimeStamper(),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.JSONRenderer(sort_keys=True),
    ]
)
logger = structlog.get_logger()

PredictionId = NewType('PredictionId', int)

try: IMAGE_EMBED_FONT = ImageFont.truetype('FreeSans.ttf', 18)
except Exception: IMAGE_EMBED_FONT = ImageFont.load_default()

@functools.lru_cache(maxsize=256)
def render_text(text: str, file_format: str = 'png') -> bytes:
    size = IMAGE_EMBED_FONT.getsize(text)
    img = Image.new('RGBA', size, color=(255,255,255,0))
    ImageDraw.Draw(img).text((0,0), text, fill=(0,128,0,255), font=IMAGE_EMBED_FONT)
    buf = io.BytesIO()
    img.save(buf, format=file_format)
    return buf.getvalue()

MAX_LEGAL_STAKE_CENTS = 5_000_00

class UsernameAlreadyRegisteredError(Exception): pass
class NoSuchUserError(Exception): pass
class BadPasswordError(Exception): pass
class ForgottenTokenError(RuntimeError): pass

def secret_eq(a: bytes, b: bytes) -> bool:
    return len(a) == len(b) and all(a[i]==b[i] for i in range(len(a)))
def scrypt(password: str, salt: bytes) -> bytes:
    return hashlib.scrypt(password.encode('utf8'), salt=salt, n=16384, r=8, p=1)
def new_hashed_password(password: str) -> mvp_pb2.HashedPassword:
    salt = secrets.token_bytes(4)
    return mvp_pb2.HashedPassword(salt=salt, scrypt=scrypt(password, salt))
def check_password(password: str, hashed: mvp_pb2.HashedPassword) -> bool:
    return secret_eq(hashed.scrypt, scrypt(password, hashed.salt))

def weak_rand_not_in(rng: random.Random, limit: int, xs: Container[int]) -> int:
    result = rng.randrange(0, limit)
    while result in xs:
        result = rng.randrange(0, limit)
    return result

def indent(s: str) -> str:
    return '\n'.join('  '+line for line in s.splitlines())

def get_generic_user_info(wstate: mvp_pb2.WorldState, user: mvp_pb2.UserId) -> Optional[mvp_pb2.GenericUserInfo]:
    if user.WhichOneof('kind') == 'username':
        username_info = wstate.username_users.get(user.username)
        return username_info.info if (username_info is not None) else None
    else:
        logger.warn('unrecognized UserId kind', user=user)
        return None

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

_M = TypeVar('_M', bound=Message)
def unique_protos(messages: Iterable[_M]) -> Sequence[_M]:
    result = []
    seen_ser = set()
    for m in messages:
        ser = m.SerializeToString()
        if ser not in seen_ser:
            seen_ser.add(ser)
            result.append(copy.deepcopy(m))
    return result


class FsStorage:
    def __init__(self, state_path: Path):
        self._state_path = state_path

    @property
    def _lock(self) -> filelock.FileLock:
        return filelock.FileLock(self._state_path.with_suffix(self._state_path.suffix + '.lock'))
    def _get_nolock(self) -> mvp_pb2.WorldState:
        result = mvp_pb2.WorldState()
        if self._state_path.exists():
            result.ParseFromString(self._state_path.read_bytes())
        return result
    def _put_nolock(self, wstate: mvp_pb2.WorldState) -> None:
        path = Path(tempfile.mktemp(suffix='.WorldState.pb'))
        path.write_bytes(wstate.SerializeToString())
        path.rename(self._state_path)


    def get(self) -> mvp_pb2.WorldState:
        with self._lock:
            return self._get_nolock()

    def put(self, wstate: mvp_pb2.WorldState) -> None:
        with self._lock:
            self._put_nolock(wstate)

    @contextlib.contextmanager
    def mutate(self) -> Iterator[mvp_pb2.WorldState]:
        with self._lock:
            wstate = self._get_nolock()
            yield wstate
            self._put_nolock(wstate)


class Emailer:
    def __init__(
        self,
        hostname: str,
        port: int,
        username: str,
        password: str,
        from_addr: str,
        *,
        aiosmtplib_for_testing=aiosmtplib,
    ) -> None:
        self._hostname = hostname
        self._port = port
        self._username = username
        self._password = password
        self._from_addr = from_addr
        self._aiosmtplib = aiosmtplib_for_testing

    async def send(self, *, to: str, subject: str, body: str, content_type: str = 'text/html') -> None:
        # adapted from https://aiosmtplib.readthedocs.io/en/stable/usage.html#authentication
        message = EmailMessage()
        message["From"] = self._from_addr
        message["To"] = to
        message["Subject"] = subject
        message.set_content(body)
        message.set_type(content_type)
        await self._aiosmtplib.send(
            message=message,
            hostname=self._hostname,
            port=self._port,
            username=self._username,
            password=self._password,
            use_tls=True,
        )
        logger.info('sent email', subject=subject, to=to)


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
    def ListMyStakes(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListMyStakesRequest) -> mvp_pb2.ListMyStakesResponse: pass
    def ListPredictions(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.ListPredictionsResponse: pass
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse: pass
    def Resolve(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse: pass
    def SetTrusted(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse: pass
    def GetUser(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse: pass
    def ChangePassword(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse: pass
    def SetEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetEmailRequest) -> mvp_pb2.SetEmailResponse: pass
    def VerifyEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.VerifyEmailRequest) -> mvp_pb2.VerifyEmailResponse: pass
    def GetSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GetSettingsResponse: pass
    def UpdateSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.UpdateSettingsRequest) -> mvp_pb2.UpdateSettingsResponse: pass
    def CreateInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreateInvitationRequest) -> mvp_pb2.CreateInvitationResponse: pass
    def AcceptInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.AcceptInvitationResponse: pass


def checks_token(f):
    @functools.wraps(f)
    def wrapped(self: 'FsBackedServicer', token: Optional[mvp_pb2.AuthToken], *args, **kwargs):
        token = self._token_mint.check_token(token)
        if (token is not None) and not user_exists(self._storage.get(), token.owner):
            raise ForgottenTokenError(token)
        structlog.contextvars.bind_contextvars(actor=token.owner if (token is not None) else None)
        try:
            return f(self, token, *args, **kwargs)
        finally:
            structlog.contextvars.unbind_contextvars('actor')
    return wrapped
def log_action(f):
    @functools.wraps(f)
    def wrapped(*args, **kwargs):
        structlog.contextvars.bind_contextvars(servicer_action=f.__name__)
        try:
            return f(*args, **kwargs)
        finally:
            structlog.contextvars.unbind_contextvars('servicer_action')
    return wrapped

class FsBackedServicer(Servicer):
    def __init__(self, storage: FsStorage, token_mint: TokenMint, emailer: Emailer, random_seed: Optional[int] = None, clock: Callable[[], float] = time.time) -> None:
        self._storage = storage
        self._token_mint = token_mint
        self._emailer = emailer
        self._rng = random.Random(random_seed)
        self._clock = clock

    @checks_token
    @log_action
    def Whoami(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse:
        return mvp_pb2.WhoamiResponse(auth=token)

    @checks_token
    @log_action
    def SignOut(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse:
        if token is not None:
            self._token_mint.revoke_token(token)
        return mvp_pb2.SignOutResponse()

    @checks_token
    @log_action
    def RegisterUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse:
        if token is not None:
            logger.warn('logged-in user trying to register a username', new_username=request.username)
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='already authenticated; first, log out'))
        username_problems = describe_username_problems(request.username)
        if username_problems is not None:
            logger.debug('trying to register bad username', username=request.username)
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall=username_problems))
        password_problems = describe_password_problems(request.password)
        if password_problems is not None:
            logger.debug('trying to register with a bad password', username=request.username)
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall=password_problems))

        with self._storage.mutate() as wstate:
            if request.username in wstate.username_users:
                logger.info('username taken', username=request.username)
                return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='username taken'))

            logger.info('registering username', username=request.username)
            wstate.username_users[request.username].MergeFrom(mvp_pb2.UsernameInfo(
                password=new_hashed_password(request.password),
                info=mvp_pb2.GenericUserInfo(trusted_users=[]),
            ))
            return mvp_pb2.RegisterUsernameResponse(ok=self._token_mint.mint_token(owner=mvp_pb2.UserId(username=request.username), ttl_seconds=60*60*24*7))

    @checks_token
    @log_action
    def LogInUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse:
        if token is not None:
            logger.warn('logged-in user trying to log in again', new_username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='already authenticated; first, log out'))
        username_problems = describe_username_problems(request.username)

        info = self._storage.get().username_users.get(request.username)
        if info is None:
            logger.debug('login attempt for nonexistent user', username=request.username)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='no such user'))
        if not check_password(request.password, info.password):
            logger.info('login attempt has bad password', possible_malice=True)
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='bad password'))

        logger.debug('username logged in', username=request.username)
        token = self._token_mint.mint_token(owner=mvp_pb2.UserId(username=request.username), ttl_seconds=86400)
        return mvp_pb2.LogInUsernameResponse(ok=token)

    @checks_token
    @log_action
    def CreatePrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must log in to create predictions'))

        now = int(self._clock())

        if not request.prediction:
            logger.warn('invalid CreatePredictionRequest', request=request)
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must have a prediction field'))
        if not request.certainty:
            logger.warn('invalid CreatePredictionRequest', request=request)
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='must have a certainty'))
        if not (request.certainty.low <= request.certainty.high):
            logger.warn('invalid CreatePredictionRequest', request=request)
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall='certainty must have low <= high'))
        if not (request.maximum_stake_cents <= MAX_LEGAL_STAKE_CENTS):
            logger.warn('invalid CreatePredictionRequest', request=request)
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=f'stake must not exceed ${MAX_LEGAL_STAKE_CENTS//100}'))
        if not (request.open_seconds > 0):
            logger.warn('invalid CreatePredictionRequest', request=request)
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=f'prediction must be open for a positive number of seconds'))
        if not (request.resolves_at_unixtime > now):
            logger.warn('invalid CreatePredictionRequest', request=request)
            return mvp_pb2.CreatePredictionResponse(error=mvp_pb2.CreatePredictionResponse.Error(catchall=f'prediction must resolve in the future'))

        with self._storage.mutate() as wstate:
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
            logger.debug('creating prediction', prediction_id=mid, prediction=prediction)
            wstate.predictions[mid].MergeFrom(prediction)
            return mvp_pb2.CreatePredictionResponse(new_prediction_id=mid)

    @checks_token
    @log_action
    def GetPrediction(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse:
        wstate = self._storage.get()
        ws_prediction = wstate.predictions.get(request.prediction_id)
        if ws_prediction is None:
            logger.info('trying to get nonexistent prediction', prediction_id=request.prediction_id)
            return mvp_pb2.GetPredictionResponse(error=mvp_pb2.GetPredictionResponse.Error(no_such_prediction=mvp_pb2.VOID))

        return mvp_pb2.GetPredictionResponse(prediction=view_prediction(wstate, (token.owner if token is not None else None), ws_prediction))

    @checks_token
    @log_action
    def ListMyStakes(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListMyStakesRequest) -> mvp_pb2.ListMyStakesResponse:
        if token is None:
            logger.info('logged-out user trying to list their predictions')
            return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions={}))

        wstate = self._storage.get()
        result = {
            prediction_id: view_prediction(wstate, (token.owner if token is not None else None), prediction)
            for prediction_id, prediction in wstate.predictions.items()
            if prediction.creator == token.owner or any(trade.bettor == token.owner for trade in prediction.trades)
        }

        return mvp_pb2.ListMyStakesResponse(ok=mvp_pb2.PredictionsById(predictions=result))

    @checks_token
    @log_action
    def ListPredictions(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.ListPredictionsResponse:
        if token is None:
            logger.info('logged-out user trying to list predictions')
            return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions={}))
        creator = request.creator if (request.creator is not None) else token.owner

        wstate = self._storage.get()
        if not trusts(wstate, creator, token.owner):
            logger.info('trying to get list untrusting creator\'s predictions', creator=creator)
            return mvp_pb2.ListPredictionsResponse(error=mvp_pb2.ListPredictionsResponse.Error(catchall="creator doesn't trust you"))

        result = {
            prediction_id: view_prediction(wstate, (token.owner if token is not None else None), prediction)
            for prediction_id, prediction in wstate.predictions.items()
            if prediction.creator == creator
        }

        return mvp_pb2.ListPredictionsResponse(ok=mvp_pb2.PredictionsById(predictions=result))

    @checks_token
    @log_action
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='must log in to bet'))
        assert request.bettor_stake_cents >= 0, 'protobuf should enforce this being a uint, but just in case...'

        with self._storage.mutate() as wstate:
            prediction = wstate.predictions.get(request.prediction_id)
            if prediction is None:
                logger.warn('trying to bet on nonexistent prediction', prediction_id=request.prediction_id)
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='no such prediction'))
            if prediction.creator == token.owner:
                logger.warn('trying to bet against self', prediction_id=request.prediction_id)
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="can't bet against yourself"))
            if not trusts(wstate, prediction.creator, token.owner):
                logger.warn('trying to bet against untrusting creator', prediction_id=request.prediction_id, possible_malice=True)
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="creator doesn't trust you"))
            if not trusts(wstate, token.owner, prediction.creator):
                logger.warn('trying to bet against untrusted creator', prediction_id=request.prediction_id)
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall="you don't trust the creator"))
            if request.bettor_is_a_skeptic:
                lowP = prediction.certainty.low
                creator_stake_cents = int(request.bettor_stake_cents * lowP/(1-lowP))
                existing_stake = sum(t.creator_stake_cents for t in prediction.trades if t.bettor_is_a_skeptic)
            else:
                highP = prediction.certainty.high
                creator_stake_cents = int(request.bettor_stake_cents * (1-highP)/highP)
                existing_stake = sum(t.creator_stake_cents for t in prediction.trades if not t.bettor_is_a_skeptic)
            if existing_stake + creator_stake_cents > prediction.maximum_stake_cents:
                logger.warn('trying to make a bet that would exceed creator tolerance', request=request)
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'bet would exceed creator tolerance ({existing_stake} existing + {creator_stake_cents} new stake > {prediction.maximum_stake_cents} max)'))
            sameside_prior_trades = [t for t in prediction.trades if t.bettor == token.owner and t.bettor_is_a_skeptic == request.bettor_is_a_skeptic]
            existing_bettor_exposure = sum(t.bettor_stake_cents for t in sameside_prior_trades)
            if existing_bettor_exposure + request.bettor_stake_cents > MAX_LEGAL_STAKE_CENTS:
                logger.warn('trying to make a bet that would exceed per-market stake limit', request=request, sameside_prior_trades=sameside_prior_trades)
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'your existing stake of ~${existing_bettor_exposure//100} plus your new stake ~${request.bettor_stake_cents//100} cents would put you over the limit of ${MAX_LEGAL_STAKE_CENTS//100} staked in a single prediction'))
            prediction.trades.append(mvp_pb2.Trade(
                bettor=token.owner,
                bettor_is_a_skeptic=request.bettor_is_a_skeptic,
                creator_stake_cents=creator_stake_cents,
                bettor_stake_cents=request.bettor_stake_cents,
                transacted_unixtime=int(self._clock()),
            ))
            logger.info('trade executed', prediction_id=request.prediction_id, trade=str(prediction.trades[-1]))
            return mvp_pb2.StakeResponse(ok=view_prediction(wstate, token.owner, prediction))

    @checks_token
    @log_action
    def Resolve(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='must log in to resolve a prediction'))
        if request.resolution not in {mvp_pb2.RESOLUTION_YES, mvp_pb2.RESOLUTION_NO, mvp_pb2.RESOLUTION_INVALID, mvp_pb2.RESOLUTION_NONE_YET}:
            logger.warn('user sent unrecognized resolution', resolution=request.resolution)
            return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='unrecognized resolution'))

        with self._storage.mutate() as wstate:
            prediction = wstate.predictions.get(request.prediction_id)
            if prediction is None:
                logger.info('attempt to resolve nonexistent prediction', prediction_id=request.prediction_id)
                return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall='no such prediction'))
            if token.owner != prediction.creator:
                logger.warn('non-creator trying to resolve prediction', prediction_id=request.prediction_id, creator=prediction.creator, possible_malice=True)
                return mvp_pb2.ResolveResponse(error=mvp_pb2.ResolveResponse.Error(catchall="you are not the creator"))
            prediction.resolutions.append(mvp_pb2.ResolutionEvent(unixtime=int(self._clock()), resolution=request.resolution, notes=request.notes))
            logger.info('prediction resolved', prediction_id=request.prediction_id, resolution=str(request.resolution))

            email_addrs = []
            for stakeholder in unique_protos([prediction.creator, *(trade.bettor for trade in prediction.trades)]):
                info = get_generic_user_info(wstate, stakeholder)
                if info is None:
                    logger.error('prediction references nonexistent user', prediction_id=request.prediction_id, user=stakeholder)
                    continue
                elif info.email_resolution_notifications and info.email.WhichOneof('email_flow_state_kind') == 'verified':
                    email_addrs.append(info.email.verified)

            logger.info('sending resolution emails', prediction_id=request.prediction_id, email_addrs=email_addrs)
            email_body = (
                f'https://biatob.com/p/{request.prediction_id} has resolved YES' if request.resolution == mvp_pb2.RESOLUTION_YES else
                f'https://biatob.com/p/{request.prediction_id} has resolved NO' if request.resolution == mvp_pb2.RESOLUTION_NO else
                f'https://biatob.com/p/{request.prediction_id} has resolved INVALID' if request.resolution == mvp_pb2.RESOLUTION_INVALID else
                f'https://biatob.com/p/{request.prediction_id} has UN-resolved'
            )
            for addr in email_addrs:
                asyncio.create_task(self._emailer.send(
                    to=addr,
                    subject=f'Prediction resolved: {prediction.prediction!r}',
                    body=email_body,
                ))
            logger.debug('finished sending resolution emails', prediction_id=request.prediction_id)
            return mvp_pb2.ResolveResponse(ok=view_prediction(wstate, token.owner, prediction))

    @checks_token
    @log_action
    def SetTrusted(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='must log in to trust folks'))

        with self._storage.mutate() as wstate:
            requester_info = get_generic_user_info(wstate, token.owner)
            if requester_info is None:
                raise ForgottenTokenError(token)
            if not user_exists(wstate, request.who):
                logger.warn('attempting to set trust for nonexistent user')
                return mvp_pb2.SetTrustedResponse(error=mvp_pb2.SetTrustedResponse.Error(catchall='no such user'))
            logger.info('setting user trust', who=str(request.who), trusted=request.trusted)
            if request.trusted and request.who not in requester_info.trusted_users:
                requester_info.trusted_users.append(request.who)
            elif not request.trusted and request.who in requester_info.trusted_users:
                requester_info.trusted_users.remove(request.who)
            return mvp_pb2.SetTrustedResponse(ok=mvp_pb2.UserIds(values=requester_info.trusted_users))

    @checks_token
    @log_action
    def GetUser(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse:
        wstate = self._storage.get()
        if not user_exists(wstate, request.who):
            logger.info('attempting to view nonexistent user', who=request.who)
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
    @log_action
    def ChangePassword(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='must log in to change your password'))
        if token.owner.WhichOneof('kind') != 'username':
            logger.warn('non-username user attempting to set password')
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='only username-authenticated users have passwords'))
        password_problems = describe_password_problems(request.new_password)
        if password_problems is not None:
            logger.warn('attempting to set bad password')
            return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall=password_problems))

        with self._storage.mutate() as wstate:
            info = wstate.username_users.get(token.owner.username)
            if info is None:
                raise ForgottenTokenError(token)

            if not check_password(request.old_password, info.password):
                logger.warn('password-change request has wrong password', possible_malice=True)
                return mvp_pb2.ChangePasswordResponse(error=mvp_pb2.ChangePasswordResponse.Error(catchall='bad password'))

            info.password.CopyFrom(new_hashed_password(request.new_password))

            logger.info('changing password', who=str(token.owner))
            return mvp_pb2.ChangePasswordResponse(ok=mvp_pb2.VOID)

    @checks_token
    @log_action
    def SetEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SetEmailRequest) -> mvp_pb2.SetEmailResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.SetEmailResponse(error=mvp_pb2.SetEmailResponse.Error(catchall='must log in to set an email'))

        # TODO: prevent an email address from getting "too many" emails if somebody abuses us
        code = secrets.token_urlsafe(nbytes=16)
        asyncio.create_task(self._emailer.send(
            to=request.email,
            subject='Your Biatob email-verification',
            body=f"Here's your code: {code}",  # TODO: handle abuse
        ))

        with self._storage.mutate() as wstate:
            requester_info = get_generic_user_info(wstate, token.owner)
            if requester_info is None:
                raise ForgottenTokenError(token)
            requester_info.email.MergeFrom(mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email=request.email, code=new_hashed_password(code))))
            wstate.username_users[token.owner.username].info.CopyFrom(requester_info) # TODO: hack
            logger.info('set email address', who=str(token.owner), address=request.email)
            return mvp_pb2.SetEmailResponse(ok=requester_info.email)

    @checks_token
    @log_action
    def VerifyEmail(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.VerifyEmailRequest) -> mvp_pb2.VerifyEmailResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='must log in to change your password'))

        with self._storage.mutate() as wstate:
            requester_info = get_generic_user_info(wstate, token.owner)
            if requester_info is None:
                raise ForgottenTokenError(token)
            if not (requester_info.email and requester_info.email.WhichOneof('email_flow_state_kind') == 'code_sent'):
                logger.warn('attempting to verify email, but no email outstanding', possible_malice=True)
                return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='you have no pending email-verification flow'))
            code_sent_state = requester_info.email.code_sent
            if not check_password(request.code, code_sent_state.code):
                logger.warn('bad email-verification code', address=code_sent_state.email, possible_malice=True)
                return mvp_pb2.VerifyEmailResponse(error=mvp_pb2.VerifyEmailResponse.Error(catchall='bad code'))
            requester_info.email.CopyFrom(mvp_pb2.EmailFlowState(verified=code_sent_state.email))
            logger.info('verified email address', who=str(token.owner), address=code_sent_state.email)
            return mvp_pb2.VerifyEmailResponse(ok=requester_info.email)

    @checks_token
    @log_action
    def GetSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GetSettingsResponse:
        if token is None:
            logger.info('not logged in')
            return mvp_pb2.GetSettingsResponse(error=mvp_pb2.GetSettingsResponse.Error(catchall='must log in to see your settings'))

        wstate = self._storage.get()
        if token.owner.WhichOneof('kind') == 'username':
            info = wstate.username_users.get(token.owner.username)
            if info is None:
                raise ForgottenTokenError(token)
            return mvp_pb2.GetSettingsResponse(ok_username=info)
        else:
            logger.warn('valid-looking but mangled token', token=token, possible_malice=True, data_loss=True)
            return mvp_pb2.GetSettingsResponse(error=mvp_pb2.GetSettingsResponse.Error(catchall='your token is mangled, bro'))  # TODO

    @checks_token
    @log_action
    def UpdateSettings(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.UpdateSettingsRequest) -> mvp_pb2.UpdateSettingsResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.UpdateSettingsResponse(error=mvp_pb2.UpdateSettingsResponse.Error(catchall='must log in to update your settings'))

        with self._storage.mutate() as wstate:
            info = get_generic_user_info(wstate, token.owner)
            if info is None:
                raise ForgottenTokenError(token)
            if request.HasField('email_reminders_to_resolve'):
                info.email_reminders_to_resolve = request.email_reminders_to_resolve.value
            if request.HasField('email_resolution_notifications'):
                info.email_resolution_notifications = request.email_resolution_notifications.value
            logger.info('updated settings', request=request)
            return mvp_pb2.UpdateSettingsResponse(ok=info)

    @checks_token
    @log_action
    def CreateInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreateInvitationRequest) -> mvp_pb2.CreateInvitationResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.CreateInvitationResponse(error=mvp_pb2.CreateInvitationResponse.Error(catchall='must log in to create an invitation'))

        with self._storage.mutate() as wstate:
            info = get_generic_user_info(wstate, token.owner)
            if info is None:
                raise ForgottenTokenError(token)

            nonce = secrets.token_urlsafe(16)
            invitation = mvp_pb2.Invitation(
                created_unixtime=int(self._clock()),
                notes=request.notes,
                accepted_by=None,
            )
            info.invitations[nonce].CopyFrom(invitation)
            return mvp_pb2.CreateInvitationResponse(ok=mvp_pb2.CreateInvitationResponse.Result(
                id=mvp_pb2.InvitationId(inviter=token.owner, nonce=nonce),
                invitation=invitation,
            ))

    @checks_token
    @log_action
    def AcceptInvitation(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.AcceptInvitationResponse:
        if token is None:
            logger.warn('not logged in')
            return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='must log in to create an invitation'))

        with self._storage.mutate() as wstate:
            if (not request.HasField('invitation_id')) or (not request.invitation_id.HasField('inviter')):
                logger.warn('malformed attempt to accept invitation', possible_malice=True)
                return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='malformed invitation'))

            accepter_info = get_generic_user_info(wstate, token.owner)
            if accepter_info is None:
                raise ForgottenTokenError(token)

            inviter = request.invitation_id.inviter
            inviter_info = get_generic_user_info(wstate, inviter)
            if inviter_info is None:
                return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='no such invitation'))

            for orig_nonce, orig_invitation in inviter_info.invitations.items():
                if orig_nonce == request.invitation_id.nonce:
                    if orig_invitation.HasField('accepted_by'):
                        logger.info('attempt to re-accept invitation')
                        return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='invitation has already been used'))
                    orig_invitation.accepted_by.CopyFrom(token.owner)
                    orig_invitation.accepted_unixtime = int(self._clock())
                    if inviter not in accepter_info.trusted_users:
                        accepter_info.trusted_users.append(inviter)
                    if token.owner not in inviter_info.trusted_users:
                        inviter_info.trusted_users.append(token.owner)
                    logger.info('accepted invitation', whose=inviter)
                    return mvp_pb2.AcceptInvitationResponse(ok=mvp_pb2.VOID)
            logger.warn('attempt to accept nonexistent invitation', possible_malice=True)
            return mvp_pb2.AcceptInvitationResponse(error=mvp_pb2.AcceptInvitationResponse.Error(catchall='no such invitation'))


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

    def add_to_app(self, app: web.Application) -> None:
        if self.middleware not in app.middlewares:
            app.middlewares.append(self.middleware)

    @web.middleware
    async def middleware(self, request, handler):
        try:
            return await handler(request)
        except ForgottenTokenError as e:
            logger.exception(e)
            response = web.HTTPInternalServerError(reason="I, uh, may have accidentally obliterated your entire account. Crap. I'm sorry.")
            self.del_cookie(request, response)
            return response

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

    async def Whoami(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Whoami(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.WhoamiRequest)))
    async def SignOut(self, http_req: web.Request) -> web.Response:
        http_resp = proto_response(self._servicer.SignOut(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.SignOutRequest)))
        self._token_glue.del_cookie(http_req, http_resp)
        return http_resp
    async def RegisterUsername(self, http_req: web.Request) -> web.Response:
        pb_resp = self._servicer.RegisterUsername(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.RegisterUsernameRequest))
        http_resp = proto_response(pb_resp)
        if pb_resp.WhichOneof('register_username_result') == 'ok':
            self._token_glue.set_cookie(pb_resp.ok, http_resp)
        return http_resp
    async def LogInUsername(self, http_req: web.Request) -> web.Response:
        pb_resp = self._servicer.LogInUsername(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.LogInUsernameRequest))
        http_resp = proto_response(pb_resp)
        if pb_resp.WhichOneof('log_in_username_result') == 'ok':
            self._token_glue.set_cookie(pb_resp.ok, http_resp)
        return http_resp
    async def CreatePrediction(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.CreatePrediction(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.CreatePredictionRequest)))
    async def GetPrediction(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetPrediction(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.GetPredictionRequest)))
    async def Stake(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Stake(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.StakeRequest)))
    async def Resolve(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Resolve(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.ResolveRequest)))
    async def SetTrusted(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SetTrusted(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.SetTrustedRequest)))
    async def GetUser(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetUser(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.GetUserRequest)))
    async def ChangePassword(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.ChangePassword(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.ChangePasswordRequest)))
    async def SetEmail(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SetEmail(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.SetEmailRequest)))
    async def VerifyEmail(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.VerifyEmail(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.VerifyEmailRequest)))
    async def GetSettings(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetSettings(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.GetSettingsRequest)))
    async def UpdateSettings(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.UpdateSettings(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.UpdateSettingsRequest)))
    async def CreateInvitation(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.CreateInvitation(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.CreateInvitationRequest)))
    async def AcceptInvitation(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.AcceptInvitation(token=self._token_glue.parse_cookie(http_req), request=await parse_proto(http_req, mvp_pb2.AcceptInvitationRequest)))

    def add_to_app(self, app: web.Application) -> None:
        app.router.add_post('/api/Whoami', self.Whoami)
        app.router.add_post('/api/SignOut', self.SignOut)
        app.router.add_post('/api/RegisterUsername', self.RegisterUsername)
        app.router.add_post('/api/LogInUsername', self.LogInUsername)
        app.router.add_post('/api/CreatePrediction', self.CreatePrediction)
        app.router.add_post('/api/GetPrediction', self.GetPrediction)
        app.router.add_post('/api/Stake', self.Stake)
        app.router.add_post('/api/Resolve', self.Resolve)
        app.router.add_post('/api/SetTrusted', self.SetTrusted)
        app.router.add_post('/api/GetUser', self.GetUser)
        app.router.add_post('/api/ChangePassword', self.ChangePassword)
        app.router.add_post('/api/SetEmail', self.SetEmail)
        app.router.add_post('/api/VerifyEmail', self.VerifyEmail)
        app.router.add_post('/api/GetSettings', self.GetSettings)
        app.router.add_post('/api/UpdateSettings', self.UpdateSettings)
        app.router.add_post('/api/CreateInvitation', self.CreateInvitation)
        app.router.add_post('/api/AcceptInvitation', self.AcceptInvitation)
        self._token_glue.add_to_app(app)


_HERE = Path(__file__).parent
class WebServer:
    def __init__(self, servicer: Servicer, elm_dist: Path, token_glue: HttpTokenGlue) -> None:
        self._servicer = servicer
        self._elm_dist = elm_dist
        self._token_glue = token_glue

        self._jinja = jinja2.Environment( # adapted from https://jinja.palletsprojects.com/en/2.11.x/api/#basics
            loader=jinja2.FileSystemLoader(searchpath=[_HERE/'templates'], encoding='utf-8'),
            autoescape=jinja2.select_autoescape(['html', 'xml']),
        )
        self._jinja.undefined = jinja2.StrictUndefined  # raise exception if a template uses an undefined variable; adapted from https://stackoverflow.com/a/39127941/8877656

    async def get_static(self, req: web.Request) -> web.StreamResponse:
        filename = req.match_info['filename']
        if (not filename) or filename.startswith('.'):
            raise web.HTTPBadRequest()
        return web.FileResponse(_HERE/'static'/filename)  # type: ignore

    async def get_wellknown(self, req: web.Request) -> web.StreamResponse:
        path = Path(req.match_info['path'])
        root = Path('/home/public/.well-known')
        try:
            return web.FileResponse(root / ((root/path).absolute().relative_to(root)))
        except Exception:
            raise web.HTTPBadRequest()

    async def get_elm_module(self, req: web.Request) -> web.Response:
        module = req.match_info['module']
        return web.Response(content_type='text/javascript', body=(_HERE.parent/f'elm/dist/{module}.js').read_text()) # type: ignore

    async def get_index(self, req: web.Request) -> web.StreamResponse:
        auth = self._token_glue.parse_cookie(req)
        if auth is None:
            return await self.get_welcome(req)
        else:
            return await self.get_my_stakes(req)

    async def get_welcome(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        get_settings_response = self._servicer.GetSettings(auth, mvp_pb2.GetSettingsRequest())
        if get_settings_response.WhichOneof('get_settings_result') == 'ok_username':
            user_info: Optional[mvp_pb2.GenericUserInfo] = get_settings_response.ok_username.info
        else:
            assert get_settings_response.WhichOneof('get_settings_result') == 'error'
            user_info = None
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('Welcome.html').render(
                auth_token_pb_b64=pb_b64(auth),
                user_info_pb_b64=pb_b64(user_info),
            ))

    async def get_create_prediction_page(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('CreatePredictionPage.html').render(
                auth_token_pb_b64=pb_b64(auth),
            ))

    async def get_view_prediction_page(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        prediction_id = int(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('ViewPredictionPage.html').render(
                title=f'Biatob - Prediction: by {datetime.datetime.fromtimestamp(get_prediction_resp.prediction.resolves_at_unixtime).strftime("%Y-%m-%d")}, {get_prediction_resp.prediction.prediction}',
                auth_token_pb_b64=pb_b64(auth),
                prediction_pb_b64=pb_b64(get_prediction_resp.prediction),
                prediction_id=prediction_id,
            ))

    async def get_prediction_img_embed(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
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

        return web.Response(content_type='image/png', body=render_text(text=text, file_format='png'))

    async def get_my_stakes(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        if auth is None:
            return web.Response(
                content_type='text/html',
                body=self._jinja.get_template('LoginPage.html').render(
                    auth_token_pb_b64=None,
                ))
        list_my_stakes_resp = self._servicer.ListMyStakes(auth, mvp_pb2.ListMyStakesRequest())
        if list_my_stakes_resp.WhichOneof('list_my_stakes_result') == 'error':
            return web.Response(status=400, body=str(list_my_stakes_resp.error))
        assert list_my_stakes_resp.WhichOneof('list_my_stakes_result') == 'ok'
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('MyStakesPage.html').render(
                auth_token_pb_b64=pb_b64(auth),
                predictions_pb_b64=pb_b64(list_my_stakes_resp.ok),
            ))

    async def get_username(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        username = req.match_info['username']
        user_id = mvp_pb2.UserId(username=username)
        get_user_resp = self._servicer.GetUser(auth, mvp_pb2.GetUserRequest(who=user_id))
        if get_user_resp.WhichOneof('get_user_result') == 'error':
            return web.Response(status=400, body=str(get_user_resp.error))
        assert get_user_resp.WhichOneof('get_user_result') == 'ok'
        if get_user_resp.ok.trusts_you:
            list_predictions_resp = self._servicer.ListPredictions(auth, mvp_pb2.ListPredictionsRequest(creator=mvp_pb2.UserId(username=username)))
            predictions: Optional[mvp_pb2.PredictionsById] = list_predictions_resp.ok  # TODO: error handling
        else:
            predictions = None
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('ViewUserPage.html').render(
                auth_token_pb_b64=pb_b64(auth),
                user_view_pb_b64=pb_b64(get_user_resp.ok),
                user_id_pb_b64=pb_b64(user_id),
                predictions_pb_b64=pb_b64(predictions),
            ))

    async def get_settings(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        if auth is None:
            return web.Response(
                content_type='text/html',
                body=self._jinja.get_template('LoginPage.html').render(
                    auth_token_pb_b64=None,
                ))
        get_settings_response = self._servicer.GetSettings(auth, mvp_pb2.GetSettingsRequest())
        if get_settings_response.WhichOneof('get_settings_result') == 'error':
            return web.HTTPBadRequest(reason=str(get_settings_response.error))
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('SettingsPage.html').render(
                auth_token_pb_b64=pb_b64(auth),
                settings_response_pb_b64=pb_b64(get_settings_response),
            ))

    async def get_invitation(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        invitation_id = mvp_pb2.InvitationId(
            inviter=mvp_pb2.UserId(username=req.match_info['username']),
            nonce=req.match_info['nonce'],
        )
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('AcceptInvitationPage.html').render(
                auth_token_pb_b64=pb_b64(auth),
                invitation_id_pb_b64=pb_b64(invitation_id),
            ))

    def add_to_app(self, app: web.Application) -> None:

        self._token_glue.add_to_app(app)

        app.router.add_get('/', self.get_index)
        app.router.add_get('/.well-known/{path:.*}', self.get_wellknown)
        app.router.add_get('/static/{filename}', self.get_static)
        app.router.add_get('/elm/{module}.js', self.get_elm_module)
        app.router.add_get('/welcome', self.get_welcome)
        app.router.add_get('/new', self.get_create_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}', self.get_view_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}/embed.png', self.get_prediction_img_embed)
        app.router.add_get('/my_stakes', self.get_my_stakes)
        app.router.add_get('/username/{username:[a-zA-Z0-9_-]+}', self.get_username)
        app.router.add_get('/settings', self.get_settings)
        app.router.add_get('/invitation/{username}/{nonce}', self.get_invitation)


def pb_b64(message: Optional[Message]) -> Optional[str]:
    if message is None:
        return None
    return base64.b64encode(message.SerializeToString()).decode('ascii')


async def email_daily_backups_forever(storage: FsStorage, emailer: Emailer, recipient_email: str):
    while True:
        now = datetime.datetime.now()
        next_day = datetime.datetime.fromtimestamp(86400 * (1 + now.timestamp()//86400))
        await asyncio.sleep((next_day - now).total_seconds())
        logger.info('emailing backups')
        await emailer.send(
            to=recipient_email,
            subject=f'Biatob backup for {now:%Y-%m-%d}',
            body=google.protobuf.text_format.MessageToString(storage.get()),
            content_type='text/plain',
        )

async def email_resolution_reminders_forever(storage: FsStorage, emailer: Emailer, interval: datetime.timedelta = datetime.timedelta(hours=1)):
    interval_secs = interval.total_seconds()
    while True:
        logger.info('waking up to email resolution reminders')
        cycle_start_time = int(time.time())
        wstate = storage.get()

        todo = []

        for prediction_id, prediction in wstate.predictions.items():
            resolved_recently = wstate.email_reminders_sent_up_to_unixtime <= prediction.resolves_at_unixtime < cycle_start_time
            if resolved_recently:
                creator_info = get_generic_user_info(wstate, prediction.creator)
                if creator_info is None:
                    logging.error("prediction has nonexistent creator", prediction_id=prediction_id, creator=prediction.creator)
                    continue
                if not creator_info.HasField('email'):
                    continue
                if creator_info.email_reminders_to_resolve and creator_info.email.WhichOneof('email_flow_state_kind') == 'verified':
                    todo.append((creator_info.email.verified, prediction_id, prediction))

        for addr, prediction_id, prediction in todo:
            await emailer.send(
                to=addr,
                subject='Resolve your prediction: ' + json.dumps(prediction.prediction),
                body=f'https://biatob.com/p/{prediction_id} became resolvable recently.',
            )

        with storage.mutate() as wstate:
            wstate.email_reminders_sent_up_to_unixtime = cycle_start_time

        next_cycle_time = cycle_start_time + interval_secs
        time_to_next_cycle = next_cycle_time - time.time()
        if time_to_next_cycle < interval_secs / 2:
            logger.warn('sending resolution-reminders took dangerously long', interval_secs=interval_secs, time_remaining=time.time() - cycle_start_time)
        await asyncio.sleep(time_to_next_cycle)


parser = argparse.ArgumentParser()
parser.add_argument("-H", "--host", default="localhost")
parser.add_argument("-p", "--port", type=int, default=8080)
parser.add_argument("--elm-dist", type=Path, default="elm/dist")
parser.add_argument("--state-path", type=Path, required=True)
parser.add_argument("--credentials-path", type=Path, required=True)
parser.add_argument("--email-daily-backups-to", help='send daily backups to this email address')
parser.add_argument("-v", "--verbose", action="count", default=0)

async def main(args):
    logging.basicConfig(level=logging.INFO if args.verbose==0 else logging.DEBUG)
    if args.verbose < 2:
        logging.getLogger('filelock').setLevel(logging.WARN)
        logging.getLogger('aiohttp.access').setLevel(logging.WARN)
    app = web.Application()

    credentials = google.protobuf.text_format.Parse(args.credentials_path.read_text(), mvp_pb2.CredentialsConfig())

    storage = FsStorage(state_path=args.state_path)
    # from unittest.mock import Mock
    emailer = Emailer(
        hostname=credentials.smtp.hostname,
        port=credentials.smtp.port,
        username=credentials.smtp.username,
        password=credentials.smtp.password,
        from_addr=credentials.smtp.from_addr,
        # aiosmtplib_for_testing=Mock(send=lambda *args, **kwargs: (print(args, kwargs), asyncio.sleep(0))[1])
    )
    token_mint = TokenMint(secret_key=credentials.token_signing_secret)
    token_glue = HttpTokenGlue(token_mint=token_mint)
    servicer = FsBackedServicer(storage=storage, token_mint=token_mint, emailer=emailer)

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

    asyncio.get_running_loop().create_task(email_resolution_reminders_forever(storage=storage, emailer=emailer))
    if args.email_daily_backups_to is not None:
        asyncio.get_running_loop().create_task(email_daily_backups_forever(storage=storage, emailer=emailer, recipient_email=args.email_daily_backups_to))

    # adapted from https://docs.aiohttp.org/en/stable/web_advanced.html#application-runners
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host=args.host, port=args.port)
    await site.start()
    print(f'Running forever on http://{args.host}:{args.port}...', file=sys.stderr)
    try:
        while True:
            await asyncio.sleep(3600)
    except KeyboardInterrupt:
        print('Shutting down server...', file=sys.stderr)
        await runner.cleanup()
        print('...server shut down.', file=sys.stderr)

if __name__ == '__main__':
    asyncio.run(main(parser.parse_args()))
