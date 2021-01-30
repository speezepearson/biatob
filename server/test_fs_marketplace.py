import contextlib
from pathlib import Path
import random

import pytest

from .server import FSMarketplace

@pytest.fixture
def temp_path():
  result = Path(f'/tmp/test_fs_marketplace-{random.randrange(2**32)}')
  yield result
  if result.exists():
    result.unlink()

def test_register_username(temp_path):
  marketplace = FSMarketplace(state_path=temp_path)

  assert 'potato' not in marketplace._get_state().username_users
  marketplace.register_username(username='potato', password='secret')
  assert 'potato' in marketplace._get_state().username_users
