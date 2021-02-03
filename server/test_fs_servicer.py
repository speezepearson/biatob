import contextlib
from pathlib import Path
import random

import bcrypt  # type: ignore
import pytest

from .protobuf import mvp_pb2
from .server import FsBackedServicer
from .test_utils import clock, token_mint, fs_servicer

def test_RegisterUsername(fs_servicer):
  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'ok'
  token = resp.ok
  assert token.owner.username == 'potato'

  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'error'

  resp = fs_servicer.RegisterUsername(token=token, request=mvp_pb2.RegisterUsernameRequest(username='potato2', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'error'



def test_CreateMarket_returns_distinct_ids(token_mint, fs_servicer):
  token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret')).ok
  ids = {fs_servicer.CreateMarket(token, mvp_pb2.CreateMarketRequest()).new_market_id for _ in range(30)}
  assert len(ids) == 30

def test_Stake(fs_servicer, clock):
  creator_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='creator', password='secret')).ok
  market_id = fs_servicer.CreateMarket(
    token=creator_token,
    request=mvp_pb2.CreateMarketRequest(
      maximum_stake_cents=100_00,
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    ),
  ).new_market_id
  assert market_id != 0

  bettor_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='bettor', password='secret')).ok
  fs_servicer.SetTrusted(bettor_token, mvp_pb2.SetTrustedRequest(who=creator_token.owner, trusted=True))
  fs_servicer.SetTrusted(creator_token, mvp_pb2.SetTrustedRequest(who=bettor_token.owner, trusted=True))

  fs_servicer.Stake(token=bettor_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=20_00,
  ))
  fs_servicer.Stake(token=bettor_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=90_00,
  ))
  assert list(fs_servicer._get_state().markets.get(market_id).trades) == [
    mvp_pb2.Trade(
      bettor=mvp_pb2.UserId(username='bettor'),
      bettor_is_a_skeptic=True,
      bettor_stake_cents=20_00,
      creator_stake_cents=80_00,
      transacted_unixtime=clock.now(),
    ),
    mvp_pb2.Trade(
      bettor=mvp_pb2.UserId(username='bettor'),
      bettor_is_a_skeptic=False,
      bettor_stake_cents=90_00,
      creator_stake_cents=10_00,
      transacted_unixtime=clock.now(),
    ),
  ]

def test_Stake_protects_against_overpromising(fs_servicer):
  creator_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret')).ok
  market_id = fs_servicer.CreateMarket(
    token=creator_token,
    request=mvp_pb2.CreateMarketRequest(
      maximum_stake_cents=100_00,
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    ),
  ).new_market_id
  assert market_id != 0

  bettor_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='bettor', password='secret')).ok
  fs_servicer.SetTrusted(bettor_token, mvp_pb2.SetTrustedRequest(who=creator_token.owner, trusted=True))
  fs_servicer.SetTrusted(creator_token, mvp_pb2.SetTrustedRequest(who=bettor_token.owner, trusted=True))

  fs_servicer.Stake(token=bettor_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=25_00,
  ))
  fs_servicer.Stake(token=bettor_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=900_00,
  ))

  assert fs_servicer.Stake(bettor_token, mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=1,
  )).WhichOneof('stake_result') == 'error'
  assert fs_servicer.Stake(bettor_token, mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=9,
  )).WhichOneof('stake_result') == 'error'

def test_Stake_enforces_trust(fs_servicer):
  creator_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret')).ok
  market_id = fs_servicer.CreateMarket(
    token=creator_token,
    request=mvp_pb2.CreateMarketRequest(
      maximum_stake_cents=100_00,
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    ),
  ).new_market_id
  assert market_id != 0


  stake_req = mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=10_00,
  )

  rando_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='rando', password='secret')).ok
  assert fs_servicer.Stake(rando_token, stake_req).WhichOneof('stake_result') == 'error'

  truster_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='truster', password='secret')).ok
  fs_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=creator_token.owner, trusted=True))
  assert fs_servicer.Stake(truster_token, stake_req).WhichOneof('stake_result') == 'error'

  trustee_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='trustee', password='secret')).ok
  fs_servicer.SetTrusted(creator_token, mvp_pb2.SetTrustedRequest(who=trustee_token.owner, trusted=True))
  assert fs_servicer.Stake(trustee_token, stake_req).WhichOneof('stake_result') == 'error'

  friend_token = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='friend', password='secret')).ok
  fs_servicer.SetTrusted(friend_token, mvp_pb2.SetTrustedRequest(who=creator_token.owner, trusted=True))
  fs_servicer.SetTrusted(creator_token, mvp_pb2.SetTrustedRequest(who=friend_token.owner, trusted=True))
  assert fs_servicer.Stake(friend_token, stake_req).WhichOneof('stake_result') == 'ok'
