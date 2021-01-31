import contextlib
from pathlib import Path
import random

import bcrypt  # type: ignore
import pytest

from .protobuf import mvp_pb2
from .server import FSMarketplace

@pytest.fixture
def temp_path():
  result = Path(f'/tmp/test_fs_marketplace-{random.randrange(2**32)}')
  yield result
  if result.exists():
    result.unlink()

def test_register_username(temp_path):
  marketplace = FSMarketplace(state_path=temp_path)

  assert marketplace.get_username_info('potato') is None
  marketplace.register_username(username='potato', password='secret')
  assert bcrypt.checkpw(b'secret', marketplace.get_username_info('potato').password_bcrypt)

def test_create_market_returns_distinct_ids(temp_path):
  market = mvp_pb2.WorldState.Market()
  marketplace = FSMarketplace(state_path=temp_path, random_seed=0)
  ids = {marketplace.create_market(market) for _ in range(30)}
  assert len(ids) == 30

def test_create_market_obeys_safe_uint_limit(temp_path):
  market = mvp_pb2.WorldState.Market()
  marketplace = FSMarketplace(state_path=temp_path, random_seed=0)
  ids = {marketplace.create_market(market) for _ in range(30)}
  for id in ids:
    assert id < 2**50, id
