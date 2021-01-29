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

def test_mint_auth_token(temp_path):
  marketplace = FSMarketplace(state_path=temp_path)

  with pytest.raises(KeyError):
    marketplace.mint_auth_token(username='Spencer', password='secret')

  marketplace.register_user(username='Spencer', password='secret')
  marketplace.mint_auth_token(username='Spencer', password='secret')
  with pytest.raises(ValueError):
    marketplace.mint_auth_token(username='Spencer', password='wrong pw')
