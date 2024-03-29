import abc
import copy
import datetime
import hashlib
import hmac
import random
import re
import secrets
from typing import overload, Optional, Container, NewType, Callable

from aiohttp import web
from google.protobuf.message import Message

from .protobuf import mvp_pb2

PredictionId = NewType('PredictionId', str)
Username = NewType('Username', str)
AuthorizingUsername = NewType('AuthorizingUsername', Username)

MAX_LEGAL_STAKE_CENTS = 5_000_00


class UsernameAlreadyRegisteredError(Exception): pass
class NoSuchUserError(Exception): pass
class BadPasswordError(Exception): pass
class ForgottenTokenError(RuntimeError): pass


@overload
def token_owner(token: None) -> None: pass
@overload
def token_owner(token: mvp_pb2.AuthToken) -> AuthorizingUsername: pass
def token_owner(token: Optional[mvp_pb2.AuthToken]) -> Optional[AuthorizingUsername]:
    return None if (token is None) else AuthorizingUsername(Username(token.owner))


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

_MISC_RESERVED_TOPLEVEL_PATH_SEGMENTS = {
    'legal',
    'privacy',
    'abuse',
    'admin',
    'admins',
    'user',
    'feedback',
    'help',
    'info',
    'status',
    'static',
    'nonce',
    'send',
    'mail',
    'license',
    'index',
    'js',
    'css',
    'json',
    'invite',
    'paypal',
    'pay',
    'btc',
    'bitcoin',
    'mastercard',
    'visa',
    'god',
    'server',
    'facebook',
    'fb',
    'google',
    'goog',
    'oauth',
    'lesswrong',
    'ios',
    'mac',
    'android',
}
def describe_username_problems(username: str) -> Optional[str]:
    from . import web_server, api_server
    problems = []
    if not username:
        problems.append('username must be non-empty')
    if len(username) > 64:
        problems.append('username must be no more than 64 characters')
    if len(username) < 3:
        problems.append('username must be at least 3 characters')
    if not username.isalnum():
        problems.append('username must be alphanumeric')
    if username in (_MISC_RESERVED_TOPLEVEL_PATH_SEGMENTS | web_server.RESERVED_TOPLEVEL_PATH_SEGMENTS | api_server.RESERVED_TOPLEVEL_PATH_SEGMENTS):
        problems.append('username is a reserved word')
    return '; '.join(problems) if problems else None

def describe_password_problems(password: str) -> Optional[str]:
    problems = []
    if not password:
        problems.append('password must be non-empty')
    if len(password) > 256:
        problems.append('password must not exceed 256 characters, good lord')
    return '; '.join(problems) if problems else None

def describe_CreatePredictionRequest_problems(request: mvp_pb2.CreatePredictionRequest, now: float) -> Optional[str]:
    problems = []
    if not request.prediction:
        problems.append('must have a prediction field')
    if not request.certainty:
        problems.append('must have a certainty')
    if not (0 < request.certainty.low <= request.certainty.high <= 1):
        problems.append('must have 0 < lowProb <= highProb <= 1')
    if not (request.maximum_stake_cents <= MAX_LEGAL_STAKE_CENTS):
        problems.append(f'stake must not exceed ${MAX_LEGAL_STAKE_CENTS//100}')
    if not (request.open_seconds > 0):
        problems.append(f'prediction must be open for a positive number of seconds')
    if not (request.resolves_at_unixtime > now + request.open_seconds):
        problems.append(f'prediction must resolve after betting closes')
    return '; '.join(problems) if problems else None

def describe_AcceptInvitationRequest_problems(request: mvp_pb2.AcceptInvitationRequest) -> Optional[str]:
    problems = []
    if not request.nonce:
        problems.append('no nonce given')
    return '; '.join(problems) if problems else None


class Servicer(abc.ABC):
    def Whoami(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse: pass
    def SignOut(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse: pass
    def SendVerificationEmail(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SendVerificationEmailRequest) -> mvp_pb2.SendVerificationEmailResponse: pass
    def RegisterUsername(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse: pass
    def LogInUsername(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse: pass
    def CreatePrediction(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse: pass
    def GetPrediction(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.GetPredictionResponse: pass
    def ListMyStakes(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ListMyStakesRequest) -> mvp_pb2.ListMyStakesResponse: pass
    def ListPredictions(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.ListPredictionsResponse: pass
    def Stake(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse: pass
    def Follow(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.FollowRequest) -> mvp_pb2.FollowResponse: pass
    def Resolve(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ResolveRequest) -> mvp_pb2.ResolveResponse: pass
    def SetTrusted(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.SetTrustedResponse: pass
    def GetUser(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetUserRequest) -> mvp_pb2.GetUserResponse: pass
    def ChangePassword(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.ChangePasswordResponse: pass
    def GetSettings(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GetSettingsResponse: pass
    def SendInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SendInvitationRequest) -> mvp_pb2.SendInvitationResponse: pass
    def CheckInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.CheckInvitationRequest) -> mvp_pb2.CheckInvitationResponse: pass
    def AcceptInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.AcceptInvitationResponse: pass


class TokenMint:

    def __init__(self, secret_key: bytes, clock: Callable[[], datetime.datetime] = datetime.datetime.now) -> None:
        self._secret_key = secret_key
        self._clock = clock

    def _signature(self, message: Message) -> bytes:
        return hmac.digest(key=self._secret_key, msg=message.SerializeToString(), digest='sha256')

    def _compute_token_hmac(self, token: mvp_pb2.AuthToken) -> bytes:
        scratchpad = copy.copy(token)
        scratchpad.hmac_of_rest = b''
        return self._signature(scratchpad)

    def _sign_token(self, token: mvp_pb2.AuthToken) -> None:
        token.hmac_of_rest = self._compute_token_hmac(token=token)

    def mint_token(self, owner: Username, ttl_seconds: int) -> mvp_pb2.AuthToken:
        now = int(self._clock().timestamp())
        token = mvp_pb2.AuthToken(
            owner=owner,
            minted_unixtime=now,
            expires_unixtime=now + ttl_seconds,
        )
        self._sign_token(token=token)
        return token

    def check_token(self, token: Optional[mvp_pb2.AuthToken]) -> Optional[AuthorizingUsername]:
        if token is None:
            return None
        now = int(self._clock().timestamp())
        if not (token.minted_unixtime <= now < token.expires_unixtime):
            return None

        alleged_hmac = token.hmac_of_rest
        true_hmac = self._compute_token_hmac(token)
        if not hmac.compare_digest(alleged_hmac, true_hmac):
            return None

        return AuthorizingUsername(Username(token.owner))

    def revoke_token(self, token: mvp_pb2.AuthToken) -> None:
        pass  # TODO

    def sign_proof_of_email(self, email_address: str) -> mvp_pb2.ProofOfEmail:
        payload = mvp_pb2.ProofOfEmail.Payload(email_address=email_address)
        salt = secrets.token_bytes(8)
        return mvp_pb2.ProofOfEmail(
            payload=payload,
            salt=salt,
            hmac=hmac.digest(key=self._secret_key, msg=payload.SerializeToString(), digest='sha256'),
        )

    def check_proof_of_email(self, proof: mvp_pb2.ProofOfEmail) -> Optional[str]:
        if hmac.compare_digest(proof.hmac, self._signature(proof.payload)):
            return proof.payload.email_address
        return None
