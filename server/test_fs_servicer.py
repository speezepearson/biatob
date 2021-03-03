import contextlib
import copy
from pathlib import Path
import random
from typing import Tuple

import pytest

from .protobuf import mvp_pb2
from .server import FsBackedServicer
from .test_utils import *

def new_user_token(fs_servicer: FsBackedServicer, username: str) -> mvp_pb2.AuthToken:
  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username=username, password=f'{username} password'))
  assert resp.WhichOneof('register_username_result') == 'ok', resp
  return resp.ok.token


def alice_bob_tokens(fs_servicer: FsBackedServicer) -> Tuple[mvp_pb2.AuthToken, mvp_pb2.AuthToken]:
  token_a = new_user_token(fs_servicer, 'Alice')
  token_b = new_user_token(fs_servicer, 'Bob')

  fs_servicer.SetTrusted(token_a, mvp_pb2.SetTrustedRequest(who=token_b.owner, trusted=True))
  fs_servicer.SetTrusted(token_b, mvp_pb2.SetTrustedRequest(who=token_a.owner, trusted=True))

  return (token_a, token_b)

def some_create_prediction_request(**kwargs) -> mvp_pb2.CreatePredictionRequest:
  init_kwargs = dict(
    prediction='prediction!',
    certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
    maximum_stake_cents=100_00,
    open_seconds=123,
    resolves_at_unixtime=int(2e9),
    special_rules='rules!',
  )
  init_kwargs.update(kwargs)
  return mvp_pb2.CreatePredictionRequest(**init_kwargs)  # type: ignore




async def test_cuj__register__create__invite__accept__stake__resolve(fs_servicer: FsBackedServicer, clock: MockClock):
  creator_token = assert_oneof(
    fs_servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='creator', password='secret')),
    'register_username_result', 'ok', mvp_pb2.AuthSuccess).token

  prediction_id = assert_oneof(
    fs_servicer.CreatePrediction(creator_token, mvp_pb2.CreatePredictionRequest(
      prediction='a thing will happen',
      resolves_at_unixtime=clock.now() + 86400,
      certainty=mvp_pb2.CertaintyRange(low=0.40, high=0.60),
      maximum_stake_cents=100_00,
      open_seconds=3600,
    )),
    'create_prediction_result', 'new_prediction_id', int)

  invitation_id = assert_oneof(
    fs_servicer.CreateInvitation(creator_token, mvp_pb2.CreateInvitationRequest()),
    'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id

  assert assert_oneof(
    fs_servicer.CheckInvitation(None, mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
    'check_invitation_result', 'is_open', bool)

  friend_token = assert_oneof(
    fs_servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='friend', password='secret')),
    'register_username_result', 'ok', mvp_pb2.AuthSuccess).token

  friend_settings = assert_oneof(
    fs_servicer.AcceptInvitation(friend_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
    'accept_invitation_result', 'ok', mvp_pb2.GenericUserInfo)
  assert creator_token.owner in friend_settings.trusted_users

  prediction = assert_oneof(
    fs_servicer.Stake(friend_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=6_00)),
    'stake_result', 'ok', mvp_pb2.UserPredictionView)
  assert list(prediction.your_trades) == [mvp_pb2.Trade(
    bettor=friend_token.owner,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=6_00,
    creator_stake_cents=4_00,
    transacted_unixtime=clock.now(),
  )]

  prediction = assert_oneof(
    fs_servicer.Resolve(creator_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES)),
    'resolve_result', 'ok', mvp_pb2.UserPredictionView)
  assert list(prediction.resolutions) ==[mvp_pb2.ResolutionEvent(unixtime=clock.now(), resolution=mvp_pb2.RESOLUTION_YES)]


async def test_Whoami(fs_servicer: FsBackedServicer):
  resp = fs_servicer.Whoami(None, mvp_pb2.WhoamiRequest())
  assert not resp.HasField('auth')

  rando_token = new_user_token(fs_servicer, 'rando')
  resp = fs_servicer.Whoami(rando_token, mvp_pb2.WhoamiRequest())
  assert resp.auth == rando_token


def test_LogInUsername(fs_servicer: FsBackedServicer):
  rando_token = new_user_token(fs_servicer, 'rando')
  resp = fs_servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username='rando', password='rando password'))
  assert resp.WhichOneof('log_in_username_result') == 'ok', resp
  assert resp.ok.token.owner == rando_token.owner

  resp = fs_servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username='rando', password='WRONG'))
  assert resp.WhichOneof('log_in_username_result') == 'error', resp
  assert not resp.HasField('ok')

  resp = fs_servicer.LogInUsername(rando_token, mvp_pb2.LogInUsernameRequest(username='rando', password='WRONG'))
  assert resp.WhichOneof('log_in_username_result') == 'error', resp
  assert not resp.HasField('ok')


def test_RegisterUsername(fs_servicer: FsBackedServicer):
  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'ok', resp
  token = resp.ok.token
  assert token.owner.username == 'potato'

  resp = fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'error', resp

  resp = fs_servicer.RegisterUsername(token=token, request=mvp_pb2.RegisterUsernameRequest(username='potato2', password='secret'))
  assert resp.WhichOneof('register_username_result') == 'error', resp



def test_CreatePrediction_returns_distinct_ids(token_mint, fs_servicer):
  token = new_user_token(fs_servicer, 'rando')
  ids = {fs_servicer.CreatePrediction(token, some_create_prediction_request()).new_prediction_id for _ in range(30)}
  assert len(ids) == 30


def test_GetPrediction(fs_servicer: FsBackedServicer, clock: MockClock):
  req = some_create_prediction_request()
  rando_token = new_user_token(fs_servicer, 'rando')
  prediction_id = fs_servicer.CreatePrediction(
    token=rando_token,
    request=copy.deepcopy(req),
  ).new_prediction_id

  resp = fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
  assert resp == mvp_pb2.GetPredictionResponse(prediction=mvp_pb2.UserPredictionView(
    prediction=req.prediction,
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


def test_ListMyStakes(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  prediction_1_id = fs_servicer.CreatePrediction(token=alice_token, request=some_create_prediction_request()).new_prediction_id
  prediction_2_id = fs_servicer.CreatePrediction(token=alice_token, request=some_create_prediction_request()).new_prediction_id
  prediction_3_id = fs_servicer.CreatePrediction(token=alice_token, request=some_create_prediction_request()).new_prediction_id

  resp = fs_servicer.ListMyStakes(bob_token, mvp_pb2.ListMyStakesRequest())
  assert resp.WhichOneof('list_my_stakes_result') == 'ok'
  assert set(resp.ok.predictions.keys()) == set()

  fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_1_id, bettor_is_a_skeptic=True, bettor_stake_cents=10))
  resp = fs_servicer.ListMyStakes(bob_token, mvp_pb2.ListMyStakesRequest())
  assert resp.WhichOneof('list_my_stakes_result') == 'ok'
  assert set(resp.ok.predictions.keys()) == {prediction_1_id}

  fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_2_id, bettor_is_a_skeptic=True, bettor_stake_cents=10))
  resp = fs_servicer.ListMyStakes(bob_token, mvp_pb2.ListMyStakesRequest())
  assert resp.WhichOneof('list_my_stakes_result') == 'ok'
  assert set(resp.ok.predictions.keys()) == {prediction_1_id, prediction_2_id}


def test_Stake(fs_servicer, clock):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  prediction_id = fs_servicer.CreatePrediction(
    token=alice_token,
    request=some_create_prediction_request(
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
      maximum_stake_cents=100_00,
    ),
  ).new_prediction_id
  assert prediction_id != 0

  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=20_00,
  ))
  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=90_00,
  ))
  assert list(fs_servicer.GetPrediction(alice_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)).prediction.your_trades) == [
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
  prediction_id = fs_servicer.CreatePrediction(
    token=alice_token,
    request=some_create_prediction_request(
      certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
      maximum_stake_cents=100_00,
    ),
  ).new_prediction_id
  assert prediction_id != 0

  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=25_00,
  ))
  fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=900_00,
  ))

  assert fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
    bettor_is_a_skeptic=True,
    bettor_stake_cents=1,
  )).WhichOneof('stake_result') == 'error'
  assert fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
    bettor_is_a_skeptic=False,
    bettor_stake_cents=9,
  )).WhichOneof('stake_result') == 'error'

def test_Stake_enforces_trust(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  rando_token = new_user_token(fs_servicer, 'rando')
  prediction_id = fs_servicer.CreatePrediction(
    token=alice_token,
    request=some_create_prediction_request(),
  ).new_prediction_id
  assert prediction_id != 0

  stake_req = mvp_pb2.StakeRequest(
    prediction_id=prediction_id,
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
  prediction_id = fs_servicer.CreatePrediction(
    token=rando_token,
    request=some_create_prediction_request(),
  ).new_prediction_id

  t0 = clock.now()
  planned_events = [
    mvp_pb2.ResolutionEvent(unixtime=t0+0, resolution=mvp_pb2.RESOLUTION_YES),
    mvp_pb2.ResolutionEvent(unixtime=t0+1, resolution=mvp_pb2.RESOLUTION_NONE_YET),
    mvp_pb2.ResolutionEvent(unixtime=t0+2, resolution=mvp_pb2.RESOLUTION_NO),
  ]

  resolve_resp = fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES))
  assert resolve_resp.WhichOneof('resolve_result') == 'ok', resolve_resp
  get_resp = fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
  assert list(get_resp.prediction.resolutions) == planned_events[:1]

  clock.tick()
  t1 = clock.now()
  resolve_resp = fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_NONE_YET))
  assert resolve_resp.WhichOneof('resolve_result') == 'ok', resolve_resp
  get_resp = fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
  assert list(get_resp.prediction.resolutions) == planned_events[:2]

  clock.tick()
  t2 = clock.now()
  resolve_resp = fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_NO))
  assert resolve_resp.WhichOneof('resolve_result') == 'ok', resolve_resp
  get_resp = fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
  assert list(get_resp.prediction.resolutions) == planned_events


def test_Resolve_ensures_creator(fs_servicer: FsBackedServicer):
  alice_token, bob_token = alice_bob_tokens(fs_servicer)
  prediction_id = fs_servicer.CreatePrediction(
    token=alice_token,
    request=some_create_prediction_request(),
  ).new_prediction_id

  resp = fs_servicer.Resolve(bob_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_NO))
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
