import asyncio
import random
import pytest
import unittest.mock

from .server import TokenMint, FsBackedServicer, FsStorage


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
