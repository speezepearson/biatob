import contextlib
import copy
from pathlib import Path
import random
from typing import Tuple

import bcrypt  # type: ignore
import pytest

from .protobuf import mvp_pb2
from .server import FsBackedServicer
from .test_utils import clock, token_mint, fs_servicer, MockClock

def new_user_token(fs_servicer: FsBackedServicer, username: str) -> mvp_pb2.AuthToken:
  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username=username, password=f'{username} password'))
  assert resp.WhichOneof('register_username_result') == 'ok', resp
  return resp.ok


def alice_bob_tokens(fs_servicer: FsBackedServicer) -> Tuple[mvp_pb2.AuthToken, mvp_pb2.AuthToken]:
  token_a = new_user_token(fs_servicer, 'Alice')
  token_b = new_user_token(fs_servicer, 'Bob')

  fs_servicer.SetTrusted(token_a, mvp_pb2.SetTrustedRequest(who=token_b.owner, trusted=True))
  fs_servicer.SetTrusted(token_b, mvp_pb2.SetTrustedRequest(who=token_a.owner, trusted=True))

  return (token_a, token_b)

def some_create_market_request(**kwargs) -> mvp_pb2.CreateMarketRequest:
  init_kwargs = dict(
    question='question!',
    certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
    open_seconds=123,
    resolves_at_unixtime=int(2e9),
    special_rules='rules!',
  )
  init_kwargs.update(kwargs)
  return mvp_pb2.CreateMarketRequest(**init_kwargs)  # type: ignore

def test_Whoami(fs_servicer: FsBackedServicer):
  resp = fs_servicer.Whoami(None, mvp_pb2.WhoamiRequest())
  assert resp.auth.ByteSize() == 0

  rando_token = new_user_token(fs_servicer, 'rando')
  resp = fs_servicer.Whoami(rando_token, mvp_pb2.WhoamiRequest())
  assert resp.auth == rando_token


def test_LogInUsername(fs_servicer: FsBackedServicer):
  rando_token = new_user_token(fs_servicer, 'rando')
  resp = fs_servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username='rando', password='rando password'))
  assert resp.WhichOneof('log_in_username_result') == 'ok', resp
  assert resp.ok.owner == rando_token.owner

  resp = fs_servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username='rando', password='WRONG'))
  assert resp.WhichOneof('log_in_username_result') == 'error', resp
  assert resp.ok.ByteSize() == 0

  resp = fs_servicer.LogInUsername(rando_token, mvp_pb2.LogInUsernameRequest(username='rando', password='WRONG'))
  assert resp.WhichOneof('log_in_username_result') == 'error', resp
  assert resp.ok.ByteSize() == 0


def test_RegisterUsername(fs_servicer: FsBackedServicer):
  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'ok', resp
  token = resp.ok
  assert token.owner.username == 'potato'

  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'error', resp

  resp = fs_servicer.RegisterUsername(token=token, request=mvp_pb2.RegisterUsernameRequest(username='potato2', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'error', resp



def test_CreateMarket_returns_distinct_ids(token_mint, fs_servicer):
  token = new_user_token(fs_servicer, 'rando')
  ids = {fs_servicer.CreateMarket(token, some_create_market_request()).new_market_id for _ in range(30)}
  assert len(ids) == 30


def test_GetMarket(fs_servicer: FsBackedServicer, clock: MockClock):
  req = some_create_market_request()
  rando_token = new_user_token(fs_servicer, 'rando')
  market_id = fs_servicer.CreateMarket(
    token=rando_token,
    request=copy.deepcopy(req),
  ).new_market_id

  resp = fs_servicer.GetMarket(rando_token, mvp_pb2.GetMarketRequest(market_id=market_id))
  assert resp == mvp_pb2.GetMarketResponse(market=mvp_pb2.UserMarketView(
    question=req.question,
    certainty=req.certainty,
    maximum_stake_cents=req.maximum_stake_cents,
    remaining_stake_cents_vs_believers=req.maximum_stake_cents,
    remaining_stake_cents_vs_skeptics=req.maximum_stake_cents,
    created_unixtime=clock.now(),
    closes_unixtime=clock.now() + req.open_seconds,
    resolves_at_unixtime=req.resolves_at_unixtime,
    special_rules=req.special_rules,
    creator=mvp_pb2.UserUserView(display_name='rando', is_self=True, is_trusted=True, trusts_you=True),
    resolutions=[],
    your_trades=[],
  ))


def test_ListMyMarkets(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  market_1_id = fs_servicer.CreateMarket(token=alice_token, request=some_create_market_request()).new_market_id
  market_2_id = fs_servicer.CreateMarket(token=alice_token, request=some_create_market_request()).new_market_id
  market_3_id = fs_servicer.CreateMarket(token=alice_token, request=some_create_market_request()).new_market_id

  resp = fs_servicer.ListMyMarkets(bob_token, mvp_pb2.ListMyMarketsRequest())
  assert resp.WhichOneof('list_my_markets_result') == 'ok'
  assert set(resp.ok.markets.keys()) == set()

  fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(market_id=market_1_id, bettor_is_a_skeptic=True, bettor_stake_cents=10))
  resp = fs_servicer.ListMyMarkets(bob_token, mvp_pb2.ListMyMarketsRequest())
  assert resp.WhichOneof('list_my_markets_result') == 'ok'
  assert set(resp.ok.markets.keys()) == {market_1_id}

  fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(market_id=market_2_id, bettor_is_a_skeptic=True, bettor_stake_cents=10))
  resp = fs_servicer.ListMyMarkets(bob_token, mvp_pb2.ListMyMarketsRequest())
  assert resp.WhichOneof('list_my_markets_result') == 'ok'
  assert set(resp.ok.markets.keys()) == {market_1_id, market_2_id}


def test_Stake(fs_servicer, clock):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  market_id = fs_servicer.CreateMarket(
    token=alice_token,
    request=some_create_market_request(
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
      maximum_stake_cents=100_00,
    ),
  ).new_market_id
  assert market_id != 0

  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=20_00,
  ))
  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=90_00,
  ))
  assert list(fs_servicer.GetMarket(alice_token, mvp_pb2.GetMarketRequest(market_id=market_id)).market.your_trades) == [
    mvp_pb2.Trade(
      bettor=bob_token.owner,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=20_00,
      creator_stake_cents=80_00,
      transacted_unixtime=clock.now(),
    ),
    mvp_pb2.Trade(
      bettor=bob_token.owner,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=90_00,
      creator_stake_cents=10_00,
      transacted_unixtime=clock.now(),
    ),
  ]

def test_Stake_protects_against_overpromising(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  market_id = fs_servicer.CreateMarket(
    token=alice_token,
    request=some_create_market_request(
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
      maximum_stake_cents=100_00,
    ),
  ).new_market_id
  assert market_id != 0

  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=25_00,
  ))
  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=900_00,
  ))

  assert fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=1,
  )).WhichOneof('stake_result') == 'error'
  assert fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=9,
  )).WhichOneof('stake_result') == 'error'

def test_Stake_enforces_trust(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  rando_token = new_user_token(fs_servicer, 'rando')
  market_id = fs_servicer.CreateMarket(
    token=alice_token,
    request=some_create_market_request(),
  ).new_market_id
  assert market_id != 0

  stake_req = mvp_pb2.StakeRequest(
    market_id=market_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=10_00,
  )

  assert fs_servicer.Stake(rando_token, stake_req).WhichOneof('stake_result') == 'error'

  truster_token = new_user_token(fs_servicer, 'truster')
  fs_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=alice_token.owner, trusted=True))
  assert fs_servicer.Stake(truster_token, stake_req).WhichOneof('stake_result') == 'error'

  trustee_token = new_user_token(fs_servicer, 'trustee')
  fs_servicer.SetTrusted(alice_token, mvp_pb2.SetTrustedRequest(who=trustee_token.owner, trusted=True))
  assert fs_servicer.Stake(trustee_token, stake_req).WhichOneof('stake_result') == 'error'

  assert fs_servicer.Stake(bob_token, stake_req).WhichOneof('stake_result') == 'ok'


def test_Resolve(fs_servicer: FsBackedServicer, clock: MockClock):
  rando_token = new_user_token(fs_servicer, 'rando')
  market_id = fs_servicer.CreateMarket(
    token=rando_token,
    request=some_create_market_request(),
  ).new_market_id

  t0 = clock.now()
  planned_events = [
    mvp_pb2.ResolutionEvent(unixtime=t0+0, resolution=mvp_pb2.RESOLUTION_YES),
    mvp_pb2.ResolutionEvent(unixtime=t0+1, resolution=mvp_pb2.RESOLUTION_NONE_YET),
    mvp_pb2.ResolutionEvent(unixtime=t0+2, resolution=mvp_pb2.RESOLUTION_NO),
  ]

  resolve_resp = fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(market_id=market_id, resolution=mvp_pb2.RESOLUTION_YES))
  assert resolve_resp.WhichOneof('resolve_result') == 'ok', resolve_resp
  get_resp = fs_servicer.GetMarket(rando_token, mvp_pb2.GetMarketRequest(market_id=market_id))
  assert list(get_resp.market.resolutions) == planned_events[:1]

  clock.tick()
  t1 = clock.now()
  resolve_resp = fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(market_id=market_id, resolution=mvp_pb2.RESOLUTION_NONE_YET))
  assert resolve_resp.WhichOneof('resolve_result') == 'ok', resolve_resp
  get_resp = fs_servicer.GetMarket(rando_token, mvp_pb2.GetMarketRequest(market_id=market_id))
  assert list(get_resp.market.resolutions) == planned_events[:2]

  clock.tick()
  t2 = clock.now()
  resolve_resp = fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(market_id=market_id, resolution=mvp_pb2.RESOLUTION_NO))
  assert resolve_resp.WhichOneof('resolve_result') == 'ok', resolve_resp
  get_resp = fs_servicer.GetMarket(rando_token, mvp_pb2.GetMarketRequest(market_id=market_id))
  assert list(get_resp.market.resolutions) == planned_events


def test_Resolve_ensures_creator(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  market_id = fs_servicer.CreateMarket(
    token=alice_token,
    request=some_create_market_request(),
  ).new_market_id

  resp = fs_servicer.Resolve(bob_token, mvp_pb2.ResolveRequest(market_id=market_id, resolution=mvp_pb2.RESOLUTION_NO))
  assert resp.WhichOneof('resolve_result') == 'error', resp
  assert 'not the creator' in str(resp.error)


def test_GetUser(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)

  resp = fs_servicer.GetUser(alice_token, mvp_pb2.GetUserRequest(who=bob_token.owner))
  assert resp.ok == mvp_pb2.UserUserView(display_name='Bob', is_self=False, is_trusted=True, trusts_you=True)

  truster_token = new_user_token(fs_servicer, 'truster')
  fs_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=alice_token.owner, trusted=True))
  resp = fs_servicer.GetUser(alice_token, mvp_pb2.GetUserRequest(who=truster_token.owner))
  assert resp.ok == mvp_pb2.UserUserView(display_name='truster', is_self=False, is_trusted=False, trusts_you=True)

  resp = fs_servicer.GetUser(None, mvp_pb2.GetUserRequest(who=bob_token.owner))
  assert resp.ok == mvp_pb2.UserUserView(display_name='Bob', is_self=False, is_trusted=False, trusts_you=False)
