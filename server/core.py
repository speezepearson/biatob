import abc
import datetime
import hashlib
import random
import re
import secrets
from typing import overload, Optional, Container, NewType, Callable

from aiohttp import web

from . import tokens
from .protobuf import mvp_pb2

PredictionId = NewType('PredictionId', str)
Username = NewType('Username', str)
AuthorizingUsername = NewType('AuthorizingUsername', Username)

MAX_LEGAL_STAKE_CENTS = 5_000_00


class UsernameAlreadyRegisteredError(Exception): pass
class ForgottenTokenError(RuntimeError): pass


# --- servicer failure modes --------------------------------------------------
#
# The exceptions a servicer raises to signal an expected, client-facing failure.
# They name the *failure mode*, not the HTTP status: the status is a
# presentation detail that happens to hang off the class.
#
# Deliberately no HTTP library import here. Servicers must stay
# transport-agnostic, because web_server.py calls them directly to render pages
# -- they are not only reached over HTTP. Each transport translates: api_server
# into a status code plus an ErrorResponse body, web_server into an error page.

class ApiError(Exception):
    """Base class for expected, client-facing failures.

    `catchall` is shown to the user verbatim, so it must never leak internals.
    Anything that is *not* an ApiError is a bug, and becomes an opaque 500.
    """
    http_status = 400

    def __init__(self, catchall: str) -> None:
        super().__init__(catchall)
        self.catchall = catchall


class InvalidRequestError(ApiError):
    """The request is malformed or self-contradictory: bad password format,
    unrecognized resolution, betting zero cents, trusting yourself."""
    http_status = 400


# --- who you are -------------------------------------------------------------

class NotLoggedInError(ApiError):
    """This endpoint needs an actor and didn't get one."""
    http_status = 401

class BadCredentialsError(ApiError):
    """Credentials didn't check out: wrong password, or (on login) no such user.

    NOTE: on login this is currently raised with a message that distinguishes
    'no such user' from 'bad password', which lets an attacker enumerate
    usernames. Pre-existing behaviour, preserved deliberately; worth closing
    separately.
    """
    http_status = 401

class AlreadyLoggedInError(ApiError):
    """Actor is authenticated but the endpoint requires anonymity (log in,
    register, verify email). A client mistake, not an auth failure -- hence
    400 rather than 401."""
    http_status = 400

class ForbiddenError(ApiError):
    """Actor is authenticated, and simply isn't allowed: resolving someone
    else's prediction, betting against a creator you don't trust."""
    http_status = 403


# --- what you asked for --------------------------------------------------

class NotFoundError(ApiError):
    http_status = 404

class NoSuchPredictionError(NotFoundError):
    """No such prediction -- or the actor may not know it exists.

    Deliberately conflates 'absent' and 'forbidden': telling a stranger that a
    private prediction exists is itself a leak, so both are a 404.
    """

class NoSuchUserError(NotFoundError): pass
class NoSuchInvitationError(NotFoundError): pass


# --- the world is not in the right state -------------------------------------

class ConflictError(ApiError):
    """The request is well-formed and permitted, but conflicts with current
    state. Retrying unchanged won't help until something else changes."""
    http_status = 409

class AlreadyRegisteredError(ConflictError):
    """Username taken, or email already registered."""

class PredictionClosedError(ConflictError):
    """Betting window has closed, or the prediction already resolved."""

class StakeCapExceededError(ConflictError):
    """The bet would exceed the creator's tolerance, or the per-prediction cap."""

class InvitationAlreadySentError(ConflictError): pass


# --- our fault ---------------------------------------------------------------

class InternalError(ApiError):
    """A 'this should never happen' that we nonetheless handle. Distinct from an
    unhandled exception only in that we have a message worth showing."""
    http_status = 500


@overload
def token_owner(token: None) -> None: pass
@overload
def token_owner(token: tokens.AuthToken) -> AuthorizingUsername: pass
def token_owner(token: Optional[tokens.AuthToken]) -> Optional[AuthorizingUsername]:
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
    def SendVerificationEmail(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SendVerificationEmailRequest) -> mvp_pb2.Empty:
        """Raises AlreadyLoggedInError, AlreadyRegisteredError."""
    def RegisterUsername(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.AuthSuccess:
        """Raises AlreadyLoggedInError, InvalidRequestError, AlreadyRegisteredError."""
    def LogInUsername(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.AuthSuccess:
        """Raises BadCredentialsError, AlreadyLoggedInError."""
    def CreatePrediction(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.CreatePredictionRequest) -> mvp_pb2.CreatePredictionResponse:
        """Raises NotLoggedInError, InvalidRequestError."""
    def GetPrediction(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetPredictionRequest) -> mvp_pb2.UserPredictionView:
        """Raises NoSuchPredictionError if absent or not visible to the actor."""
    def ListMyStakes(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ListMyStakesRequest) -> mvp_pb2.PredictionsById:
        """Raises NotLoggedInError."""
    def ListPredictions(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ListPredictionsRequest) -> mvp_pb2.PredictionsById:
        """Raises NotLoggedInError."""
    def Stake(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.StakeRequest) -> mvp_pb2.UserPredictionView:
        """Raises NotLoggedInError, NoSuchPredictionError, ForbiddenError, PredictionClosedError, StakeCapExceededError, InvalidRequestError."""
    def Follow(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.FollowRequest) -> mvp_pb2.UserPredictionView:
        """Raises NotLoggedInError, NoSuchPredictionError."""
    def Resolve(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ResolveRequest) -> mvp_pb2.UserPredictionView:
        """Raises NotLoggedInError, NoSuchPredictionError, ForbiddenError, InvalidRequestError."""
    def SetTrusted(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SetTrustedRequest) -> mvp_pb2.GenericUserInfo:
        """Raises NotLoggedInError, NoSuchUserError, InvalidRequestError."""
    def GetUser(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetUserRequest) -> mvp_pb2.Relationship:
        """Raises NoSuchUserError."""
    def ChangePassword(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.ChangePasswordRequest) -> mvp_pb2.Empty:
        """Raises NotLoggedInError, BadCredentialsError, InvalidRequestError."""
    def GetSettings(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.GetSettingsRequest) -> mvp_pb2.GenericUserInfo:
        """Raises NotLoggedInError."""
    def SendInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.SendInvitationRequest) -> mvp_pb2.GenericUserInfo:
        """Raises NotLoggedInError, NoSuchUserError, InvitationAlreadySentError."""
    def CheckInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.CheckInvitationRequest) -> mvp_pb2.CheckInvitationResponse:
        """Raises NoSuchInvitationError."""
    def AcceptInvitation(self, actor: Optional[AuthorizingUsername], request: mvp_pb2.AcceptInvitationRequest) -> mvp_pb2.GenericUserInfo:
        """Raises NoSuchInvitationError."""


AUTH_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 365


class TokenMint:

    def __init__(self, secret_key: bytes, clock: Callable[[], datetime.datetime] = datetime.datetime.now) -> None:
        self._secret_key = secret_key
        self._clock = clock

    # --- auth tokens: sealed Pydantic JSON ---

    def mint_token(self, owner: Username, ttl_seconds: int = AUTH_TOKEN_TTL_SECONDS) -> tokens.AuthToken:
        now = int(self._clock().timestamp())
        return tokens.AuthToken(
            owner=owner,
            minted_unixtime=now,
            expires_unixtime=now + ttl_seconds,
        )

    def seal_token(self, token: tokens.AuthToken) -> str:
        return tokens.seal(self._secret_key, token)

    def unseal_token(self, sealed: str) -> Optional[tokens.AuthToken]:
        return tokens.unseal(self._secret_key, sealed, tokens.AuthToken)

    def check_token(self, token: Optional[tokens.AuthToken]) -> Optional[AuthorizingUsername]:
        # The signature is checked by unseal_token; this checks the time window.
        if token is None:
            return None
        now = int(self._clock().timestamp())
        if not (token.minted_unixtime <= now < token.expires_unixtime):
            return None
        return AuthorizingUsername(Username(token.owner))

    def revoke_token(self, token: tokens.AuthToken) -> None:
        pass  # TODO

    # --- email-verification proofs: sealed Pydantic JSON ---

    def sign_proof_of_email(self, email_address: str) -> str:
        proof = tokens.ProofOfEmail(email_address=email_address, salt=secrets.token_hex(8))
        return tokens.seal(self._secret_key, proof)

    def check_proof_of_email(self, sealed: str) -> Optional[str]:
        proof = tokens.unseal(self._secret_key, sealed, tokens.ProofOfEmail)
        return proof.email_address if proof is not None else None
