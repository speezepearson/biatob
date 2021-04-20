import asyncio
import contextlib
import copy
import random
import pytest
import unittest.mock
from typing import Type, TypeVar, Iterator

from google.protobuf.message import Message

from .core import PredictionId, Servicer, TokenMint
from .fs_servicer import FsBackedServicer, FsStorage
from .protobuf import mvp_pb2


class MockClock:
  def __init__(self):
    self._unixtime = 1000000000
  def now(self) -> int:
    return self._unixtime
  def tick(self, seconds=1) -> None:
    self._unixtime += seconds

@pytest.fixture
def clock():
  return MockClock()

@pytest.fixture
def token_mint(clock):
  return TokenMint(secret_key=b'test secret', clock=clock.now)

@pytest.fixture
def fs_storage(tmp_path):
  return FsStorage(tmp_path / 'state.WorldState.pb')

@pytest.fixture
def emailer():
  return unittest.mock.Mock(
    send_resolution_notifications=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_resolution_reminder=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_email_verification=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
    send_backup=unittest.mock.Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)),
  )

@pytest.fixture
def fs_servicer(fs_storage, clock, token_mint, emailer):
  return FsBackedServicer(
    storage=fs_storage,
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
  assert old.creator.username == creator_token.owner
  yield
  new = assert_oneof(servicer.GetPrediction(creator_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
  assert old == new
