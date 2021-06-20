import asyncio
import contextlib
import datetime
import pytest
import unittest.mock
from typing import Any, Callable, Tuple, Type, TypeVar, Iterator

from google.protobuf.message import Message

from .core import PredictionId, Servicer, TokenMint
from .emailer import Emailer
from .protobuf import mvp_pb2
from .sql_servicer import SqlServicer, SqlConn
from .sql_schema import create_sqlite_engine

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
  )

@pytest.fixture
def any_servicer(clock, token_mint, emailer):
  engine = create_sqlite_engine(':memory:')
  with engine.connect() as conn:
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
def assert_user_unchanged(servicer: Servicer, token: mvp_pb2.AuthToken, password: str) -> Iterator[None]:
  assert_oneof(servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username=token.owner, password=password)), 'log_in_username_result', 'ok', mvp_pb2.AuthSuccess)
  old_settings = assert_oneof(servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
  yield
  new_settings = assert_oneof(servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
  assert old_settings == new_settings
  assert_oneof(servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username=token.owner, password=password)), 'log_in_username_result', 'ok', mvp_pb2.AuthSuccess)


@contextlib.contextmanager
def assert_prediction_unchanged(servicer: Servicer, prediction_id: PredictionId, creator_token: mvp_pb2.AuthToken) -> Iterator[None]:
  old = assert_oneof(servicer.GetPrediction(creator_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
  assert old.creator == creator_token.owner
  yield
  new = assert_oneof(servicer.GetPrediction(creator_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
  assert old == new


def new_user_token(servicer: Servicer, username: str) -> mvp_pb2.AuthToken:
  resp = servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username=username, password=f'{username} password'))
  assert resp.WhichOneof('register_username_result') == 'ok', resp
  return resp.ok.token


def alice_bob_tokens(servicer: Servicer) -> Tuple[mvp_pb2.AuthToken, mvp_pb2.AuthToken]:
  token_a = new_user_token(servicer, 'Alice')
  token_b = new_user_token(servicer, 'Bob')

  servicer.SetTrusted(token_a, mvp_pb2.SetTrustedRequest(who=token_b.owner, trusted=True))
  servicer.SetTrusted(token_b, mvp_pb2.SetTrustedRequest(who=token_a.owner, trusted=True))

  return (token_a, token_b)

def some_create_prediction_request(**kwargs) -> mvp_pb2.CreatePredictionRequest:
  init_kwargs = dict(
    prediction='prediction!',
    certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
    open_seconds=123,
    resolves_at_unixtime=int(2e9),
    special_rules='rules!',
  )
  init_kwargs.update(kwargs)
  return mvp_pb2.CreatePredictionRequest(**init_kwargs)  # type: ignore

def set_and_verify_email(
  servicer: Servicer,
  emailer: Emailer,
  token: mvp_pb2.AuthToken,
  email_address: str,
) -> None:
  servicer.SetEmail(token, mvp_pb2.SetEmailRequest(email=email_address))
  servicer.VerifyEmail(token, mvp_pb2.VerifyEmailRequest(
    code=get_call_kwarg(emailer.send_email_verification, 'code'),
  ))

def get_call_kwarg(mock_method: Callable[..., Any], kwarg: str) -> Any:
  return mock_method.call_args[1][kwarg]  # type: ignore
