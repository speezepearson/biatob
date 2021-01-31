import contextlib
from pathlib import Path
import random

import bcrypt  # type: ignore
import pytest

from .protobuf import mvp_pb2
from .server import FSMarketplace
from .test_utils import clock_fixture

@pytest.fixture
def marketplace(clock_fixture):
  temp_path = Path(f'/tmp/test_fs_marketplace-{random.randrange(2**32)}')
  yield FSMarketplace(state_path=temp_path, random_seed=0, clock=clock_fixture.now)
  if temp_path.exists():
    temp_path.unlink()

def test_register_username(marketplace):
  assert marketplace.get_username_info('potato') is None
  marketplace.register_username(username='potato', password='secret')
  assert bcrypt.checkpw(b'secret', marketplace.get_username_info('potato').password_bcrypt)

def test_create_market_returns_distinct_ids(marketplace):
  market = mvp_pb2.WorldState.Market()
  ids = {marketplace.create_market(market) for _ in range(30)}
  assert len(ids) == 30

def test_create_market_obeys_safe_uint_limit(marketplace):
  market = mvp_pb2.WorldState.Market()
  ids = {marketplace.create_market(market) for _ in range(30)}
  for id in ids:
    assert id < 2**50, id

def test_bet(marketplace, clock_fixture):
  bettor = mvp_pb2.UserId(username='bettor')
  marketplace.register_username(username='bettor', password='.')

  market_id = marketplace.create_market(mvp_pb2.WorldState.Market(
    certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
  ))
  marketplace.bet(
    market_id=market_id,
    bettor=bettor,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=20_00,
  )
  marketplace.bet(
    market_id=market_id,
    bettor=bettor,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=90_00,
  )
  assert list(marketplace.get_market(market_id).trades) == [
    mvp_pb2.WorldState.Trade(
      bettor=bettor,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=20_00,
      creator_stake_cents=80_00,
      transacted_unixtime=clock_fixture.now(),
    ),
    mvp_pb2.WorldState.Trade(
      bettor=bettor,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=90_00,
      creator_stake_cents=10_00,
      transacted_unixtime=clock_fixture.now(),
    ),
  ]

def test_bet_protects_against_overpromising(marketplace):
  bettor = mvp_pb2.UserId(username='bettor')
  marketplace.register_username(username='bettor', password='.')

  market_id = marketplace.create_market(mvp_pb2.WorldState.Market(
    certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
  ))
  marketplace.bet(
    market_id=market_id,
    bettor=bettor,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=25_00,
  )
  marketplace.bet(
    market_id=market_id,
    bettor=bettor,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=900_00,
  )
  with pytest.raises(ValueError):
    marketplace.bet(
      market_id=market_id,
      bettor=bettor,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=1,
    )
  with pytest.raises(ValueError):
    marketplace.bet(
      market_id=market_id,
      bettor=bettor,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=9,
    )
