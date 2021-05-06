import contextlib
import copy
from pathlib import Path
import random
from typing import Tuple
from unittest.mock import ANY

import pytest

from .protobuf import mvp_pb2
from .core import Servicer
from .emailer import Emailer
from .test_utils import *


class TestCUJs:
  async def test_cuj__register__create__invite__accept__stake__resolve(self, any_servicer: Servicer, clock: MockClock):
    creator_token = assert_oneof(
      any_servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='creator', password='secret')),
      'register_username_result', 'ok', mvp_pb2.AuthSuccess).token

    prediction_id = PredictionId(assert_oneof(
      any_servicer.CreatePrediction(creator_token, mvp_pb2.CreatePredictionRequest(
        prediction='a thing will happen',
        resolves_at_unixtime=clock.now() + 86400,
        certainty=mvp_pb2.CertaintyRange(low=0.40, high=0.60),
        maximum_stake_cents=100_00,
        open_seconds=3600,
      )),
      'create_prediction_result', 'new_prediction_id', int))

    invitation_id = assert_oneof(
      any_servicer.CreateInvitation(creator_token, mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id

    assert assert_oneof(
      any_servicer.CheckInvitation(None, mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)

    friend_token = assert_oneof(
      any_servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='friend', password='secret')),
      'register_username_result', 'ok', mvp_pb2.AuthSuccess).token

    friend_settings = assert_oneof(
      any_servicer.AcceptInvitation(friend_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', mvp_pb2.GenericUserInfo)
    assert friend_settings.relationships[creator_token.owner].trusted

    prediction = assert_oneof(
      any_servicer.Stake(friend_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=6_00)),
      'stake_result', 'ok', mvp_pb2.UserPredictionView)
    assert list(prediction.your_trades) == [mvp_pb2.Trade(
      bettor=friend_token.owner,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=6_00,
      creator_stake_cents=4_00,
      transacted_unixtime=clock.now(),
    )]

    prediction = assert_oneof(
      any_servicer.Resolve(creator_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView)
    assert list(prediction.resolutions) ==[mvp_pb2.ResolutionEvent(unixtime=clock.now(), resolution=mvp_pb2.RESOLUTION_YES)]


  async def test_cuj___set_email__verify_email__update_settings(self, any_servicer: Servicer, emailer: Emailer):
    token = assert_oneof(
      any_servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='creator', password='secret')),
      'register_username_result', 'ok', mvp_pb2.AuthSuccess).token

    assert assert_oneof(any_servicer.SetEmail(token, mvp_pb2.SetEmailRequest(email='nobody@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'nobody@example.com'

    emailer.send_email_verification.assert_called_once()  # type: ignore
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore

    assert assert_oneof(any_servicer.VerifyEmail(token, mvp_pb2.VerifyEmailRequest(code=code)),
      'verify_email_result', 'ok', mvp_pb2.EmailFlowState).verified == 'nobody@example.com'

    assert not assert_oneof(any_servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve

    assert assert_oneof(any_servicer.UpdateSettings(token, mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=True))),
      'update_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve

    assert assert_oneof(any_servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve



class TestWhoami:

  async def test_smoke_logged_out(self, any_servicer: Servicer):
    assert not any_servicer.Whoami(token=None, request=mvp_pb2.WhoamiRequest()).HasField('auth')

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert any_servicer.Whoami(token=token, request=mvp_pb2.WhoamiRequest()).auth == token


class TestSignOut:

  async def test_smoke_logged_out(self, any_servicer: Servicer):
    any_servicer.SignOut(token=None, request=mvp_pb2.SignOutRequest())

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    any_servicer.SignOut(token=token, request=mvp_pb2.SignOutRequest())


class TestRegisterUsername:

  async def test_success(self, any_servicer: Servicer):
    assert assert_oneof(any_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='alice', password='secret')),
      'register_username_result', 'ok', mvp_pb2.AuthSuccess).token.owner == 'alice'

  async def test_error_when_already_exists(self, any_servicer: Servicer):
    orig_token = new_user_token(any_servicer, 'rando')

    for password in ['rando password', 'some other password']:
      with assert_user_unchanged(any_servicer, orig_token, 'rando password'):
        assert 'username taken' in assert_oneof(any_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='rando', password=password)),
          'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error).catchall

  async def test_error_if_already_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    with assert_user_unchanged(any_servicer, token, 'rando password'):
      assert 'first, log out' in str(assert_oneof(any_servicer.RegisterUsername(token=token, request=mvp_pb2.RegisterUsernameRequest(username='alice', password='secret')),
        'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error))

  async def test_error_if_invalid_username(self, any_servicer: Servicer):
    assert 'username must be alphanumeric' in assert_oneof(any_servicer.RegisterUsername(token=None, request=mvp_pb2.RegisterUsernameRequest(username='foo bar!baz\xfequux', password='rando password')),
      'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error).catchall


class TestLogInUsername:

  async def test_success(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    assert assert_oneof(any_servicer.LogInUsername(token=None, request=mvp_pb2.LogInUsernameRequest(username='rando', password='rando password')),
      'log_in_username_result', 'ok', mvp_pb2.AuthSuccess).token.owner == 'rando'

  async def test_no_such_user(self, any_servicer: Servicer):
    assert 'no such user' in assert_oneof(any_servicer.LogInUsername(token=None, request=mvp_pb2.LogInUsernameRequest(username='alice', password='secret')),
      'log_in_username_result', 'error', mvp_pb2.LogInUsernameResponse.Error).catchall

  async def test_error_if_already_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'first, log out' in str(assert_oneof(any_servicer.LogInUsername(token=token, request=mvp_pb2.LogInUsernameRequest(username='alice', password='secret')),
      'log_in_username_result', 'error', mvp_pb2.LogInUsernameResponse.Error))


class TestCreatePrediction:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in to create predictions' in assert_oneof(any_servicer.CreatePrediction(token=None, request=some_create_prediction_request()),
      'create_prediction_result', 'error', mvp_pb2.CreatePredictionResponse.Error).catchall

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(token=token, request=some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))
    assert_oneof(any_servicer.GetPrediction(token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)

  async def test_returns_distinct_ids(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    ids = {any_servicer.CreatePrediction(token, some_create_prediction_request()).new_prediction_id for _ in range(30)}
    assert len(ids) == 30
    for prediction_id in ids:
      assert_oneof(any_servicer.GetPrediction(token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
        'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)


class TestGetPrediction:

  async def test_has_all_fields(self, any_servicer: Servicer, clock: MockClock):
    req = some_create_prediction_request(
      prediction='a thing will happen',
      special_rules='some special rules',
      maximum_stake_cents=100_00,
      certainty=mvp_pb2.CertaintyRange(low=0.50, high=1.00),
    )
    alice_token, bob_token = alice_bob_tokens(any_servicer)

    create_time = clock.now()
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=alice_token,
      request=copy.deepcopy(req),
    ), 'create_prediction_result', 'new_prediction_id', int))

    clock.tick()
    stake_time = clock.now()
    assert_oneof(any_servicer.Stake(bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=1_00)),
      'stake_result', 'ok', mvp_pb2.UserPredictionView)

    clock.tick()
    resolve_time = clock.now()
    assert_oneof(any_servicer.Resolve(alice_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView)

    resp = any_servicer.GetPrediction(bob_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
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
      creator=mvp_pb2.UserUserView(username='Alice', is_trusted=True, trusts_you=True),
      resolutions=[mvp_pb2.ResolutionEvent(unixtime=resolve_time, resolution=mvp_pb2.RESOLUTION_YES)],
      your_trades=[mvp_pb2.Trade(bettor=bob_token.owner, bettor_is_a_skeptic=True, bettor_stake_cents=1_00, creator_stake_cents=1_00, transacted_unixtime=stake_time)],
    )


  async def test_success_if_logged_out(self, any_servicer: Servicer):
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(new_user_token(any_servicer, 'rando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))
    assert_oneof(any_servicer.GetPrediction(token=None, request=mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)

  async def test_success_if_logged_in(self, any_servicer: Servicer):
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(new_user_token(any_servicer, 'rando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))
    assert_oneof(any_servicer.GetPrediction(token=new_user_token(any_servicer, 'otherrando'), request=mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)

  async def test_error_if_no_such_prediction(self, any_servicer: Servicer):
    assert 'no such prediction' in assert_oneof(any_servicer.GetPrediction(token=new_user_token(any_servicer, 'otherrando'), request=mvp_pb2.GetPredictionRequest(prediction_id=12345)),
      'get_prediction_result', 'error', mvp_pb2.GetPredictionResponse.Error).catchall

class TestListMyStakes:

  async def test_success_if_logged_in(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    alice_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(alice_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int))
    bob_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(bob_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int))
    irrelevant_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(bob_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int))

    assert_oneof(any_servicer.Stake(alice_token, mvp_pb2.StakeRequest(prediction_id=bob_prediction_id, bettor_stake_cents=1_00)),
      'stake_result', 'ok', mvp_pb2.UserPredictionView)

    assert set(assert_oneof(any_servicer.ListMyStakes(token=alice_token, request=mvp_pb2.ListMyStakesRequest()),
      'list_my_stakes_result', 'ok', mvp_pb2.PredictionsById).predictions.keys()) == {alice_prediction_id, bob_prediction_id}

  async def test_error_if_logged_out(self, any_servicer: Servicer):
      assert 'must log in to create predictions' in assert_oneof(any_servicer.CreatePrediction(token=None, request=some_create_prediction_request()),
        'create_prediction_result', 'error', mvp_pb2.CreatePredictionResponse.Error).catchall


class TestListPredictions:

  async def test_success_listing_own(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(token, some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))
    irrelevant_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(new_user_token(any_servicer, 'otherrando'), some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))

    assert set(assert_oneof(any_servicer.ListPredictions(token=token, request=mvp_pb2.ListPredictionsRequest(creator=token.owner)),
      'list_predictions_result', 'ok', mvp_pb2.PredictionsById).predictions.keys()) == {prediction_id}

  async def test_success_listing_friend(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    alice_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(alice_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int))
    irrelevant_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(bob_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int))
    assert set(assert_oneof(any_servicer.ListPredictions(token=bob_token, request=mvp_pb2.ListPredictionsRequest(creator=alice_token.owner)),
      'list_predictions_result', 'ok', mvp_pb2.PredictionsById).predictions.keys()) == {alice_prediction_id}

  async def test_error_listing_untruster(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    assert_oneof(any_servicer.SetTrusted(alice_token, mvp_pb2.SetTrustedRequest(who=bob_token.owner, trusted=False)),
      'set_trusted_result', 'ok', object)
    alice_prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(alice_token, some_create_prediction_request(maximum_stake_cents=100_00)),
      'create_prediction_result', 'new_prediction_id', int))
    for token in [bob_token, new_user_token(any_servicer, 'rando')]:
      assert "creator doesn't trust you" in assert_oneof(any_servicer.ListPredictions(token=token, request=mvp_pb2.ListPredictionsRequest(creator=alice_token.owner)),
        'list_predictions_result', 'error', mvp_pb2.ListPredictionsResponse.Error).catchall



class TestStake:

  async def test_error_if_resolved(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int))
    assert_oneof(any_servicer.Resolve(alice_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView)

    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'prediction has already resolved' in assert_oneof(any_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)),
        'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_error_if_closed(self, clock: MockClock, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(open_seconds=86400, resolves_at_unixtime=int(clock.now() + 2*86400)),
    ), 'create_prediction_result', 'new_prediction_id', int))

    clock.tick(86401)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'prediction is no longer open for betting' in assert_oneof(any_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)),
        'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_happy_path(self, any_servicer: Servicer, clock: MockClock):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(
        certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
        maximum_stake_cents=100_00,
      ),
    ), 'create_prediction_result', 'new_prediction_id', int))

    any_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=20_00,
    ))
    any_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=90_00,
    ))
    assert list(any_servicer.GetPrediction(alice_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)).prediction.your_trades) == [
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

  async def test_prevents_overpromising(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(
        certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
        maximum_stake_cents=100_00,
      ),
    ), 'create_prediction_result', 'new_prediction_id', int))

    assert_oneof(any_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=25_00,
    )), 'stake_result', 'ok', mvp_pb2.UserPredictionView)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'bet would exceed creator tolerance' in assert_oneof(any_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=1,
      )), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

    assert_oneof(any_servicer.Stake(token=bob_token, request=mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=900_00,
    )), 'stake_result', 'ok', mvp_pb2.UserPredictionView)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'bet would exceed creator tolerance' in assert_oneof(any_servicer.Stake(bob_token, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=False,
        bettor_stake_cents=9,
      )), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(token, some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=token):
      assert 'must log in to bet' in assert_oneof(any_servicer.Stake(None, mvp_pb2.StakeRequest(prediction_id=prediction_id)),
        'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_error_if_no_mutual_trust(self, any_servicer: Servicer):
    creator_token = new_user_token(any_servicer, 'creator')
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(creator_token, some_create_prediction_request()),
      'create_prediction_result', 'new_prediction_id', int))

    stake_req = mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=10,
    )

    truster_token = new_user_token(any_servicer, 'truster')
    assert any_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=creator_token.owner, trusted=True)).HasField('ok')
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=creator_token):
      assert "creator doesn't trust you" in assert_oneof(any_servicer.Stake(truster_token, stake_req), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

    trustee_token = new_user_token(any_servicer, 'trustee')
    any_servicer.SetTrusted(creator_token, mvp_pb2.SetTrustedRequest(who=trustee_token.owner, trusted=True))
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=creator_token):
      assert "you don't trust the creator" in assert_oneof(any_servicer.Stake(trustee_token, stake_req), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

    rando_token = new_user_token(any_servicer, 'rando')
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=creator_token):
      assert "creator doesn't trust you" in assert_oneof(any_servicer.Stake(rando_token, stake_req), 'stake_result', 'error', mvp_pb2.StakeResponse.Error).catchall

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    resp = any_servicer.Stake(token=token, request=mvp_pb2.StakeRequest())


class TestResolve:

  async def test_happy_path(self, any_servicer: Servicer, clock: MockClock):
    rando_token = new_user_token(any_servicer, 'rando')
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=rando_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int))

    t0 = clock.now()
    planned_events = [
      mvp_pb2.ResolutionEvent(unixtime=t0+0, resolution=mvp_pb2.RESOLUTION_YES),
      mvp_pb2.ResolutionEvent(unixtime=t0+1, resolution=mvp_pb2.RESOLUTION_NONE_YET),
      mvp_pb2.ResolutionEvent(unixtime=t0+2, resolution=mvp_pb2.RESOLUTION_NO),
    ]

    assert list(assert_oneof(any_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=planned_events[0].resolution)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView).resolutions) == planned_events[:1]
    assert list(assert_oneof(any_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).resolutions) == planned_events[:1]

    clock.tick()
    t1 = clock.now()
    assert list(assert_oneof(any_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=planned_events[1].resolution)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView).resolutions) == planned_events[:2]
    assert list(assert_oneof(any_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).resolutions) == planned_events[:2]

    clock.tick()
    t2 = clock.now()
    assert list(assert_oneof(any_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=planned_events[2].resolution)),
      'resolve_result', 'ok', mvp_pb2.UserPredictionView).resolutions) == planned_events[:3]
    assert list(assert_oneof(any_servicer.GetPrediction(rando_token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)),
      'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView).resolutions) == planned_events

  async def test_validation(self, any_servicer: Servicer):
    rando_token = new_user_token(any_servicer, 'rando')
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=rando_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int))

    assert 'unreasonably long notes' in str(assert_oneof(any_servicer.Resolve(rando_token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES, notes=99999*'foo')),
      'resolve_result', 'error', mvp_pb2.ResolveResponse.Error))


  async def test_ensures_creator(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = PredictionId(assert_oneof(any_servicer.CreatePrediction(
      token=alice_token,
      request=some_create_prediction_request(),
    ), 'create_prediction_result', 'new_prediction_id', int))

    for token in [bob_token, new_user_token(any_servicer, 'rando')]:
      with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
        assert 'not the creator' in assert_oneof(any_servicer.Resolve(token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_NO)),
          'resolve_result', 'error', mvp_pb2.ResolveResponse.Error).catchall


class TestSetTrusted:

  async def test_error_when_logged_out(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    assert 'must log in to trust folks' in assert_oneof(any_servicer.SetTrusted(token=None, request=mvp_pb2.SetTrustedRequest(who='rando', trusted=True)),
      'set_trusted_result', 'error', mvp_pb2.SetTrustedResponse.Error).catchall

  async def test_error_if_nonexistent(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'no such user' in assert_oneof(any_servicer.SetTrusted(token=token, request=mvp_pb2.SetTrustedRequest(who='nonexistent', trusted=True)),
      'set_trusted_result', 'error', mvp_pb2.SetTrustedResponse.Error).catchall

  async def test_error_if_self(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'cannot set trust for self' in assert_oneof(any_servicer.SetTrusted(token=token, request=mvp_pb2.SetTrustedRequest(who='rando', trusted=True)),
      'set_trusted_result', 'error', mvp_pb2.SetTrustedResponse.Error).catchall

  async def test_happy_path(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    new_user_token(any_servicer, 'other')

    alice_view_of_bob = assert_oneof(any_servicer.GetUser(token=alice_token, request=mvp_pb2.GetUserRequest(who='Bob')),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert alice_view_of_bob.is_trusted

    assert_oneof(any_servicer.SetTrusted(token=alice_token, request=mvp_pb2.SetTrustedRequest(who='Bob', trusted=False)),
      'set_trusted_result', 'ok', mvp_pb2.GenericUserInfo)

    alice_view_of_bob = assert_oneof(any_servicer.GetUser(token=alice_token, request=mvp_pb2.GetUserRequest(who='Bob')),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert not alice_view_of_bob.is_trusted



class TestGetUser:

  async def test_get_self(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    resp = assert_oneof(any_servicer.GetUser(token, mvp_pb2.GetUserRequest(who=token.owner)),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(username='rando', is_trusted=True, trusts_you=True)

  async def test_get_other(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)

    resp = assert_oneof(any_servicer.GetUser(alice_token, mvp_pb2.GetUserRequest(who=bob_token.owner)),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(username='Bob', is_trusted=True, trusts_you=True)

    truster_token = new_user_token(any_servicer, 'truster')
    any_servicer.SetTrusted(truster_token, mvp_pb2.SetTrustedRequest(who=alice_token.owner, trusted=True))
    resp = assert_oneof(any_servicer.GetUser(alice_token, mvp_pb2.GetUserRequest(who=truster_token.owner)),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(username='truster', is_trusted=False, trusts_you=True)

  async def test_logged_out(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    resp = assert_oneof(any_servicer.GetUser(None, mvp_pb2.GetUserRequest(who='rando')),
      'get_user_result', 'ok', mvp_pb2.UserUserView)
    assert resp == mvp_pb2.UserUserView(username='rando', is_trusted=False, trusts_you=False)


class TestChangePassword:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    real_token = new_user_token(any_servicer, 'rando')
    with assert_user_unchanged(any_servicer, real_token, 'rando password'):
      assert 'must log in' in assert_oneof(any_servicer.ChangePassword(None, mvp_pb2.ChangePasswordRequest(old_password='rando password', new_password='new rando password')),
        'change_password_result', 'error', mvp_pb2.ChangePasswordResponse.Error).catchall

  async def test_happy_path(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert_oneof(any_servicer.ChangePassword(token, mvp_pb2.ChangePasswordRequest(old_password='rando password', new_password='new rando password')),
      'change_password_result', 'ok', object)

  async def test_wrong_old_password(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    with assert_user_unchanged(any_servicer, token, 'rando password'):
      assert 'wrong old password' in assert_oneof(any_servicer.ChangePassword(token, mvp_pb2.ChangePasswordRequest(old_password='WRONG', new_password='new rando password')),
        'change_password_result', 'error', mvp_pb2.ChangePasswordResponse.Error).catchall


class TestSetEmail:

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'nobody@example.com'
    emailer.send_email_verification.assert_called_once_with(to='nobody@example.com', code=ANY)  # type: ignore
    assert assert_oneof(any_servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo).email.code_sent.email == 'nobody@example.com'

  async def test_works_in_all_stages(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')

    # starting from scratch
    assert assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='a@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'a@example.com'

    # starting from CodeSent
    assert assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='b@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'b@example.com'
    code: str = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert assert_oneof(any_servicer.VerifyEmail(token=token, request=mvp_pb2.VerifyEmailRequest(code=code)),
      'verify_email_result', 'ok', mvp_pb2.EmailFlowState).verified == 'b@example.com'

    # starting from Verified
    assert assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='c@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == 'c@example.com'

  async def test_clear(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')),
      'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email

    emailer.send_email_verification.reset_mock()  # type: ignore
    assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='')).ok,
      'email_flow_state_kind', 'unstarted', object)
    emailer.send_email_verification.assert_not_called()  # type: ignore

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in assert_oneof(any_servicer.SetEmail(token=None, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')), 'set_email_result', 'error', mvp_pb2.SetEmailResponse.Error).catchall

  async def test_email_validation(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    for good_email_address in ['a@b', 'b@c.com', 'a.b-c_d+tag@example.com']:
      assert assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email=good_email_address)),
        'set_email_result', 'ok', mvp_pb2.EmailFlowState).code_sent.email == good_email_address
    for bad_email_address in ['bad email', 'bad@example.com  ', 'good@example.com, evil@example.com']:
      with assert_user_unchanged(any_servicer, token, 'rando password'):
        assert 'invalid-looking email' in assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email=bad_email_address)), 'set_email_result', 'error', mvp_pb2.SetEmailResponse.Error).catchall


class TestVerifyEmail:

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')), 'set_email_result', 'ok', object)
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert assert_oneof(any_servicer.VerifyEmail(token=token, request=mvp_pb2.VerifyEmailRequest(code=code)),
      'verify_email_result', 'ok', mvp_pb2.EmailFlowState).verified == 'nobody@example.com'

  async def test_error_if_wrong_code(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert_oneof(any_servicer.SetEmail(token=token, request=mvp_pb2.SetEmailRequest(email='nobody@example.com')), 'set_email_result', 'ok', object)
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert 'bad code' in assert_oneof(any_servicer.VerifyEmail(token=token, request=mvp_pb2.VerifyEmailRequest(code='not ' + code)),
      'verify_email_result', 'error', mvp_pb2.VerifyEmailResponse.Error).catchall

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in assert_oneof(any_servicer.VerifyEmail(token=None, request=mvp_pb2.VerifyEmailRequest(code='foo')), 'verify_email_result', 'error', mvp_pb2.VerifyEmailResponse.Error).catchall


class TestGetSettings:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in assert_oneof(any_servicer.GetSettings(token=None, request=mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'error', mvp_pb2.GetSettingsResponse.Error).catchall

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    geninfo = assert_oneof(any_servicer.GetSettings(token=alice_token, request=mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
    assert dict(geninfo.relationships) == {'Bob': mvp_pb2.Relationship(trusted=True)}


class TestUpdateSettings:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in assert_oneof(any_servicer.UpdateSettings(token=None, request=mvp_pb2.UpdateSettingsRequest()), 'update_settings_result', 'error', mvp_pb2.UpdateSettingsResponse.Error).catchall

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    assert assert_oneof(any_servicer.UpdateSettings(token=alice_token, request=mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=True))),
      'update_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve
    assert assert_oneof(any_servicer.GetSettings(alice_token, mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo).email_reminders_to_resolve


class TestCreateInvitation:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in assert_oneof(any_servicer.CreateInvitation(token=None, request=mvp_pb2.CreateInvitationRequest()), 'create_invitation_result', 'error', mvp_pb2.CreateInvitationResponse.Error).catchall

  async def test_success_if_logged_in(self, any_servicer: Servicer, clock: MockClock):
    token = new_user_token(any_servicer, 'rando')
    invitation_id = assert_oneof(any_servicer.CreateInvitation(token=token, request=mvp_pb2.CreateInvitationRequest()), 'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    assert assert_oneof(any_servicer.GetSettings(token=token, request=mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo).invitations[invitation_id.nonce] == mvp_pb2.Invitation(
        created_unixtime=clock.now(),
      )


class TestCheckInvitation:

  async def test_no_such_invitation(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    assert not assert_oneof(any_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=mvp_pb2.InvitationId(inviter='rando', nonce='asdf'))),
      'check_invitation_result', 'is_open', bool)

  async def test_open(self, any_servicer: Servicer):
    invitation_id = assert_oneof(any_servicer.CreateInvitation(token=new_user_token(any_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    assert assert_oneof(any_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)

  async def test_closed(self, any_servicer: Servicer):
    invitation_id = assert_oneof(any_servicer.CreateInvitation(token=new_user_token(any_servicer, 'inviter'), request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    accepter_token = new_user_token(any_servicer, 'accepter')
    assert_oneof(any_servicer.AcceptInvitation(accepter_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', object)
    assert not assert_oneof(any_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)


class TestAcceptInvitation:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'inviter')
    invitation_id = assert_oneof(any_servicer.CreateInvitation(token=token, request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    assert 'must log in' in assert_oneof(any_servicer.AcceptInvitation(token=None, request=mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)), 'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall
    assert assert_oneof(any_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)

  async def test_error_if_invalid(self, any_servicer: Servicer):
    accepter_token = new_user_token(any_servicer, 'accepter')
    assert 'no invitation id given' in assert_oneof(any_servicer.AcceptInvitation(token=accepter_token, request=mvp_pb2.AcceptInvitationRequest(invitation_id=None)), 'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall

  async def test_happy_path(self, any_servicer: Servicer, clock: MockClock):
    inviter_token = new_user_token(any_servicer, 'inviter')
    invitation_id = assert_oneof(any_servicer.CreateInvitation(token=inviter_token, request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id
    invited_at = clock.now()

    clock.tick()

    accepter_token = new_user_token(any_servicer, 'accepter')
    assert_oneof(any_servicer.AcceptInvitation(accepter_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', object)
    accepted_at = clock.now()

    assert not assert_oneof(any_servicer.CheckInvitation(token=None, request=mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id)),
      'check_invitation_result', 'is_open', bool)

    assert assert_oneof(any_servicer.GetSettings(token=inviter_token, request=mvp_pb2.GetSettingsRequest()),
      'get_settings_result', 'ok', mvp_pb2.GenericUserInfo).invitations[invitation_id.nonce] == mvp_pb2.Invitation(
        created_unixtime=invited_at,
        accepted_by='accepter',
        accepted_unixtime=accepted_at,
      )

  async def test_no_such_invitation(self, any_servicer: Servicer):
    non_inviter_token = new_user_token(any_servicer, 'rando')
    accepter_token = new_user_token(any_servicer, 'accepter')
    with assert_user_unchanged(any_servicer, non_inviter_token, 'rando password'):
      assert 'invitation is non-existent or already used' in assert_oneof(any_servicer.AcceptInvitation(token=accepter_token, request=mvp_pb2.AcceptInvitationRequest(invitation_id=mvp_pb2.InvitationId(inviter='rando', nonce='asdf'))),
        'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall

  async def test_closed_invitation(self, any_servicer: Servicer):
    inviter_token = new_user_token(any_servicer, 'inviter')
    invitation_id = assert_oneof(any_servicer.CreateInvitation(token=inviter_token, request=mvp_pb2.CreateInvitationRequest()),
      'create_invitation_result', 'ok', mvp_pb2.CreateInvitationResponse.Result).id

    accepter_token = new_user_token(any_servicer, 'accepter')
    assert_oneof(any_servicer.AcceptInvitation(accepter_token, mvp_pb2.AcceptInvitationRequest(invitation_id=invitation_id)),
      'accept_invitation_result', 'ok', object)

    with assert_user_unchanged(any_servicer, inviter_token, 'inviter password'):
      assert 'invitation is non-existent or already used' in assert_oneof(any_servicer.AcceptInvitation(token=accepter_token, request=mvp_pb2.AcceptInvitationRequest(invitation_id=mvp_pb2.InvitationId(inviter='rando', nonce=invitation_id.nonce))),
        'accept_invitation_result', 'error', mvp_pb2.AcceptInvitationResponse.Error).catchall
