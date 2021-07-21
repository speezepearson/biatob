from __future__ import annotations
from typing import Sequence

from unittest.mock import ANY

from .protobuf import mvp_pb2
from .core import Servicer
from .emailer import Emailer
from .test_utils import *

PRED_ID_1 = PredictionId('my_pred_id_1')

ALICE = au('alice')
BOB = au('bob')
CHARLIE = au('charlie')

class TestCUJs:
  async def test_cuj__register__create__invite__accept__stake__resolve(self, any_servicer: Servicer, emailer: Emailer, clock: MockClock):
    RegisterUsernameOk(any_servicer, None, ALICE)
    set_and_verify_email(any_servicer, emailer, ALICE, 'creator@example.com')
    UpdateSettingsOk(any_servicer, ALICE, allow_email_invitations=True)

    RegisterUsernameOk(any_servicer, None, BOB)
    set_and_verify_email(any_servicer, emailer, BOB, 'friend@example.com')

    prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(
        prediction='a thing will happen',
        resolves_at_unixtime=clock.now().timestamp() + 86400,
        certainty=mvp_pb2.CertaintyRange(low=0.40, high=0.60),
        maximum_stake_cents=100_00,
        open_seconds=3600,
      ))

    SendInvitationOk(any_servicer, BOB, ALICE)
    AcceptInvitationOk(any_servicer, None, get_call_kwarg(emailer.send_invitation, 'nonce'))

    assert GetSettingsOk(any_servicer, ALICE).relationships[BOB].trusts_you
    assert GetSettingsOk(any_servicer, ALICE).relationships[BOB].trusted_by_you
    assert GetSettingsOk(any_servicer, BOB).relationships[ALICE].trusts_you
    assert GetSettingsOk(any_servicer, BOB).relationships[ALICE].trusted_by_you

    prediction = StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=6_00))
    assert prediction.trades_by_bettor == {BOB: mvp_pb2.Trade(
      bettor=BOB,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=6_00,
      creator_stake_cents=4_00,
      transacted_unixtime=clock.now().timestamp(),
      updated_unixtime=clock.now().timestamp(),
      state=mvp_pb2.TRADE_STATE_ACTIVE,
    )}

    prediction = ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES)
    assert prediction.resolution == mvp_pb2.ResolutionEvent(unixtime=clock.now().timestamp(), resolution=mvp_pb2.RESOLUTION_YES)


  async def test_cuj___set_email__verify_email__update_settings(self, any_servicer: Servicer, emailer: Emailer):
    RegisterUsernameOk(any_servicer, None, ALICE)

    assert SetEmailOk(any_servicer, ALICE, 'nobody@example.com').code_sent.email == 'nobody@example.com'

    emailer.send_email_verification.assert_called_once()  # type: ignore
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore

    assert VerifyEmailOk(any_servicer, ALICE, code).verified == 'nobody@example.com'

    assert not UpdateSettingsOk(any_servicer, ALICE, email_reminders_to_resolve=False).email_reminders_to_resolve
    assert not GetSettingsOk(any_servicer, ALICE).email_reminders_to_resolve

    assert UpdateSettingsOk(any_servicer, ALICE, email_reminders_to_resolve=True).email_reminders_to_resolve
    assert GetSettingsOk(any_servicer, ALICE).email_reminders_to_resolve



class TestWhoami:

  async def test_returns_none_when_logged_out(self, any_servicer: Servicer):
    assert not any_servicer.Whoami(actor=None, request=mvp_pb2.WhoamiRequest()).username

  async def test_returns_token_when_logged_in(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert any_servicer.Whoami(actor=ALICE, request=mvp_pb2.WhoamiRequest()).username == ALICE


class TestSignOut:

  async def test_smoke_logged_out(self, any_servicer: Servicer):
    any_servicer.SignOut(actor=None, request=mvp_pb2.SignOutRequest())

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    any_servicer.SignOut(actor=ALICE, request=mvp_pb2.SignOutRequest())


class TestRegisterUsername:

  async def test_returns_auth_when_successful(self, any_servicer: Servicer):
    token = RegisterUsernameOk(any_servicer, None, ALICE, 'secret').token
    assert token.owner == ALICE

  async def test_can_log_in_after_registering(self, any_servicer: Servicer):
    assert 'no such user' in str(LogInUsernameErr(any_servicer, None, ALICE, 'secret'))
    RegisterUsernameOk(any_servicer, None, ALICE, 'secret')
    assert LogInUsernameOk(any_servicer, None, ALICE, 'secret').token.owner == ALICE

  async def test_error_when_already_exists(self, any_servicer: Servicer):
    password = 'pw'
    RegisterUsernameOk(any_servicer, None, ALICE, password=password)

    for try_password in [password, 'not '+password]:
      with assert_user_unchanged(any_servicer, ALICE, password):
        assert 'username taken' in str(RegisterUsernameErr(any_servicer, None, ALICE, try_password))

  async def test_error_if_already_logged_in(self, any_servicer: Servicer):
    password = 'pw'
    RegisterUsernameOk(any_servicer, None, ALICE, password=password)
    with assert_user_unchanged(any_servicer, ALICE, password):
      assert 'first, log out' in str(RegisterUsernameErr(any_servicer, ALICE, ALICE, 'secret'))

  async def test_error_if_invalid_username(self, any_servicer: Servicer):
    assert 'username must be alphanumeric' in str(RegisterUsernameErr(any_servicer, None, u('foo bar!baz\xfequux'), 'rando password'))


class TestLogInUsername:

  async def test_error_if_no_such_user(self, any_servicer: Servicer):
    assert 'no such user' in str(LogInUsernameErr(any_servicer, None, ALICE, 'some password'))

  async def test_success_when_user_exists_and_password_right(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE, 'password')
    assert LogInUsernameOk(any_servicer, None, ALICE, 'password').token.owner == ALICE

  async def test_error_if_wrong_password(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE, 'password')
    assert 'bad password' in str(LogInUsernameErr(any_servicer, None, ALICE, 'WRONG'))

  async def test_error_if_already_logged_in(self, any_servicer: Servicer):
    orig_pw = 'pw'
    RegisterUsernameOk(any_servicer, None, ALICE, orig_pw)
    assert 'first, log out' in str(LogInUsernameErr(any_servicer, ALICE, ALICE, orig_pw))


class TestCreatePrediction:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in to create predictions' in str(CreatePredictionErr(any_servicer, None, {}))

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(prediction='a thing will happen'))
    assert GetPredictionOk(any_servicer, ALICE, prediction_id).prediction == 'a thing will happen'

  async def test_returns_distinct_ids(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    ids = {CreatePredictionOk(any_servicer, ALICE, {}) for _ in range(30)}
    assert len(ids) == 30
    for prediction_id in ids:
      GetPredictionOk(any_servicer, ALICE, prediction_id)

  async def test_returns_urlsafe_ids(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    ids = {CreatePredictionOk(any_servicer, ALICE, {}) for _ in range(30)}
    assert all(id.isalnum() for id in ids)


class TestGetPrediction:

  async def test_has_all_fields(self, any_servicer: Servicer, clock: MockClock):
    req_kwargs = dict(
      prediction='a thing will happen',
      special_rules='some special rules',
      maximum_stake_cents=100_00,
      certainty=mvp_pb2.CertaintyRange(low=0.50, high=1.00),
    )
    req = some_create_prediction_request(**req_kwargs)
    register_friend_pair(any_servicer, ALICE, BOB)

    create_time = clock.now().timestamp()
    prediction_id = CreatePredictionOk(any_servicer, ALICE, req_kwargs)

    clock.tick()
    stake_time = clock.now().timestamp()
    StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=1_00))

    clock.tick()
    resolve_time = clock.now().timestamp()
    ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES)

    resp = GetPredictionOk(any_servicer, BOB, prediction_id)
    assert resp == mvp_pb2.UserPredictionView(
      prediction=req.prediction,
      certainty=req.certainty,
      maximum_stake_cents=req.maximum_stake_cents,
      remaining_stake_cents_vs_believers=req.maximum_stake_cents,
      remaining_stake_cents_vs_skeptics=req.maximum_stake_cents - resp.trades_by_bettor[BOB].creator_stake_cents,
      created_unixtime=create_time,
      closes_unixtime=create_time + req.open_seconds,
      resolves_at_unixtime=req.resolves_at_unixtime,
      special_rules=req.special_rules,
      creator=ALICE,
      resolution=mvp_pb2.ResolutionEvent(unixtime=resolve_time, resolution=mvp_pb2.RESOLUTION_YES),
      trades_by_bettor={BOB: mvp_pb2.Trade(bettor=BOB, bettor_is_a_skeptic=True, bettor_stake_cents=1_00, creator_stake_cents=1_00, transacted_unixtime=stake_time, updated_unixtime=stake_time, state=mvp_pb2.TRADE_STATE_ACTIVE)},
    )


  async def test_success_if_logged_out(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    GetPredictionOk(any_servicer, None, prediction_id)

  async def test_success_if_logged_in(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    RegisterUsernameOk(any_servicer, None, BOB)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    GetPredictionOk(any_servicer, BOB, prediction_id)

  async def test_error_if_no_such_prediction(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, BOB)
    assert 'no such prediction' in str(GetPredictionErr(any_servicer, BOB, PredictionId('12345')))

class TestListMyStakes:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
      assert 'must log in to create predictions' in str(CreatePredictionErr(any_servicer, None, {}))

  async def test_includes_own_predictions(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    RegisterUsernameOk(any_servicer, None, BOB)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, BOB, {})
    assert set(ListMyStakesOk(any_servicer, ALICE).predictions.keys()) == {prediction_id}

  async def test_includes_others_predictions(self, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    RegisterUsernameOk(any_servicer, None, CHARLIE)
    prediction_id = CreatePredictionOk(any_servicer, BOB, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, CHARLIE, {})
    StakeOk(any_servicer, ALICE, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00))
    assert set(ListMyStakesOk(any_servicer, ALICE).predictions.keys()) == {prediction_id}


class TestListPredictions:

  async def test_success_listing_own(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    RegisterUsernameOk(any_servicer, None, BOB)
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, BOB, {})

    assert set(ListPredictionsOk(any_servicer, ALICE, ALICE).predictions.keys()) == {prediction_id}

  async def test_success_listing_friend(self, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    alice_prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, BOB, {})
    assert set(ListPredictionsOk(any_servicer, BOB, ALICE).predictions.keys()) == {alice_prediction_id}

  async def test_error_listing_untruster(self, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    RegisterUsernameOk(any_servicer, None, CHARLIE)
    SetTrustedOk(any_servicer, ALICE, BOB, False)
    alice_prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    for username in [BOB, CHARLIE]:
      assert "creator doesn\\'t trust you" in str(ListPredictionsErr(any_servicer, au(username), ALICE))


def some_stake_request(prediction_id: PredictionId, **kwargs) -> mvp_pb2.StakeRequest:
  kwargs['prediction_id'] = prediction_id
  kwargs.setdefault('bettor_is_a_skeptic', True)
  kwargs.setdefault('bettor_stake_cents', 10)
  return mvp_pb2.StakeRequest(**kwargs)

class TestStake:

  class TestWithMutualTrust:
    async def test_error_if_resolved(self, any_servicer: Servicer):
      register_friend_pair(any_servicer, ALICE, BOB)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
      ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES)

      with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
        assert 'prediction has already resolved' in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)))

    async def test_error_if_closed(self, clock: MockClock, any_servicer: Servicer):
      register_friend_pair(any_servicer, ALICE, BOB)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(open_seconds=86400, resolves_at_unixtime=int(clock.now().timestamp() + 2*86400)))

      clock.tick(86401)
      with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
        assert 'prediction is no longer open for betting' in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)))

    class TestHappyPath:

      async def test_adds_trade_to_prediction(self, any_servicer: Servicer):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
        StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
        assert BOB in GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor

      async def test_returns_new_prediction(self, any_servicer: Servicer):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
        old_pred = GetPredictionOk(any_servicer, BOB, prediction_id)
        resp_pred = StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
        new_pred = GetPredictionOk(any_servicer, BOB, prediction_id)
        assert new_pred == resp_pred != old_pred

      async def test_copies_fields_from_request(self, any_servicer: Servicer):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
        StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=True,
          bettor_stake_cents=20,
        ))
        trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB]
        assert trade.bettor == BOB
        assert trade.bettor_is_a_skeptic
        assert trade.bettor_stake_cents == 20

      async def test_autopopulated_fields(self, any_servicer: Servicer, clock: MockClock):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, {'open_seconds': 86400})
        clock.tick(12353)  # some random length less than open_seconds
        StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
        trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB]
        assert trade.state == mvp_pb2.TRADE_STATE_ACTIVE
        assert trade.transacted_unixtime == clock.now().timestamp()
        assert trade.updated_unixtime == clock.now().timestamp()
        assert trade.notes == ''

      @pytest.mark.parametrize('skeptic', [True, False])
      async def test_computes_creator_stake_correctly(self, any_servicer: Servicer, skeptic: bool):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, {'certainty': mvp_pb2.CertaintyRange(low=0.40, high=0.70)})
        StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=skeptic, bettor_stake_cents=13))
        expected_factor = (0.40/(1-0.40)) if skeptic else (1-0.70)/0.70
        assert GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB].creator_stake_cents == int(13 * expected_factor)

      @pytest.mark.parametrize('bettor_is_a_skeptic', [True, False])
      async def test_reduces_remaining_stake(self, any_servicer: Servicer, bettor_is_a_skeptic: bool):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
        StakeOk(any_servicer, BOB, some_stake_request(prediction_id, bettor_is_a_skeptic=bettor_is_a_skeptic))
        pred = GetPredictionOk(any_servicer, ALICE, prediction_id)
        remaining = pred.remaining_stake_cents_vs_skeptics if bettor_is_a_skeptic else pred.remaining_stake_cents_vs_believers
        assert remaining + pred.trades_by_bettor[BOB].creator_stake_cents == pred.maximum_stake_cents

    class TestExposureLimitEnforcement:
      @pytest.mark.parametrize('bettor_is_a_skeptic,certainty', [
        (True, mvp_pb2.CertaintyRange(low=0.50, high=1.00)),
        (False, mvp_pb2.CertaintyRange(low=0.10, high=0.50)),
      ])
      async def test_prevents_overpromising_on_single_side(self, any_servicer: Servicer, bettor_is_a_skeptic: bool, certainty: mvp_pb2.CertaintyRange):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(
            certainty=certainty,
            maximum_stake_cents=100_00,
        ))

        StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=bettor_is_a_skeptic,
          bettor_stake_cents=99_00,
        ))
        with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
          assert 'bet would exceed creator tolerance' in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(
            prediction_id=prediction_id,
            bettor_is_a_skeptic=bettor_is_a_skeptic,
            bettor_stake_cents=10_00,
          )))

      async def test_bets_on_opposite_sides_dont_stack(self, any_servicer: Servicer, clock: MockClock):
        register_friend_pair(any_servicer, ALICE, BOB)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(
            certainty=mvp_pb2.CertaintyRange(low=0.50, high=0.80),
            maximum_stake_cents=100_00,
        ))

        StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=True,
          bettor_stake_cents=100_00,
        ))
        clock.tick()
        StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=False,
          bettor_stake_cents=400_00,
        ))
        with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
          assert 'bet would exceed creator tolerance' in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(
            prediction_id=prediction_id,
            bettor_is_a_skeptic=True,
            bettor_stake_cents=1,
          )))
          assert 'bet would exceed creator tolerance' in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(
            prediction_id=prediction_id,
            bettor_is_a_skeptic=False,
            bettor_stake_cents=10_00,
          )))

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
      assert 'must log in to bet' in str(StakeErr(any_servicer, None, mvp_pb2.StakeRequest(prediction_id=prediction_id)))

  async def test_error_if_bettor_doesnt_trust_creator(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    RegisterUsernameOk(any_servicer, None, BOB)
    SetTrustedOk(any_servicer, ALICE, BOB, True)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
      assert "you don\\'t trust the creator" in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=10)))

  class TestQueueing:

    @staticmethod
    def _make_bob_trust_alice(any_servicer: Servicer):
      RegisterUsernameOk(any_servicer, None, ALICE)
      RegisterUsernameOk(any_servicer, None, BOB)
      SetTrustedOk(any_servicer, BOB, ALICE, True)

    async def test_queues_if_creator_doesnt_trust_bettor(self, any_servicer: Servicer):
      self._make_bob_trust_alice(any_servicer)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
      StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
      trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB]
      assert trade.state == mvp_pb2.TRADE_STATE_QUEUED

    async def test_queued_trades_dont_affect_remaining_stake(self, any_servicer: Servicer):
      self._make_bob_trust_alice(any_servicer)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
      StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
      pred = GetPredictionOk(any_servicer, ALICE, prediction_id)
      assert pred.remaining_stake_cents_vs_skeptics == pred.maximum_stake_cents

    async def test_queued_trade_is_mostly_exactly_like_nonqueued_trade(self, any_servicer: Servicer, clock: MockClock):
      register_friend_pair(any_servicer, ALICE, BOB)
      RegisterUsernameOk(any_servicer, None, CHARLIE)
      SetTrustedOk(any_servicer, CHARLIE, ALICE, True)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
      request = some_stake_request(prediction_id)
      StakeOk(any_servicer, BOB, request)
      StakeOk(any_servicer, CHARLIE, request)
      trades = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor
      assert trades[BOB].bettor_stake_cents == trades[CHARLIE].bettor_stake_cents
      assert trades[BOB].creator_stake_cents == trades[CHARLIE].creator_stake_cents
      assert trades[BOB].bettor_is_a_skeptic == trades[CHARLIE].bettor_is_a_skeptic

    async def test_cant_overpromise_even_if_queueing(self, any_servicer: Servicer):
      self._make_bob_trust_alice(any_servicer)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(
          certainty=mvp_pb2.CertaintyRange(low=0.50, high=1.00),
          maximum_stake_cents=100_00,
      ))
      with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
        assert 'bet would exceed creator tolerance' in str(StakeErr(any_servicer, BOB, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=True,
          bettor_stake_cents=101_00,
        )))

    async def test_queued_trade_applied_when_mutual_trust_created(self, any_servicer: Servicer):
      self._make_bob_trust_alice(any_servicer)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
      StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
      trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB]
      assert trade.state == mvp_pb2.TRADE_STATE_QUEUED
      SetTrustedOk(any_servicer, ALICE, BOB, True)
      trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB]
      assert trade.state == mvp_pb2.TRADE_STATE_ACTIVE

    async def test_queued_trade_partially_applied_when_mutual_trust_created_if_would_overfill(self, any_servicer: Servicer):
      register_friend_pair(any_servicer, ALICE, BOB)
      RegisterUsernameOk(any_servicer, None, CHARLIE)
      SetTrustedOk(any_servicer, CHARLIE, ALICE, True)
      prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(
          certainty=mvp_pb2.CertaintyRange(low=0.50, high=1.00),
          maximum_stake_cents=100_00,
      ))

      StakeOk(any_servicer, CHARLIE, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=70_00,
      ))
      StakeOk(any_servicer, BOB, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=60_00,
      ))

      SetTrustedOk(any_servicer, ALICE, CHARLIE, True)
      dequeued_trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[CHARLIE]
      assert dequeued_trade.creator_stake_cents == dequeued_trade.bettor_stake_cents == (100_00 - 60_00)

    class TestDequeueFailure:
      def _arrange_dequeue_failure(self, any_servicer: Servicer, bettor: AuthorizingUsername) -> mvp_pb2.UserPredictionView:
        friend = CHARLIE if bettor == BOB else BOB
        register_friend_pair(any_servicer, ALICE, friend)
        RegisterUsernameOk(any_servicer, None, bettor)
        SetTrustedOk(any_servicer, bettor, ALICE, True)
        prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(
            certainty=mvp_pb2.CertaintyRange(low=0.50, high=1.00),
            maximum_stake_cents=100_00,
        ))

        StakeOk(any_servicer, bettor, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=True,
          bettor_stake_cents=20_00,
        ))
        StakeOk(any_servicer, friend, mvp_pb2.StakeRequest(
          prediction_id=prediction_id,
          bettor_is_a_skeptic=True,
          bettor_stake_cents=99_99,
        ))

        SetTrustedOk(any_servicer, ALICE, bettor, True)
        return GetPredictionOk(any_servicer, ALICE, prediction_id)

      def test_sets_state(self, any_servicer: Servicer):
        failed_trade = self._arrange_dequeue_failure(any_servicer, bettor=CHARLIE).trades_by_bettor[CHARLIE]
        assert failed_trade.state == mvp_pb2.TRADE_STATE_DEQUEUE_FAILED

      def test_notes_reflect_failure(self, any_servicer: Servicer):
        failed_trade = self._arrange_dequeue_failure(any_servicer, bettor=CHARLIE).trades_by_bettor[CHARLIE]
        assert failed_trade.notes == '[trade ignored during dequeue due to trivial stakes]'

      def test_failed_trade_doesnt_affect_exposure(self, any_servicer: Servicer):
        pred = self._arrange_dequeue_failure(any_servicer, bettor=CHARLIE)
        assert pred.remaining_stake_cents_vs_skeptics + sum(t.creator_stake_cents for t in pred.trades_by_bettor.values()) > pred.maximum_stake_cents
        assert pred.remaining_stake_cents_vs_skeptics + sum(t.creator_stake_cents for t in pred.trades_by_bettor.values() if t.state == mvp_pb2.TRADE_STATE_ACTIVE) == pred.maximum_stake_cents


class TestResolve:

  async def test_returns_new_prediction(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    old_pred = GetPredictionOk(any_servicer, ALICE, prediction_id)
    resp_pred = ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES)
    new_pred = GetPredictionOk(any_servicer, ALICE, prediction_id)
    assert new_pred == resp_pred != old_pred

  async def test_smoke(self, any_servicer: Servicer, clock: MockClock):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {'open_seconds': 86400})
    clock.tick(18472)  # some random length less than open_seconds

    assert ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES, notes='my test notes').resolution == mvp_pb2.ResolutionEvent(
      unixtime=clock.now().timestamp(),
      resolution=mvp_pb2.RESOLUTION_YES,
      notes='my test notes',
    )

  async def test_remembers_prior_revision_when_reresolved(self, any_servicer: Servicer, clock: MockClock):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {'open_seconds': 86400})
    first_res = ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES, notes='first').resolution
    clock.tick()
    second_res = ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_NO, notes='second').resolution
    assert not first_res.HasField('prior_revision')
    assert second_res.prior_revision == first_res

  async def test_error_if_no_such_prediction(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    assert 'no such prediction' in str(ResolveErr(any_servicer, ALICE, pid('not_'+prediction_id), mvp_pb2.RESOLUTION_YES))

  async def test_error_if_notes_too_long(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    assert 'unreasonably long notes' in str(ResolveErr(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES, notes=99999*'foo'))

  async def test_error_if_invalid_resolution(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    bad_resolution_value: mvp_pb2.Resolution.V = 99  # type: ignore
    assert 'unrecognized resolution' in str(ResolveErr(any_servicer, ALICE, prediction_id, bad_resolution_value))

  async def test_error_if_not_creator(self, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})

    RegisterUsernameOk(any_servicer, None, CHARLIE)
    for actor in [BOB, CHARLIE]:
      with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id):
        assert 'not the creator' in str(ResolveErr(any_servicer, actor, prediction_id, mvp_pb2.RESOLUTION_NO))

  async def test_sends_notifications(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'), email_resolution_notifications=True, trust_users=[ALICE])
    SetTrustedOk(any_servicer, ALICE, BOB, True)

    prediction_id = CreatePredictionOk(any_servicer, ALICE, dict(prediction='a thing will happen'))
    StakeOk(any_servicer, BOB, request=mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=10))

    ResolveOk(any_servicer, ALICE, prediction_id, mvp_pb2.RESOLUTION_YES)
    emailer.send_resolution_notifications.assert_called_once_with(  # type: ignore
      bccs={'bob@example.com'},
      prediction_id=prediction_id,
      prediction_text='a thing will happen',
      resolution=mvp_pb2.RESOLUTION_YES,
    )


class TestSetTrusted:

  async def test_error_when_logged_out(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert 'must log in to trust folks' in str(SetTrustedErr(any_servicer, None, ALICE, True))

  async def test_error_if_nonexistent(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert 'no such user' in str(SetTrustedErr(any_servicer, ALICE, u('nonexistent'), True))

  async def test_error_if_self(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert 'cannot set trust for self' in str(SetTrustedErr(any_servicer, ALICE, ALICE, True))

  async def test_happy_path(self, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    RegisterUsernameOk(any_servicer, None, CHARLIE)

    alice_view_of_bob = GetUserOk(any_servicer, ALICE, BOB)
    assert alice_view_of_bob.trusted_by_you

    SetTrustedOk(any_servicer, ALICE, BOB, False)

    alice_view_of_bob = GetUserOk(any_servicer, ALICE, BOB)
    assert not alice_view_of_bob.trusted_by_you

  @pytest.mark.parametrize('trust', [True, False])
  async def test_removing_trust_deletes_outgoing_invitation(self, any_servicer: Servicer, emailer: Emailer, trust: bool):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'))
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'), allow_email_invitations=True)

    SendInvitationOk(any_servicer, ALICE, BOB)
    SetTrustedOk(any_servicer, ALICE, BOB, trust)

    expected_invitations = {BOB: mvp_pb2.GenericUserInfo.Invitation()} if trust else {}
    assert GetSettingsOk(any_servicer, ALICE).invitations == expected_invitations


class TestGetUser:

  async def test_error_when_nonexistent(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert 'no such user' in str(GetUserErr(any_servicer, None, u('nonexistentuser')))

  async def test_success_when_self(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    resp = GetUserOk(any_servicer, ALICE, ALICE)
    assert resp == mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)

  async def test_success_when_friend(self, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    resp = GetUserOk(any_servicer, ALICE, BOB)
    assert resp == mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)

  async def test_shows_trust_correctly_when_logged_in(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    RegisterUsernameOk(any_servicer, None, BOB)
    SetTrustedOk(any_servicer, BOB, ALICE, True)
    resp = GetUserOk(any_servicer, ALICE, BOB)
    assert resp == mvp_pb2.Relationship(trusted_by_you=False, trusts_you=True)

    RegisterUsernameOk(any_servicer, None, CHARLIE)
    SetTrustedOk(any_servicer, ALICE, CHARLIE, True)
    resp = GetUserOk(any_servicer, ALICE, CHARLIE)
    assert resp == mvp_pb2.Relationship(trusted_by_you=True, trusts_you=False)

  async def test_no_trust_when_logged_out(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    resp = GetUserOk(any_servicer, None, ALICE)
    assert resp == mvp_pb2.Relationship(trusted_by_you=False, trusts_you=False)


class TestChangePassword:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE, 'original pw')
    with assert_user_unchanged(any_servicer, ALICE, 'original pw'):
      assert 'must log in' in str(ChangePasswordErr(any_servicer, None, 'original pw', 'new password'))

  async def test_can_log_in_with_new_password(self, any_servicer: Servicer):
    orig_pw = 'pw'
    RegisterUsernameOk(any_servicer, None, ALICE, password=orig_pw)
    ChangePasswordOk(any_servicer, ALICE, orig_pw, 'new password')
    assert LogInUsernameOk(any_servicer, None, ALICE, 'new password').token.owner == ALICE

  async def test_error_when_wrong_old_password(self, any_servicer: Servicer):
    orig_pw = 'pw'
    RegisterUsernameOk(any_servicer, None, ALICE, password=orig_pw)
    with assert_user_unchanged(any_servicer, ALICE, orig_pw):
      assert 'wrong old password' in str(ChangePasswordErr(any_servicer, ALICE, 'WRONG', 'new password'))


class TestSetEmail:

  async def test_changes_settings(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'nobody@example.com')
    assert GetSettingsOk(any_servicer, ALICE).email.code_sent.email == 'nobody@example.com'

  async def test_returns_new_flow_state(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert SetEmailOk(any_servicer, ALICE, 'nobody@example.com').code_sent.email == 'nobody@example.com'

  async def test_sends_code_in_email(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'nobody@example.com')
    emailer.send_email_verification.assert_called_once_with(to='nobody@example.com', code=ANY)  # type: ignore

  async def test_works_in_code_sent_state(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'old@old.old')
    SetEmailOk(any_servicer, ALICE, 'new@new.new')
    assert GetSettingsOk(any_servicer, ALICE).email.code_sent.email == 'new@new.new'
    emailer.send_email_verification.assert_called_with(to='new@new.new', code=ANY)  # type: ignore

  async def test_works_in_verified_state(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    set_and_verify_email(any_servicer, emailer, ALICE, 'old@old.old')
    SetEmailOk(any_servicer, ALICE, 'new@new.new')
    assert GetSettingsOk(any_servicer, ALICE).email.code_sent.email == 'new@new.new'
    emailer.send_email_verification.assert_called_with(to='new@new.new', code=ANY)  # type: ignore

  async def test_clears_email_when_address_is_empty(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'nobody@example.com')
    emailer.send_email_verification.reset_mock()  # type: ignore
    assert SetEmailOk(any_servicer, ALICE, '').WhichOneof('email_flow_state_kind') == 'unstarted'
    emailer.send_email_verification.assert_not_called()  # type: ignore

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(SetEmailErr(any_servicer, None, 'nobody@example.com'))

  async def test_validates_email(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE, 'pw')
    for good_email_address in ['a@b', 'b@c.com', 'a.b-c_d+tag@example.com']:
      assert SetEmailOk(any_servicer, ALICE, good_email_address).code_sent.email == good_email_address
    for bad_email_address in ['bad email', 'bad@example.com  ', 'good@example.com, evil@example.com']:
      with assert_user_unchanged(any_servicer, ALICE, 'pw'):
        assert 'invalid-looking email' in str(SetEmailErr(any_servicer, ALICE, bad_email_address))


class TestVerifyEmail:

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert VerifyEmailOk(any_servicer, ALICE, code=code).verified == 'nobody@example.com'

  async def test_error_if_wrong_code(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert 'bad code' in str(VerifyEmailErr(any_servicer, ALICE, code='not ' + code))

  async def test_error_if_unstarted(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    assert 'no pending email-verification' in str(VerifyEmailErr(any_servicer, ALICE, code='some code'))

  async def test_error_if_restarted(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'old@old.old')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    SetEmailOk(any_servicer, ALICE, 'new@new.new')
    assert 'bad code' in str(VerifyEmailErr(any_servicer, ALICE, code=code))

  async def test_error_if_already_verified(self, emailer: Emailer, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    SetEmailOk(any_servicer, ALICE, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    VerifyEmailOk(any_servicer, ALICE, code=code)
    assert 'no pending email-verification' in str(VerifyEmailErr(any_servicer, ALICE, code=code))

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(VerifyEmailErr(any_servicer, None, code='foo'))


class TestGetSettings:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(GetSettingsErr(any_servicer, None))

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    register_friend_pair(any_servicer, ALICE, BOB)
    geninfo = GetSettingsOk(any_servicer, ALICE)
    assert dict(geninfo.relationships) == {BOB: mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)}


class TestUpdateSettings:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(UpdateSettingsErr(any_servicer, None))

  async def test_noop_if_no_args_given(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE, 'pw')
    with assert_user_unchanged(any_servicer, ALICE, 'pw'):
      UpdateSettingsOk(any_servicer, ALICE)

  async def test_resolution_notification_settings_are_persisted(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    UpdateSettingsOk(any_servicer, ALICE, email_resolution_notifications=False)
    assert not GetSettingsOk(any_servicer, ALICE).email_resolution_notifications
    UpdateSettingsOk(any_servicer, ALICE, email_resolution_notifications=True)
    assert GetSettingsOk(any_servicer, ALICE).email_resolution_notifications

  async def test_reminder_settings_are_persisted(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    UpdateSettingsOk(any_servicer, ALICE, email_reminders_to_resolve=False)
    assert not GetSettingsOk(any_servicer, ALICE).email_reminders_to_resolve
    UpdateSettingsOk(any_servicer, ALICE, email_reminders_to_resolve=True)
    assert GetSettingsOk(any_servicer, ALICE).email_reminders_to_resolve

  async def test_email_invitation_settings_are_persisted(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    UpdateSettingsOk(any_servicer, ALICE, allow_email_invitations=False)
    assert not GetSettingsOk(any_servicer, ALICE).allow_email_invitations
    UpdateSettingsOk(any_servicer, ALICE, allow_email_invitations=True)
    assert GetSettingsOk(any_servicer, ALICE).allow_email_invitations

  async def test_invitation_acceptance_notification_settings_are_persisted(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    UpdateSettingsOk(any_servicer, ALICE, email_invitation_acceptance_notifications=False)
    assert not GetSettingsOk(any_servicer, ALICE).email_invitation_acceptance_notifications
    UpdateSettingsOk(any_servicer, ALICE, email_invitation_acceptance_notifications=True)
    assert GetSettingsOk(any_servicer, ALICE).email_invitation_acceptance_notifications

  async def test_response_has_new_settings(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    resp = UpdateSettingsOk(any_servicer, ALICE, email_reminders_to_resolve=True)
    assert resp == GetSettingsOk(any_servicer, ALICE)


class TestSendInvitation:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(SendInvitationErr(any_servicer, None, 'anybody'))

  async def test_error_if_inviter_has_no_email(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'))
    RegisterUsernameOk(any_servicer, None, BOB)

    assert 'you need to add an email address before you can send invitations' in str(SendInvitationErr(any_servicer, BOB, ALICE))

  async def test_error_if_recipient_has_no_email(self, any_servicer: Servicer, emailer: Emailer):
    RegisterUsernameOk(any_servicer, None, ALICE)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))

    assert 'does not accept email invitations' in str(SendInvitationErr(any_servicer, BOB, ALICE))

  async def test_error_if_recipient_disabled_email_invitations(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=False)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))

    assert 'does not accept email invitations' in str(SendInvitationErr(any_servicer, BOB, ALICE))

  async def test_error_if_already_sent(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))

    SendInvitationOk(any_servicer, BOB, ALICE)
    assert 'already asked this user if they trust you' in str(SendInvitationErr(any_servicer, BOB, ALICE))

  async def test_sends_email(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))

    SendInvitationOk(any_servicer, BOB, ALICE)

    emailer.send_invitation.assert_called_once_with(  # type: ignore
      inviter_username=BOB,
      inviter_email='bob@example.com',
      recipient_username=ALICE,
      recipient_email='alice@example.com',
      nonce=ANY,
    )


class TestCheckInvitation:

  async def test_error_when_no_such_invitation(self, any_servicer: Servicer):
    assert 'no such invitation' in str(CheckInvitationErr(any_servicer, None, 'asdf'))

  async def test_returns_info_from_send(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))

    SendInvitationOk(any_servicer, BOB, 'alice')
    resp = CheckInvitationOk(any_servicer, None, get_call_kwarg(emailer.send_invitation, 'nonce'))
    assert resp.inviter == BOB
    assert resp.recipient == ALICE


class TestAcceptInvitation:

  async def test_sets_intended_trust_if_logged_in_as_recipient(self, any_servicer: Servicer, emailer: Emailer, clock: MockClock):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))
    SendInvitationOk(any_servicer, BOB, ALICE)
    AcceptInvitationOk(any_servicer, ALICE, get_call_kwarg(emailer.send_invitation, 'nonce'))

    rel = GetSettingsOk(any_servicer, ALICE).relationships[BOB]
    assert rel.trusts_you and rel.trusted_by_you

  async def test_commits_queued_trades(self, any_servicer: Servicer, emailer: Emailer, clock: MockClock):
    init_user(any_servicer,ALICE, email=(emailer, 'alice@example.com'))
    init_user(any_servicer,BOB, email=(emailer, 'bob@example.com'))
    prediction_id = CreatePredictionOk(any_servicer, ALICE, {})
    SendInvitationOk(any_servicer, BOB, ALICE)
    StakeOk(any_servicer, BOB, some_stake_request(prediction_id))
    AcceptInvitationOk(any_servicer, ALICE, get_call_kwarg(emailer.send_invitation, 'nonce'))
    trade = GetPredictionOk(any_servicer, ALICE, prediction_id).trades_by_bettor[BOB]
    assert trade.state == mvp_pb2.TRADE_STATE_ACTIVE

  async def test_successfully_creates_trust_even_if_logged_out(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))
    SendInvitationOk(any_servicer, BOB, ALICE)
    AcceptInvitationOk(any_servicer, None, get_call_kwarg(emailer.send_invitation, 'nonce'))
    rel = GetSettingsOk(any_servicer, ALICE).relationships[BOB]
    assert rel.trusts_you and rel.trusted_by_you

  async def test_sets_intended_trust_if_logged_in_as_other_user(self, any_servicer: Servicer, emailer: Emailer, clock: MockClock):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))
    RegisterUsernameOk(any_servicer, None, CHARLIE, password='pw')

    SendInvitationOk(any_servicer, BOB, ALICE)
    with assert_user_unchanged(any_servicer, CHARLIE, 'pw'):
      AcceptInvitationOk(any_servicer, CHARLIE, get_call_kwarg(emailer.send_invitation, 'nonce'))

    rel = GetSettingsOk(any_servicer, ALICE).relationships[BOB]
    assert rel.trusts_you and rel.trusted_by_you

  async def test_sends_email_to_inviter_if_settings_appropriate(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'), email_invitation_acceptance_notifications=True)

    SendInvitationOk(any_servicer, BOB, ALICE)
    AcceptInvitationOk(any_servicer, None, get_call_kwarg(emailer.send_invitation, 'nonce'))
    emailer.send_invitation_acceptance_notification.assert_called_once_with(inviter_email='bob@example.com', recipient_username=ALICE)  # type: ignore

  async def test_does_not_send_email_to_inviter_if_no_email(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'))

    SendInvitationOk(any_servicer, BOB, ALICE)
    SetEmailOk(any_servicer, BOB, '')
    AcceptInvitationOk(any_servicer, None, get_call_kwarg(emailer.send_invitation, 'nonce'))
    emailer.send_invitation_acceptance_notification.assert_not_called()  # type: ignore

  async def test_does_not_send_email_to_inviter_if_notifications_disabled(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'), email_invitation_acceptance_notifications=False)

    SendInvitationOk(any_servicer, BOB, ALICE)
    AcceptInvitationOk(any_servicer, None, get_call_kwarg(emailer.send_invitation, 'nonce'))
    emailer.send_invitation_acceptance_notification.assert_not_called()  # type: ignore

  async def test_error_when_no_such_invitation(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, ALICE, password='pw')
    with assert_user_unchanged(any_servicer, ALICE, 'pw'):
      assert 'no such invitation' in str(AcceptInvitationErr(any_servicer, ALICE, nonce='asdf'))

  async def test_error_when_invitation_is_already_used(self, any_servicer: Servicer, emailer: Emailer):
    init_user(any_servicer, ALICE, email=(emailer, 'alice@example.com'), allow_email_invitations=True)
    init_user(any_servicer, BOB, email=(emailer, 'bob@example.com'), password='pw')
    SendInvitationOk(any_servicer, BOB, ALICE)
    nonce = get_call_kwarg(emailer.send_invitation, 'nonce')
    AcceptInvitationOk(any_servicer, ALICE, nonce)
    with assert_user_unchanged(any_servicer, BOB, 'pw'):
      assert 'no such invitation' in str(AcceptInvitationErr(any_servicer, ALICE, nonce=nonce))
