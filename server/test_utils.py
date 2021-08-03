from __future__ import annotations

import asyncio
import base64
import contextlib
import datetime
import pytest
import unittest.mock
from typing import Any, Callable, Mapping, Optional, Sequence, Tuple, Type, TypeVar, Iterator, overload

from google.protobuf.message import Message
import sqlalchemy

from .core import AuthorizingUsername, PredictionId, Servicer, TokenMint, Username
from .emailer import Emailer
from .protobuf import mvp_pb2
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
def assert_oneof(pb: Message, oneof: str, case: str, typ: Type[_T]) -> _T:
  assert pb.WhichOneof(oneof) == case, pb
  result = getattr(pb, case)
  assert isinstance(result, typ), result
  return result


@contextlib.contextmanager
def assert_user_unchanged(servicer: Servicer, who: Username, password: str) -> Iterator[None]:
  assert_oneof(servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username=who, password=password)), 'log_in_username_result', 'ok', mvp_pb2.AuthSuccess)
  old_settings = assert_oneof(servicer.GetSettings(AuthorizingUsername(who), mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
  yield
  new_settings = assert_oneof(servicer.GetSettings(AuthorizingUsername(who), mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
  assert old_settings == new_settings
  assert_oneof(servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username=who, password=password)), 'log_in_username_result', 'ok', mvp_pb2.AuthSuccess)


@contextlib.contextmanager
def assert_prediction_unchanged(servicer: Servicer, prediction_id: PredictionId) -> Iterator[None]:
  creator = Username(assert_oneof(servicer.GetPrediction(None, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).creator)
  old = assert_oneof(servicer.GetPrediction(AuthorizingUsername(creator), mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
  yield
  new = assert_oneof(servicer.GetPrediction(AuthorizingUsername(creator), mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
  assert old == new


def register_friend_pair(servicer: Servicer, u1: AuthorizingUsername, u2: AuthorizingUsername):
  create_user(servicer, u1)
  create_user(servicer, u2)
  servicer.SetTrusted(u1, mvp_pb2.SetTrustedRequest(who=u2, trusted=True))
  servicer.SetTrusted(u2, mvp_pb2.SetTrustedRequest(who=u1, trusted=True))

def some_create_prediction_request(**kwargs) -> mvp_pb2.CreatePredictionRequest:
  init_kwargs = dict(
    prediction='prediction!',
    certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
    open_seconds=123,
    resolves_at_unixtime=int(2e9),
    view_privacy=mvp_pb2.PREDICTION_VIEW_PRIVACY_ANYBODY,
    special_rules='rules!',
  )
  init_kwargs.update(kwargs)
  return mvp_pb2.CreatePredictionRequest(**init_kwargs)  # type: ignore

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
  proof_of_email = servicer._emailer.send_email_verification.call_args[1]['proof_of_email']  # type: ignore
  RegisterUsernameOk(servicer, actor=None, username=username, proof_of_email=proof_of_email, password=password)

def Whoami(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> Optional[Username]:
  return Username(servicer.Whoami(actor, mvp_pb2.WhoamiRequest()).username)

def SignOut(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> None:
  servicer.SignOut(actor, mvp_pb2.SignOutRequest())

def SendVerificationEmailOk(servicer: Servicer, actor: Optional[AuthorizingUsername], email_address: str) -> None:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  assert_oneof(servicer.SendVerificationEmail(actor, mvp_pb2.SendVerificationEmailRequest(email_address=email_address)), 'send_verification_email_result', 'ok', object)
def SendVerificationEmailErr(servicer: Servicer, actor: Optional[AuthorizingUsername], email_address: str) -> mvp_pb2.SendVerificationEmailResponse.Error:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  return assert_oneof(servicer.SendVerificationEmail(actor, mvp_pb2.SendVerificationEmailRequest(email_address=email_address)), 'send_verification_email_result', 'error', mvp_pb2.SendVerificationEmailResponse.Error)

def RegisterUsernameOk(servicer: Servicer, actor: Optional[AuthorizingUsername], proof_of_email: mvp_pb2.ProofOfEmail, username: Username, password: str = 'pw') -> mvp_pb2.AuthSuccess:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  return assert_oneof(servicer.RegisterUsername(actor, mvp_pb2.RegisterUsernameRequest(username=username, password=password, proof_of_email=proof_of_email)), 'register_username_result', 'ok', mvp_pb2.AuthSuccess)
def RegisterUsernameErr(servicer: Servicer, actor: Optional[AuthorizingUsername], proof_of_email: mvp_pb2.ProofOfEmail, username: Username, password: str = 'pw') -> mvp_pb2.RegisterUsernameResponse.Error:
  token_mint: TokenMint = servicer._token_mint  # type: ignore
  return assert_oneof(servicer.RegisterUsername(actor, mvp_pb2.RegisterUsernameRequest(username=username, password=password, proof_of_email=proof_of_email)), 'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error)

def LogInUsernameOk(servicer: Servicer, actor: Optional[AuthorizingUsername], username: Username, password: str) -> mvp_pb2.AuthSuccess:
  return assert_oneof(servicer.LogInUsername(actor, mvp_pb2.LogInUsernameRequest(username=username, password=password)), 'log_in_username_result', 'ok', mvp_pb2.AuthSuccess)
def LogInUsernameErr(servicer: Servicer, actor: Optional[AuthorizingUsername], username: Username, password: str) -> mvp_pb2.LogInUsernameResponse.Error:
  return assert_oneof(servicer.LogInUsername(actor, mvp_pb2.LogInUsernameRequest(username=username, password=password)), 'log_in_username_result', 'error', mvp_pb2.LogInUsernameResponse.Error)

def CreatePredictionOk(servicer: Servicer, actor: Optional[AuthorizingUsername], request_kwargs: Mapping[str, Any]) -> PredictionId:
  return PredictionId(assert_oneof(servicer.CreatePrediction(actor, some_create_prediction_request(**request_kwargs)), 'create_prediction_result', 'new_prediction_id', str))
def CreatePredictionErr(servicer: Servicer, actor: Optional[AuthorizingUsername], request_kwargs: Mapping[str, Any]) -> mvp_pb2.CreatePredictionResponse.Error:
  return assert_oneof(servicer.CreatePrediction(actor, some_create_prediction_request(**request_kwargs)), 'create_prediction_result', 'error', mvp_pb2.CreatePredictionResponse.Error)

def GetPredictionOk(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId) -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.GetPrediction(actor, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
def GetPredictionErr(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId) -> mvp_pb2.GetPredictionResponse.Error:
  return assert_oneof(servicer.GetPrediction(actor, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'error', mvp_pb2.GetPredictionResponse.Error)

def ListMyStakesOk(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> mvp_pb2.PredictionsById:
  return assert_oneof(servicer.ListMyStakes(actor, mvp_pb2.ListMyStakesRequest()), 'list_my_stakes_result', 'ok', mvp_pb2.PredictionsById)
def ListMyStakesErr(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> mvp_pb2.ListMyStakesResponse.Error:
  return assert_oneof(servicer.ListMyStakes(actor, mvp_pb2.ListMyStakesRequest()), 'list_my_stakes_result', 'error', mvp_pb2.ListMyStakesResponse.Error)

def ListPredictionsOk(servicer: Servicer, actor: Optional[AuthorizingUsername], creator: Username) -> mvp_pb2.PredictionsById:
  return assert_oneof(servicer.ListPredictions(actor, mvp_pb2.ListPredictionsRequest(creator=creator)), 'list_predictions_result', 'ok', mvp_pb2.PredictionsById)
def ListPredictionsErr(servicer: Servicer, actor: Optional[AuthorizingUsername], creator: Username) -> mvp_pb2.ListPredictionsResponse.Error:
  return assert_oneof(servicer.ListPredictions(actor, mvp_pb2.ListPredictionsRequest(creator=creator)), 'list_predictions_result', 'error', mvp_pb2.ListPredictionsResponse.Error)

def StakeOk(servicer: Servicer, actor: Optional[AuthorizingUsername], request: mvp_pb2.StakeRequest) -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.Stake(actor, request), 'stake_result', 'ok', mvp_pb2.UserPredictionView)
def StakeErr(servicer: Servicer, actor: Optional[AuthorizingUsername], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse.Error:
  return assert_oneof(servicer.Stake(actor, request), 'stake_result', 'error', mvp_pb2.StakeResponse.Error)

def FollowOk(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, follow: bool) -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.Follow(actor, mvp_pb2.FollowRequest(prediction_id=prediction_id, follow=follow)), 'follow_result', 'ok', mvp_pb2.UserPredictionView)
def FollowErr(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, follow: bool) -> mvp_pb2.FollowResponse.Error:
  return assert_oneof(servicer.Follow(actor, mvp_pb2.FollowRequest(prediction_id=prediction_id, follow=follow)), 'follow_result', 'error', mvp_pb2.FollowResponse.Error)

def ResolveOk(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, resolution: mvp_pb2.Resolution.V, notes: str = '') -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.Resolve(actor, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=resolution, notes=notes)), 'resolve_result', 'ok', mvp_pb2.UserPredictionView)
def ResolveErr(servicer: Servicer, actor: Optional[AuthorizingUsername], prediction_id: PredictionId, resolution: mvp_pb2.Resolution.V, notes: str = '') -> mvp_pb2.ResolveResponse.Error:
  return assert_oneof(servicer.Resolve(actor, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=resolution, notes=notes)), 'resolve_result', 'error', mvp_pb2.ResolveResponse.Error)

def SetTrustedOk(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username, trusted: bool) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.SetTrusted(actor, mvp_pb2.SetTrustedRequest(who=who, trusted=trusted)), 'set_trusted_result', 'ok', mvp_pb2.GenericUserInfo)
def SetTrustedErr(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username, trusted: bool) -> mvp_pb2.SetTrustedResponse.Error:
  return assert_oneof(servicer.SetTrusted(actor, mvp_pb2.SetTrustedRequest(who=who, trusted=trusted)), 'set_trusted_result', 'error', mvp_pb2.SetTrustedResponse.Error)

def GetUserOk(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username) -> mvp_pb2.Relationship:
  return assert_oneof(servicer.GetUser(actor, mvp_pb2.GetUserRequest(who=who)), 'get_user_result', 'ok', mvp_pb2.Relationship)
def GetUserErr(servicer: Servicer, actor: Optional[AuthorizingUsername], who: Username) -> mvp_pb2.GetUserResponse.Error:
  return assert_oneof(servicer.GetUser(actor, mvp_pb2.GetUserRequest(who=who)), 'get_user_result', 'error', mvp_pb2.GetUserResponse.Error)

def ChangePasswordOk(servicer: Servicer, actor: Optional[AuthorizingUsername], old_password: str, new_password: str) -> object:
  return assert_oneof(servicer.ChangePassword(actor, mvp_pb2.ChangePasswordRequest(old_password=old_password, new_password=new_password)), 'change_password_result', 'ok', object)
def ChangePasswordErr(servicer: Servicer, actor: Optional[AuthorizingUsername], old_password: str, new_password: str) -> mvp_pb2.ChangePasswordResponse.Error:
  return assert_oneof(servicer.ChangePassword(actor, mvp_pb2.ChangePasswordRequest(old_password=old_password, new_password=new_password)), 'change_password_result', 'error', mvp_pb2.ChangePasswordResponse.Error)

def GetSettingsOk(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.GetSettings(actor, mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
def GetSettingsErr(servicer: Servicer, actor: Optional[AuthorizingUsername]) -> mvp_pb2.GetSettingsResponse.Error:
  return assert_oneof(servicer.GetSettings(actor, mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'error', mvp_pb2.GetSettingsResponse.Error)

def SendInvitationOk(servicer: Servicer, actor: Optional[AuthorizingUsername], recipient: str) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.SendInvitation(actor, mvp_pb2.SendInvitationRequest(recipient=recipient)), 'send_invitation_result', 'ok', mvp_pb2.GenericUserInfo)
def SendInvitationErr(servicer: Servicer, actor: Optional[AuthorizingUsername], recipient: str) -> mvp_pb2.SendInvitationResponse.Error:
  return assert_oneof(servicer.SendInvitation(actor, mvp_pb2.SendInvitationRequest(recipient=recipient)), 'send_invitation_result', 'error', mvp_pb2.SendInvitationResponse.Error)

def CheckInvitationOk(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> mvp_pb2.CheckInvitationResponse.Result:
  return assert_oneof(servicer.CheckInvitation(actor, mvp_pb2.CheckInvitationRequest(nonce=nonce)), 'check_invitation_result', 'ok', mvp_pb2.CheckInvitationResponse.Result)
def CheckInvitationErr(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> mvp_pb2.CheckInvitationResponse.Error:
  return assert_oneof(servicer.CheckInvitation(actor, mvp_pb2.CheckInvitationRequest(nonce=nonce)), 'check_invitation_result', 'error', mvp_pb2.CheckInvitationResponse.Error)

def AcceptInvitationOk(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.AcceptInvitation(actor, mvp_pb2.AcceptInvitationRequest(nonce=nonce)), 'accept_invitation_result', 'ok', mvp_pb2.GenericUserInfo)
def AcceptInvitationErr(servicer: Servicer, actor: Optional[AuthorizingUsername], nonce: str) -> mvp_pb2.AcceptInvitationResponse.Error:
  return assert_oneof(servicer.AcceptInvitation(actor, mvp_pb2.AcceptInvitationRequest(nonce=nonce)), 'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error)
