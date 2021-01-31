from pathlib import Path
import random
import pytest


@pytest.fixture
def temp_path_fixture():
  result = Path(f'/tmp/test_fs_marketplace-{random.randrange(2**32)}')
  yield result
  if result.exists():
    result.unlink()


class MockClock:
  def __init__(self):
    self._unixtime = 1000000000
  def now(self) -> int:
    return self._unixtime
  def tick(self, seconds=1) -> None:
    self._unixtime += seconds

@pytest.fixture
def clock_fixture():
  return MockClock()
