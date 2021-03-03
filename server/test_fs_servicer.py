import contextlib
import copy
from pathlib import Path
import random
from typing import Tuple
from unittest.mock import ANY

import pytest

from .protobuf import mvp_pb2
from .server import FsBackedServicer, Emailer
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


class TestCUJs:
  async def test_cuj__register__create__invite__accept__stake__resolve(self, fs_servicer: FsBackedServicer, clock: MockClock):
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


  async def test_cuj___set_email__verify_email__update_settings(self, fs_servicer: FsBackedServicer, emailer: Emailer):
    token = assert_oneof(
      fs_servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='creator', password='secret')),
      'register_username_result', 'ok', mvp_pb2.AuthSuccess).token

    assert assert_oneof(fs_servicer.SetEmail(token, mvp_pb2.SetEmailRequest(email='nobody@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'nobody@example.com'

    emailer.send_email_verification.assert_called_once()  # type: ignore
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore

    assert assert_oneof(fs_servicer.VerifyEmail(token, mvp_pb2.VerifyEmailRequest(code=code)),
      'verify_email_result', 'ok', mvp_pb2.EmailFlowState).verified == 'nobody@example.com'

    assert not assert_oneof(fs_servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok_username', mvp_pb2.UsernameInfo).info.email_reminders_to_resolve

    assert assert_oneof(fs_servicer.UpdateSettings(token, mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=True))),
      'update_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve

    assert assert_oneof(fs_servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok_username', mvp_pb2.UsernameInfo).info.email_reminders_to_resolve



class TestWhoami:

  async def test_smoke_logged_out(self, fs_servicer: FsBackedServicer):
    assert not fs_servicer.Whoami(token=None, request=mvp_pb2.WhoamiRequest()).HasField('auth')

  async def test_smoke_logged_in(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert fs_servicer.Whoami(token=token, request=mvp_pb2.WhoamiRequest()).auth == token


class TestSignOut:

  async def test_smoke_logged_out(self, fs_servicer: FsBackedServicer):
    fs_servicer.SignOut(token=None, request=mvp_pb2.SignOutRequest())

  async def test_smoke_logged_in(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    fs_servicer.SignOut(token=token, request=mvp_pb2.SignOutRequest())


class TestRegisterUsername:

  async def test_success(self, fs_servicer: FsBackedServicer):
    assert assert_oneof(fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='alice', password='secret')),
      'register_username_result', 'ok', mvp_pb2.AuthSuccess).token.owner.username == 'alice'

  async def test_error_when_already_exists(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    new_user_token(fs_servicer, 'rando')

    for password in ['rando password', 'some other password']:
      with assert_unchanged(fs_storage):
        assert 'username taken' in assert_oneof(fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='rando', password=password)),
          'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error).catchall

  async def test_error_if_already_logged_in(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    with assert_unchanged(fs_storage):
      assert 'first, log out' in str(assert_oneof(fs_servicer.RegisterUsername(token=token, request=mvp_pb2.RegisterUsernameRequest(username='alice', password='secret')),
        'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error))

  async def test_error_if_invalid_username(self, fs_servicer: FsBackedServicer):
    assert 'username must be alphanumeric' in assert_oneof(fs_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='foo bar!baz\xfequux', password='rando password')),
      'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error).catchall


class TestLogInUsername:

  async def test_success(self, fs_servicer: FsBackedServicer):
    new_user_token(fs_servicer, 'rando')
    assert assert_oneof(fs_servicer.LogInUsername(token=None, request=mvp_pb2.LogInUsernameRequest(username='rando', password='rando password')),
      'log_in_username_result', 'ok', mvp_pb2.AuthSuccess).token.owner.username == 'rando'

  async def test_no_such_user(self, fs_servicer: FsBackedServicer):
    assert 'no such user' in assert_oneof(fs_servicer.LogInUsername(token=None, request=mvp_pb2.LogInUsernameRequest(username='alice', password='secret')),
      'log_in_username_result', 'error', mvp_pb2.LogInUsernameResponse.Error).catchall

  async def test_error_if_already_logged_in(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert 'first, log out' in str(assert_oneof(fs_servicer.LogInUsername(token=token, request=mvp_pb2.LogInUsernameRequest(username='alice', password='secret')),
      'log_in_username_result', 'error', mvp_pb2.LogInUsernameResponse.Error))


class TestCreatePrediction:

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    with assert_unchanged(fs_storage):
      assert 'must log in to create predictions' in assert_oneof(fs_servicer.CreatePrediction(token=None, request=some_create_prediction_request()),
        'create_prediction_result', 'error', mvp_pb2.CreatePredictionResponse.Error).catchall

  async def test_smoke_logged_in(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(token=token, request=some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)
    assert prediction_id in fs_storage.get().predictions

  async def test_returns_distinct_ids(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    ids = {fs_servicer.CreatePrediction(token, some_create_prediction_request()).new_prediction_id for _ in range(30)}
    assert len(ids) == 30
    assert len(fs_storage.get().predictions) == 30


class TestGetPrediction:

  async def test_has_all_fields(self, fs_servicer: FsBackedServicer, clock: MockClock):
    req = some_create_prediction_request(
      prediction='a thing will happen',
      special_rules='some special rules',
      maximum_stake_cents=100_00,
      certainty=mvp_pb2.CertaintyRange(low=0.50, high=1.00),
    )
    alice_token, bob_token = alice_bob_tokens(fs_servicer)

    create_time = clock.now()
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(
      token=alice_token,
      request=copy.deepcopy(req),
    ), 'create_prediction_result', 'new_prediction_id', int)

    clock.tick()
    stake_time = clock.now()
    assert_oneof(fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=1_00)),
      'stake_result', 'ok', mvp_pb2.UserPredictionView)

    clock.tick()
    resolve_time = clock.now()
    assert_oneof(fs_servicer.Resolve(alice_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView)

    resp = fs_servicer.GetPrediction(bob_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
    assert resp.prediction == mvp_pb2.UserPredictionView(
      prediction=req.prediction,
      certainty=req.certainty,
      maximum_stake_cents=req.maximum_stake_cents,
      remaining_stake_cents_vs_believers=req.maximum_stake_cents,
      remaining_stake_cents_vs_skeptics=req.maximum_stake_cents - resp.prediction.your_trades[0].creator_stake_cents,
      created_unixtime=create_time,
      closes_unixtime=create_time + req.open_seconds,
      resolves_at_unixtime=req.resolves_at_unixtime,
      special_rules=req.special_rules,
      creator=mvp_pb2.UserUserView(display_name='Alice', is_self=False, is_trusted=True, trusts_you=True),
      resolutions=[mvp_pb2.ResolutionEvent(unixtime=resolve_time, resolution=mvp_pb2.RESOLUTION_YES)],
      your_trades=[mvp_pb2.Trade(bettor=bob_token.owner, bettor_is_a_skeptic=True, bettor_stake_cents=1_00, creator_stake_cents=1_00, transacted_unixtime=stake_time)],
    )


  async def test_success_if_logged_out(self, fs_servicer: FsBackedServicer):
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(new_user_token(fs_servicer, 'rando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)
    assert_oneof(fs_servicer.GetPrediction(token=None, request=mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)

  async def test_success_if_logged_in(self, fs_servicer: FsBackedServicer):
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(new_user_token(fs_servicer, 'rando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)
    assert_oneof(fs_servicer.GetPrediction(token=new_user_token(fs_servicer, 'otherrando'), request=mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)

  async def test_error_if_no_such_prediction(self, fs_servicer: FsBackedServicer):
    assert 'no such prediction' in assert_oneof(fs_servicer.GetPrediction(token=new_user_token(fs_servicer, 'otherrando'), request=mvp_pb2.GetPredictionRequest(prediction_id=12345)),
      'get_prediction_result', 'error', mvp_pb2.GetPredictionResponse.Error).catchall

class TestListMyStakes:

  async def test_success_if_logged_in(self, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    alice_prediction_id = assert_oneof(fs_servicer.CreatePrediction(alice_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int)
    bob_prediction_id = assert_oneof(fs_servicer.CreatePrediction(bob_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int)
    irrelevant_prediction_id = assert_oneof(fs_servicer.CreatePrediction(bob_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int)

    assert_oneof(fs_servicer.Stake(alice_token, mvp_pb2.StakeRequest(prediction_id=bob_prediction_id, bettor_stake_cents=1_00)),
      'stake_result', 'ok', mvp_pb2.UserPredictionView)

    assert set(assert_oneof(fs_servicer.ListMyStakes(token=alice_token, request=mvp_pb2.ListMyStakesRequest()),
      'list_my_stakes_result', 'ok', mvp_pb2.PredictionsById).predictions.keys()) == {alice_prediction_id, bob_prediction_id}

  async def test_error_if_logged_out(self, fs_servicer: FsBackedServicer):
      assert 'must log in to create predictions' in assert_oneof(fs_servicer.CreatePrediction(token=None, request=some_create_prediction_request()),
        'create_prediction_result', 'error', mvp_pb2.CreatePredictionResponse.Error).catchall


class TestListPredictions:

  async def test_success_listing_own(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(token, some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)
    irrelevant_prediction_id = assert_oneof(fs_servicer.CreatePrediction(new_user_token(fs_servicer, 'otherrando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)

    assert set(assert_oneof(fs_servicer.ListPredictions(token=token, request=mvp_pb2.ListPredictionsRequest(creator=token.owner)),
      'list_predictions_result', 'ok', mvp_pb2.PredictionsById).predictions.keys()) == {prediction_id}

  async def test_success_listing_friend(self, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    alice_prediction_id = assert_oneof(fs_servicer.CreatePrediction(alice_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int)
    irrelevant_prediction_id = assert_oneof(fs_servicer.CreatePrediction(bob_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int)
    assert set(assert_oneof(fs_servicer.ListPredictions(token=bob_token, request=mvp_pb2.ListPredictionsRequest(creator=alice_token.owner)),
      'list_predictions_result', 'ok', mvp_pb2.PredictionsById).predictions.keys()) == {alice_prediction_id}

  async def test_error_listing_untruster(self, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    assert_oneof(fs_servicer.SetTrusted(alice_token, mvp_pb2.SetTrustedRequest(who=bob_token.owner, trusted=False)),
      'set_trusted_result', 'ok', object)
    alice_prediction_id = assert_oneof(fs_servicer.CreatePrediction(alice_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int)
    for token in [bob_token, new_user_token(fs_servicer, 'rando')]:
      assert "creator doesn't trust you" in assert_oneof(fs_servicer.ListPredictions(token=token, request=mvp_pb2.ListPredictionsRequest(creator=alice_token.owner)),
        'list_predictions_result', 'error', mvp_pb2.ListPredictionsResponse.Error).catchall



class TestStake:

  async def test_error_if_resolved(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int)
    assert_oneof(fs_servicer.Resolve(alice_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView)

    with assert_unchanged(fs_storage):
      assert 'prediction has already resolved' in assert_oneof(fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)),
        'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_happy_path(self, fs_servicer: FsBackedServicer, clock: MockClock):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(
        certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
        maximum_stake_cents=100_00,
      ),
    ), 'create_prediction_result', 'new_prediction_id', int)

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

  async def test_prevents_overpromising(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(
        certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
        maximum_stake_cents=100_00,
      ),
    ), 'create_prediction_result', 'new_prediction_id', int)

    assert_oneof(fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=25_00,
    )), 'stake_result', 'ok', mvp_pb2.UserPredictionView)
    with assert_unchanged(fs_storage):
      assert 'bet would exceed creator tolerance' in assert_oneof(fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=1,
      )), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

    assert_oneof(fs_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=900_00,
    )), 'stake_result', 'ok', mvp_pb2.UserPredictionView)
    with assert_unchanged(fs_storage):
      assert 'bet would exceed creator tolerance' in assert_oneof(fs_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=False,
        bettor_stake_cents=9,
      )), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(new_user_token(fs_servicer, 'rando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)
    with assert_unchanged(fs_storage):
      assert 'must log in to bet' in assert_oneof(fs_servicer.Stake(None, mvp_pb2.StakeRequest(prediction_id=prediction_id)),
        'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_error_if_no_mutual_trust(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    creator_token = new_user_token(fs_servicer, 'creator')
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(creator_token, some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int)

    stake_req = mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=10,
    )

    truster_token = new_user_token(fs_servicer, 'truster')
    assert fs_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=creator_token.owner, trusted=True)).HasField('ok')
    with assert_unchanged(fs_storage):
      assert "creator doesn't trust you" in assert_oneof(fs_servicer.Stake(truster_token, stake_req), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

    trustee_token = new_user_token(fs_servicer, 'trustee')
    fs_servicer.SetTrusted(creator_token, mvp_pb2.SetTrustedRequest(who=trustee_token.owner, trusted=True))
    with assert_unchanged(fs_storage):
      assert "you don't trust the creator" in assert_oneof(fs_servicer.Stake(trustee_token, stake_req), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

    rando_token = new_user_token(fs_servicer, 'rando')
    with assert_unchanged(fs_storage):
      assert "creator doesn't trust you" in assert_oneof(fs_servicer.Stake(rando_token, stake_req), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_smoke_logged_in(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    resp = fs_servicer.Stake(token=token, request=mvp_pb2.StakeRequest())


class TestResolve:

  async def test_happy_path(self, fs_servicer: FsBackedServicer, clock: MockClock):
    rando_token = new_user_token(fs_servicer, 'rando')
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(
      token=rando_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int)

    t0 = clock.now()
    planned_events = [
      mvp_pb2.ResolutionEvent(unixtime=t0+0, resolution=mvp_pb2.RESOLUTION_YES),
      mvp_pb2.ResolutionEvent(unixtime=t0+1, resolution=mvp_pb2.RESOLUTION_NONE_YET),
      mvp_pb2.ResolutionEvent(unixtime=t0+2, resolution=mvp_pb2.RESOLUTION_NO),
    ]

    assert list(assert_oneof(fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=planned_events[0].resolution)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView).resolutions) == planned_events[:1]
    assert list(assert_oneof(fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).resolutions) == planned_events[:1]

    clock.tick()
    t1 = clock.now()
    assert list(assert_oneof(fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=planned_events[1].resolution)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView).resolutions) == planned_events[:2]
    assert list(assert_oneof(fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).resolutions) == planned_events[:2]

    clock.tick()
    t2 = clock.now()
    assert list(assert_oneof(fs_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=planned_events[2].resolution)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView).resolutions) == planned_events[:3]
    assert list(assert_oneof(fs_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).resolutions) == planned_events


  async def test_ensures_creator(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    prediction_id = assert_oneof(fs_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int)

    for token in [bob_token, new_user_token(fs_servicer, 'rando')]:
      with assert_unchanged(fs_storage):
        assert 'not the creator' in assert_oneof(fs_servicer.Resolve(token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_NO)),
          'resolve_result', 'error', mvp_pb2.ResolveResponse.Error).catchall


class TestSetTrusted:

  async def test_smoke_logged_out(self, fs_servicer: FsBackedServicer):
    resp = fs_servicer.SetTrusted(token=None, request=mvp_pb2.SetTrustedRequest())

  async def test_smoke_logged_in(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    resp = fs_servicer.SetTrusted(token=token, request=mvp_pb2.SetTrustedRequest())


class TestGetUser:

  async def test_get_self(self, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    resp = assert_oneof(fs_servicer.GetUser(token, mvp_pb2.GetUserRequest(who=token.owner)),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(display_name='rando', is_self=True, is_trusted=True, trusts_you=True)

  async def test_get_other(self, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)

    resp = assert_oneof(fs_servicer.GetUser(alice_token, mvp_pb2.GetUserRequest(who=bob_token.owner)),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(display_name='Bob', is_self=False, is_trusted=True, trusts_you=True)

    truster_token = new_user_token(fs_servicer, 'truster')
    fs_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=alice_token.owner, trusted=True))
    resp = assert_oneof(fs_servicer.GetUser(alice_token, mvp_pb2.GetUserRequest(who=truster_token.owner)),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(display_name='truster', is_self=False, is_trusted=False, trusts_you=True)

  async def test_logged_out(self, fs_servicer: FsBackedServicer):
    new_user_token(fs_servicer, 'rando')
    resp = assert_oneof(fs_servicer.GetUser(None, mvp_pb2.GetUserRequest(who=mvp_pb2.UserId(username='rando'))),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(display_name='rando', is_self=False, is_trusted=False, trusts_you=False)


class TestChangePassword:

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    new_user_token(fs_servicer, 'rando')
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.ChangePassword(None, mvp_pb2.ChangePasswordRequest(old_password='rando password', new_password='new rando password')),
        'change_password_result', 'error', mvp_pb2.ChangePasswordResponse.Error).catchall

  async def test_happy_path(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert_oneof(fs_servicer.ChangePassword(token, mvp_pb2.ChangePasswordRequest(old_password='rando password', new_password='new rando password')),
      'change_password_result', 'ok', object)

  async def test_wrong_old_password(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    with assert_unchanged(fs_storage):
      assert 'wrong old password' in assert_oneof(fs_servicer.ChangePassword(token, mvp_pb2.ChangePasswordRequest(old_password='WRONG', new_password='new rando password')),
        'change_password_result', 'error', mvp_pb2.ChangePasswordResponse.Error).catchall


class TestSetEmail:

  async def test_happy_path(self, fs_storage: FsStorage, emailer: Emailer, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert assert_oneof(fs_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'nobody@example.com'
    emailer.send_email_verification.assert_called_once_with(to='nobody@example.com', code=ANY)  # type: ignore
    assert fs_storage.get().username_users['rando'].info.email.code_sent.email == 'nobody@example.com'

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.SetEmail(token=None, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')), 'set_email_result', 'error', mvp_pb2.SetEmailResponse.Error).catchall

  async def test_email_validation(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    for good_email_address in ['a@b', 'b@c.com', 'a.b-c_d+tag@example.com']:
      assert assert_oneof(fs_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email=good_email_address)),
        'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == good_email_address
    for bad_email_address in ['bad email', 'bad@example.com  ', 'good@example.com, evil@example.com']:
      with assert_unchanged(fs_storage):
        assert 'bad email' in assert_oneof(fs_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email=bad_email_address)), 'set_email_result', 'error', mvp_pb2.SetEmailResponse.Error).catchall


class TestVerifyEmail:

  async def test_happy_path(self, fs_storage: FsStorage, emailer: Emailer, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert_oneof(fs_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')), 'set_email_result', 'ok', object)
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert assert_oneof(fs_servicer.VerifyEmail(token=token, request=mvp_pb2.VerifyEmailRequest(code=code)),
      'verify_email_result', 'ok', mvp_pb2.EmailFlowState).verified == 'nobody@example.com'

  async def test_error_if_wrong_code(self, fs_storage: FsStorage, emailer: Emailer, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert_oneof(fs_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')), 'set_email_result', 'ok', object)
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert 'bad code' in assert_oneof(fs_servicer.VerifyEmail(token=token, request=mvp_pb2.VerifyEmailRequest(code='not ' + code)),
      'verify_email_result', 'error', mvp_pb2.VerifyEmailResponse.Error).catchall

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.VerifyEmail(token=None, request=mvp_pb2.VerifyEmailRequest(code='foo')), 'verify_email_result', 'error', mvp_pb2.VerifyEmailResponse.Error).catchall


class TestGetSettings:

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.GetSettings(token=None, request=mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'error', mvp_pb2.GetSettingsResponse.Error).catchall

  async def test_happy_path(self, fs_storage: FsStorage, emailer: Emailer, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    geninfo = assert_oneof(fs_servicer.GetSettings(token=alice_token, request=mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok_username', mvp_pb2.UsernameInfo).info
    assert list(geninfo.trusted_users) == [bob_token.owner]


class TestUpdateSettings:

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.UpdateSettings(token=None, request=mvp_pb2.UpdateSettingsRequest()), 'update_settings_result', 'error', mvp_pb2.UpdateSettingsResponse.Error).catchall

  async def test_happy_path(self, fs_storage: FsStorage, emailer: Emailer, fs_servicer: FsBackedServicer):
    alice_token, bob_token = alice_bob_tokens(fs_servicer)
    assert assert_oneof(fs_servicer.UpdateSettings(token=alice_token, request=mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=True))),
      'update_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve
    assert fs_storage.get().username_users['Alice'].info.email_reminders_to_resolve


class TestCreateInvitation:

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.CreateInvitation(token=None, request=mvp_pb2.CreateInvitationRequest()), 'create_invitation_result', 'error', mvp_pb2.CreateInvitationResponse.Error).catchall

  async def test_success_if_logged_in(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    token = new_user_token(fs_servicer, 'rando')
    assert_oneof(fs_servicer.CreateInvitation(token=token, request=mvp_pb2.CreateInvitationRequest()), 'create_invitation_result', 'ok', object)


class TestCheckInvitation:

  async def test_no_such_invitation(self, fs_servicer: FsBackedServicer):
    new_user_token(fs_servicer, 'rando')
    assert not assert_oneof(fs_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=mvp_pb2.InvitationId(inviter=mvp_pb2.UserId(username='rando'), nonce='asdf'))),
      'check_invitation_result', 'is_open', bool)

  async def test_open(self, fs_servicer: FsBackedServicer):
    invitation_id = assert_oneof(fs_servicer.CreateInvitation(token=new_user_token(fs_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    assert assert_oneof(fs_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)

  async def test_closed(self, fs_servicer: FsBackedServicer):
    invitation_id = assert_oneof(fs_servicer.CreateInvitation(token=new_user_token(fs_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    accepter_token = new_user_token(fs_servicer, 'accepter')
    assert_oneof(fs_servicer.AcceptInvitation(accepter_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', object)
    assert not assert_oneof(fs_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)


class TestAcceptInvitation:

  async def test_error_if_logged_out(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    invitation_id = assert_oneof(fs_servicer.CreateInvitation(token=new_user_token(fs_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    with assert_unchanged(fs_storage):
      assert 'must log in' in assert_oneof(fs_servicer.AcceptInvitation(token=None, request=mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)), 'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall

  async def test_happy_path(self, fs_storage: FsStorage, fs_servicer: FsBackedServicer):
    invitation_id = assert_oneof(fs_servicer.CreateInvitation(token=new_user_token(fs_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    accepter_token = new_user_token(fs_servicer, 'accepter')
    assert_oneof(fs_servicer.AcceptInvitation(accepter_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', object)
    assert not assert_oneof(fs_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)

  async def test_no_such_invitation(self, fs_servicer: FsBackedServicer):
    new_user_token(fs_servicer, 'rando')
    accepter_token = new_user_token(fs_servicer, 'accepter')
    assert 'invitation is non-existent or already used' in assert_oneof(fs_servicer.AcceptInvitation(token=accepter_token, request=mvp_pb2.AcceptInvitationRequest(invitation_id=mvp_pb2.InvitationId(inviter=mvp_pb2.UserId(username='rando'), nonce='asdf'))),
      'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall

  async def test_closed_invitation(self, fs_servicer: FsBackedServicer):
    invitation_id = assert_oneof(fs_servicer.CreateInvitation(token=new_user_token(fs_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id

    accepter_token = new_user_token(fs_servicer, 'accepter')
    assert_oneof(fs_servicer.AcceptInvitation(accepter_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', object)

    assert 'invitation is non-existent or already used' in assert_oneof(fs_servicer.AcceptInvitation(token=accepter_token, request=mvp_pb2.AcceptInvitationRequest(invitation_id=mvp_pb2.InvitationId(inviter=mvp_pb2.UserId(username='rando'), nonce='asdf'))),
      'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall
