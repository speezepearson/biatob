from __future__ import annotations

import asyncio
import base64
import contextlib
import datetime
import pytest
import unittest.mock
from typing import Any, Callable, Mapping, Optional, Sequence, Tuple, Type, TypeVar, Iterator, overload

import sqlalchemy

from .core import ApiError, AuthorizingUsername, PredictionId, Servicer, TokenMint, Username
from .emailer import Emailer
from . import api_types as T
from .sql_servicer import SqlServicer, SqlConn
from . import sql_schema

class MockClock:
  def __init__(self):
    self._unixtime = 1000000000
  def now(self) -> datetime.datetime:
    return datetime.datetime.fromtimestamp(self._unixtime)
  def tick(self, seconds: float = 1) -> None:
    self._unixtime += seconds

@pytest.fixture
def clock():
  return MockClock()

@pytest.fixture
def token_mint(clock):
  return TokenMint(secret_key=b'test secret', clock=clock.now)

@pytest.fixture
def emailer():
  return unittest.mock.Mock(
    send_resolution_notifications=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_resolution_reminder=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_email_verification=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_invitation=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_backup=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_invitation_acceptance_notification=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
  )

@pytest.fixture
def sqlite_engine() -> sqlalchemy.engine.Engine:
  engine = sqlalchemy.create_engine(f'sqlite+pysqlite:///:memory:')
  sqlalchemy.event.listen(engine, "connect", sql_schema.set_sqlite_pragma)
  sql_schema.metadata.create_all(engine)
  return engine

@pytest.fixture
def any_servicer(clock, token_mint, emailer, sqlite_engine):
  with sqlite_engine.connect() as conn:
    yield SqlServicer(
      conn=SqlConn(conn),
      emailer=emailer,
      random_seed=0,
      clock=clock.now,
      token_mint=token_mint,
    )



_T = TypeVar('_T')
@contextlib.contextmanager
def assert_user_unchanged(servicer: Servicer, who: Username, password: str) -> Iterator[None]:
  servicer.LogInUsername(None, T.LogInUsernameRequest(username=who, password=password))
  old_settings = servicer.GetSettings(AuthorizingUsername(who), T.GetSettingsRequest(include_relationships_with_users=[]))
  yield
  new_settings = servicer.GetSettings(AuthorizingUsername(who), T.GetSettingsRequest(include_relationships_with_users=[]))
  assert old_settings == new_settings
  servicer.LogInUsername(None, T.LogInUsernameRequest(username=who, password=password))


@contextlib.contextmanager
def assert_prediction_unchanged(servicer: Servicer, prediction_id: PredictionId) -> Iterator[None]:
  creator = Username(servicer.GetPrediction(None, T.GetPredictionRequest(prediction_id=prediction_id)).creator)
  old = servicer.GetPrediction(AuthorizingUsername(creator), T.GetPredictionRequest(prediction_id=prediction_id))
  yield
  new = servicer.GetPrediction(AuthorizingUsername(creator), T.GetPredictionRequest(prediction_id=prediction_id))
  assert old == new


def register_friend_pair(servicer: Servicer, u1: AuthorizingUsername, u2: AuthorizingUsername):
  create_user(servicer, u1)
  create_user(servicer, u2)
  servicer.SetTrusted(u1, T.SetTrustedRequest(who=u2, trusted=True))
  servicer.SetTrusted(u2, T.SetTrustedRequest(who=u1, trusted=True))

def some_create_prediction_request(**kwargs) -> T.CreatePredictionRequest:
  init_kwargs = dict(
    prediction='prediction!',
    certainty=T.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
    open_seconds=123,
    resolves_at_unixtime=int(2e9),
    view_privacy=T.PredictionViewPrivacy.ANYBODY,
    special_rules='rules!',
  )
  init_kwargs.update(kwargs)
  return T.CreatePredictionRequest(**init_kwargs)  # type: ignore

def get_call_kwarg(mock_method: Callable[..., Any], kwarg: str) -> Any:
  return mock_method.call_args[1][kwarg]  # type: ignore


@overload
def au(u: None) -> None:
  pass
@overload
def au(u: str) -> AuthorizingUsername:
  pass
def au(u: Optional[str]) -> Optional[AuthorizingUsername]:
  return None if (u is None) else AuthorizingUsername(Username(u))

pid = PredictionId
u = Username


def create_user(servicer: Servicer, username: Username, password: str = 'pw', email_address: Optional[str] = None) -> None:
  if email_address is None:
    email_address = f'{username}@example.com'
  SendVerificationEmailOk(servicer, None, email_address)
  proof_token = servicer._emailer.send_email_verification.call_args[1]['proof_token']  # type: ignore
  RegisterUsernameOk(servicer, actor=None, username=username, proof_token=proof_token, password=password)

def Whoami(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> Optional[Username]:
  return Username(servicer.Whoami(actor, T.WhoamiRequest()).username)

def SignOut(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> None:
  servicer.SignOut(actor, T.SignOutRequest())

def SendVerificationEmailOk(servicer: Servicer, actor: Optional[AuthorizingUsername], email_address: str) -> None:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  servicer.SendVerificationEmail(actor, T.SendVerificationEmailRequest(email_address=email_address))
def SendVerificationEmailErr(servicer: Servicer, actor: Optional[AuthorizingUsername], email_address: str) -> ApiError:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  with pytest.raises(ApiError) as excinfo:
    servicer.SendVerificationEmail(actor, T.SendVerificationEmailRequest(email_address=email_address))
  return excinfo.value

def RegisterUsernameOk(servicer: Servicer, actor: Optional[AuthorizingUsername], proof_token: str, username: Username, password: str = 'pw') -> T.AuthSuccess:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  return servicer.RegisterUsername(actor, T.RegisterUsernameRequest(username=username, password=password, proof_of_email_token=proof_token))
def RegisterUsernameErr(servicer: Servicer, actor: Optional[AuthorizingUsername], proof_token: str, username: Username, password: str = 'pw') -> ApiError:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  with pytest.raises(ApiError) as excinfo:
    servicer.RegisterUsername(actor, T.RegisterUsernameRequest(username=username, password=password, proof_of_email_token=proof_token))
  return excinfo.value

def LogInUsernameOk(servicer: Servicer, actor: Optional[AuthorizingUsername], username: Username, password: str) -> T.AuthSuccess:
  return servicer.LogInUsername(actor, T.LogInUsernameRequest(username=username, password=password))
def LogInUsernameErr(servicer: Servicer, actor: Optional[AuthorizingUsername], username: Username, password: str) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.LogInUsername(actor, T.LogInUsernameRequest(username=username, password=password))
  return excinfo.value

def CreatePredictionOk(servicer: Servicer, actor: Optional[AuthorizingUsername], request_kwargs: Mapping[str, Any]) -> PredictionId:
  return PredictionId(servicer.CreatePrediction(actor, some_create_prediction_request(**request_kwargs)).new_prediction_id)
def CreatePredictionErr(servicer: Servicer, actor: Optional[AuthorizingUsername], request_kwargs: Mapping[str, Any]) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.CreatePrediction(actor, some_create_prediction_request(**request_kwargs))
  return excinfo.value

def GetPredictionOk(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId) -> T.UserPredictionView:
  return servicer.GetPrediction(actor, T.GetPredictionRequest(prediction_id=prediction_id))
def GetPredictionErr(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.GetPrediction(actor, T.GetPredictionRequest(prediction_id=prediction_id))
  return excinfo.value

def ListMyStakesOk(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> T.PredictionsById:
  return servicer.ListMyStakes(actor, T.ListMyStakesRequest())
def ListMyStakesErr(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.ListMyStakes(actor, T.ListMyStakesRequest())
  return excinfo.value

def ListPredictionsOk(servicer: Servicer, actor: Optional[AuthorizingUsername], creator: Username) -> T.PredictionsById:
  return servicer.ListPredictions(actor, T.ListPredictionsRequest(creator=creator))
def ListPredictionsErr(servicer: Servicer, actor: Optional[AuthorizingUsername], creator: Username) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.ListPredictions(actor, T.ListPredictionsRequest(creator=creator))
  return excinfo.value

def StakeOk(servicer: Servicer, actor: Optional[AuthorizingUsername], request: T.StakeRequest) -> T.UserPredictionView:
  return servicer.Stake(actor, request)
def StakeErr(servicer: Servicer, actor: Optional[AuthorizingUsername], request: T.StakeRequest) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.Stake(actor, request)
  return excinfo.value

def FollowOk(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, follow: bool) -> T.UserPredictionView:
  return servicer.Follow(actor, T.FollowRequest(prediction_id=prediction_id, follow=follow))
def FollowErr(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, follow: bool) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.Follow(actor, T.FollowRequest(prediction_id=prediction_id, follow=follow))
  return excinfo.value

def ResolveOk(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, resolution: T.Resolution, notes: str = '') -> T.UserPredictionView:
  return servicer.Resolve(actor, T.ResolveRequest(prediction_id=prediction_id, resolution=resolution, notes=notes))
def ResolveErr(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, resolution: T.Resolution, notes: str = '') -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.Resolve(actor, T.ResolveRequest(prediction_id=prediction_id, resolution=resolution, notes=notes))
  return excinfo.value

def SetTrustedOk(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username, trusted: bool) -> T.GenericUserInfo:
  return servicer.SetTrusted(actor, T.SetTrustedRequest(who=who, trusted=trusted))
def SetTrustedErr(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username, trusted: bool) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.SetTrusted(actor, T.SetTrustedRequest(who=who, trusted=trusted))
  return excinfo.value

def GetUserOk(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username) -> T.Relationship:
  return servicer.GetUser(actor, T.GetUserRequest(who=who))
def GetUserErr(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.GetUser(actor, T.GetUserRequest(who=who))
  return excinfo.value

def ChangePasswordOk(servicer: Servicer, actor: Optional[AuthorizingUsername], old_password: str, new_password: str) -> object:
  return servicer.ChangePassword(actor, T.ChangePasswordRequest(old_password=old_password, new_password=new_password))
def ChangePasswordErr(servicer: Servicer, actor: Optional[AuthorizingUsername], old_password: str, new_password: str) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.ChangePassword(actor, T.ChangePasswordRequest(old_password=old_password, new_password=new_password))
  return excinfo.value

def GetSettingsOk(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> T.GenericUserInfo:
  return servicer.GetSettings(actor, T.GetSettingsRequest(include_relationships_with_users=[]))
def GetSettingsErr(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.GetSettings(actor, T.GetSettingsRequest(include_relationships_with_users=[]))
  return excinfo.value

def SendInvitationOk(servicer: Servicer, actor: Optional[AuthorizingUsername], recipient: str) -> T.GenericUserInfo:
  return servicer.SendInvitation(actor, T.SendInvitationRequest(recipient=recipient))
def SendInvitationErr(servicer: Servicer, actor: Optional[AuthorizingUsername], recipient: str) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.SendInvitation(actor, T.SendInvitationRequest(recipient=recipient))
  return excinfo.value

def CheckInvitationOk(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> T.CheckInvitationResponse:
  return servicer.CheckInvitation(actor, T.CheckInvitationRequest(nonce=nonce))
def CheckInvitationErr(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.CheckInvitation(actor, T.CheckInvitationRequest(nonce=nonce))
  return excinfo.value

def AcceptInvitationOk(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> T.GenericUserInfo:
  return servicer.AcceptInvitation(actor, T.AcceptInvitationRequest(nonce=nonce))
def AcceptInvitationErr(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> ApiError:
  with pytest.raises(ApiError) as excinfo:
    servicer.AcceptInvitation(actor, T.AcceptInvitationRequest(nonce=nonce))
  return excinfo.value
