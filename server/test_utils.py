import random
import pytest

from .server import TokenMint, FsBackedServicer


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
def fs_servicer(tmp_path, clock, token_mint):
  return FsBackedServicer(
    state_path=tmp_path / 'state.WorldState.pb',
    random_seed=0,
    clock=clock.now,
    token_mint=token_mint,
  )
