from __future__ import annotations

import copy
from sys import prefix
from typing import Any, Mapping, overload, Optional
from typing_extensions import Literal
from unittest.mock import ANY

from .protobuf import mvp_pb2
from .core import Servicer
from .emailer import Emailer
from .test_utils import *

PRED_ID_1 = PredictionId('my_pred_id_1')

def Whoami(servicer: Servicer, token: Optional[mvp_pb2.AuthToken]) -> mvp_pb2.AuthToken:
  return servicer.Whoami(token, mvp_pb2.WhoamiRequest()).auth

def SignOut(servicer: Servicer, token: Optional[mvp_pb2.AuthToken]) -> None:
  servicer.SignOut(token, mvp_pb2.SignOutRequest())

def RegisterUsernameOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], username: str, password: str) -> mvp_pb2.AuthSuccess:
  return assert_oneof(servicer.RegisterUsername(token, mvp_pb2.RegisterUsernameRequest(username=username, password=password)), 'register_username_result', 'ok', mvp_pb2.AuthSuccess)
def RegisterUsernameErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], username: str, password: str) -> mvp_pb2.RegisterUsernameResponse.Error:
  return assert_oneof(servicer.RegisterUsername(token, mvp_pb2.RegisterUsernameRequest(username=username, password=password)), 'register_username_result', 'error', mvp_pb2.RegisterUsernameResponse.Error)

def LogInUsernameOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], username: str, password: str) -> mvp_pb2.AuthSuccess:
  return assert_oneof(servicer.LogInUsername(token, mvp_pb2.LogInUsernameRequest(username=username, password=password)), 'log_in_username_result', 'ok', mvp_pb2.AuthSuccess)
def LogInUsernameErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], username: str, password: str) -> mvp_pb2.LogInUsernameResponse.Error:
  return assert_oneof(servicer.LogInUsername(token, mvp_pb2.LogInUsernameRequest(username=username, password=password)), 'log_in_username_result', 'error', mvp_pb2.LogInUsernameResponse.Error)

def CreatePredictionOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], request_kwargs: Mapping[str, Any]) -> PredictionId:
  return PredictionId(assert_oneof(servicer.CreatePrediction(token, some_create_prediction_request(**request_kwargs)), 'create_prediction_result', 'new_prediction_id', str))
def CreatePredictionErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], request_kwargs: Mapping[str, Any]) -> mvp_pb2.CreatePredictionResponse.Error:
  return assert_oneof(servicer.CreatePrediction(token, some_create_prediction_request(**request_kwargs)), 'create_prediction_result', 'error', mvp_pb2.CreatePredictionResponse.Error)

def GetPredictionOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], prediction_id: str) -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.GetPrediction(token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'prediction', mvp_pb2.UserPredictionView)
def GetPredictionErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], prediction_id: str) -> mvp_pb2.GetPredictionResponse.Error:
  return assert_oneof(servicer.GetPrediction(token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)), 'get_prediction_result', 'error', mvp_pb2.GetPredictionResponse.Error)

def ListMyStakesOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken]) -> mvp_pb2.PredictionsById:
  return assert_oneof(servicer.ListMyStakes(token, mvp_pb2.ListMyStakesRequest()), 'list_my_stakes_result', 'ok', mvp_pb2.PredictionsById)
def ListMyStakesErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken]) -> mvp_pb2.ListMyStakesResponse.Error:
  return assert_oneof(servicer.ListMyStakes(token, mvp_pb2.ListMyStakesRequest()), 'list_my_stakes_result', 'error', mvp_pb2.ListMyStakesResponse.Error)

def ListPredictionsOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], creator: str) -> mvp_pb2.PredictionsById:
  return assert_oneof(servicer.ListPredictions(token, mvp_pb2.ListPredictionsRequest(creator=creator)), 'list_predictions_result', 'ok', mvp_pb2.PredictionsById)
def ListPredictionsErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], creator: str) -> mvp_pb2.ListPredictionsResponse.Error:
  return assert_oneof(servicer.ListPredictions(token, mvp_pb2.ListPredictionsRequest(creator=creator)), 'list_predictions_result', 'error', mvp_pb2.ListPredictionsResponse.Error)

def StakeOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.Stake(token, request), 'stake_result', 'ok', mvp_pb2.UserPredictionView)
def StakeErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse.Error:
  return assert_oneof(servicer.Stake(token, request), 'stake_result', 'error', mvp_pb2.StakeResponse.Error)

def ResolveOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], prediction_id: str, resolution: mvp_pb2.Resolution.V, notes: str = '') -> mvp_pb2.UserPredictionView:
  return assert_oneof(servicer.Resolve(token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=resolution, notes=notes)), 'resolve_result', 'ok', mvp_pb2.UserPredictionView)
def ResolveErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], prediction_id: str, resolution: mvp_pb2.Resolution.V, notes: str = '') -> mvp_pb2.ResolveResponse.Error:
  return assert_oneof(servicer.Resolve(token, mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=resolution, notes=notes)), 'resolve_result', 'error', mvp_pb2.ResolveResponse.Error)

def SetTrustedOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], who: str, trusted: bool) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.SetTrusted(token, mvp_pb2.SetTrustedRequest(who=who, trusted=trusted)), 'set_trusted_result', 'ok', mvp_pb2.GenericUserInfo)
def SetTrustedErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], who: str, trusted: bool) -> mvp_pb2.SetTrustedResponse.Error:
  return assert_oneof(servicer.SetTrusted(token, mvp_pb2.SetTrustedRequest(who=who, trusted=trusted)), 'set_trusted_result', 'error', mvp_pb2.SetTrustedResponse.Error)

def GetUserOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], who: str) -> mvp_pb2.Relationship:
  return assert_oneof(servicer.GetUser(token, mvp_pb2.GetUserRequest(who=who)), 'get_user_result', 'ok', mvp_pb2.Relationship)
def GetUserErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], who: str) -> mvp_pb2.GetUserResponse.Error:
  return assert_oneof(servicer.GetUser(token, mvp_pb2.GetUserRequest(who=who)), 'get_user_result', 'error', mvp_pb2.GetUserResponse.Error)

def ChangePasswordOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], old_password: str, new_password: str) -> object:
  return assert_oneof(servicer.ChangePassword(token, mvp_pb2.ChangePasswordRequest(old_password=old_password, new_password=new_password)), 'change_password_result', 'ok', object)
def ChangePasswordErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], old_password: str, new_password: str) -> mvp_pb2.ChangePasswordResponse.Error:
  return assert_oneof(servicer.ChangePassword(token, mvp_pb2.ChangePasswordRequest(old_password=old_password, new_password=new_password)), 'change_password_result', 'error', mvp_pb2.ChangePasswordResponse.Error)

def SetEmailOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], email: str) -> mvp_pb2.EmailFlowState:
  return assert_oneof(servicer.SetEmail(token, mvp_pb2.SetEmailRequest(email=email)), 'set_email_result', 'ok', mvp_pb2.EmailFlowState)
def SetEmailErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], email: str) -> mvp_pb2.SetEmailResponse.Error:
  return assert_oneof(servicer.SetEmail(token, mvp_pb2.SetEmailRequest(email=email)), 'set_email_result', 'error', mvp_pb2.SetEmailResponse.Error)

def VerifyEmailOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], code: str) -> mvp_pb2.EmailFlowState:
  return assert_oneof(servicer.VerifyEmail(token, mvp_pb2.VerifyEmailRequest(code=code)), 'verify_email_result', 'ok', mvp_pb2.EmailFlowState)
def VerifyEmailErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], code: str) -> mvp_pb2.VerifyEmailResponse.Error:
  return assert_oneof(servicer.VerifyEmail(token, mvp_pb2.VerifyEmailRequest(code=code)), 'verify_email_result', 'error', mvp_pb2.VerifyEmailResponse.Error)

def GetSettingsOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken]) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'ok', mvp_pb2.GenericUserInfo)
def GetSettingsErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken]) -> mvp_pb2.GetSettingsResponse.Error:
  return assert_oneof(servicer.GetSettings(token, mvp_pb2.GetSettingsRequest()), 'get_settings_result', 'error', mvp_pb2.GetSettingsResponse.Error)

def UpdateSettingsOk(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], *, email_resolution_notifications: Optional[bool] = None, email_reminders_to_resolve: Optional[bool] = None) -> mvp_pb2.GenericUserInfo:
  return assert_oneof(servicer.UpdateSettings(token, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=None if email_resolution_notifications is None else mvp_pb2.MaybeBool(value=email_resolution_notifications), email_reminders_to_resolve=None if email_reminders_to_resolve is None else mvp_pb2.MaybeBool(value=email_reminders_to_resolve))), 'update_settings_result', 'ok', mvp_pb2.GenericUserInfo)
def UpdateSettingsErr(servicer: Servicer, token: Optional[mvp_pb2.AuthToken], *, email_resolution_notifications: Optional[bool] = None, email_reminders_to_resolve: Optional[bool] = None) -> mvp_pb2.UpdateSettingsResponse.Error:
  return assert_oneof(servicer.UpdateSettings(token, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=None if email_resolution_notifications is None else mvp_pb2.MaybeBool(value=email_resolution_notifications), email_reminders_to_resolve=None if email_reminders_to_resolve is None else mvp_pb2.MaybeBool(value=email_reminders_to_resolve))), 'update_settings_result', 'error', mvp_pb2.UpdateSettingsResponse.Error)


class TestCUJs:
  async def test_cuj__register__create__trust__stake__resolve(self, any_servicer: Servicer, clock: MockClock):
    creator_token = RegisterUsernameOk(any_servicer, None, 'creator', 'secret').token

    prediction_id = CreatePredictionOk(any_servicer, creator_token, dict(
        prediction='a thing will happen',
        resolves_at_unixtime=clock.now().timestamp() + 86400,
        certainty=mvp_pb2.CertaintyRange(low=0.40, high=0.60),
        maximum_stake_cents=100_00,
        open_seconds=3600,
      ))

    friend_token = RegisterUsernameOk(any_servicer, None, 'friend', 'secret').token
    SetTrustedOk(any_servicer, creator_token, friend_token.owner, True)
    friend_settings = SetTrustedOk(any_servicer, friend_token, creator_token.owner, True)
    assert friend_settings.relationships[creator_token.owner].trusts_you
    assert friend_settings.relationships[creator_token.owner].trusted_by_you

    prediction = StakeOk(any_servicer, friend_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=6_00))
    assert list(prediction.your_trades) == [mvp_pb2.Trade(
      bettor=friend_token.owner,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=6_00,
      creator_stake_cents=4_00,
      transacted_unixtime=clock.now().timestamp(),
    )]

    prediction = ResolveOk(any_servicer, creator_token, prediction_id, mvp_pb2.RESOLUTION_YES)
    assert list(prediction.resolutions) ==[mvp_pb2.ResolutionEvent(unixtime=clock.now().timestamp(), resolution=mvp_pb2.RESOLUTION_YES)]


  async def test_cuj___set_email__verify_email__update_settings(self, any_servicer: Servicer, emailer: Emailer):
    token = RegisterUsernameOk(any_servicer, None, 'creator', 'secret').token

    assert SetEmailOk(any_servicer, token, 'nobody@example.com').code_sent.email == 'nobody@example.com'

    emailer.send_email_verification.assert_called_once()  # type: ignore
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore

    assert VerifyEmailOk(any_servicer, token, code).verified == 'nobody@example.com'

    assert not GetSettingsOk(any_servicer, token).email_reminders_to_resolve

    assert UpdateSettingsOk(any_servicer, token, email_reminders_to_resolve=True).email_reminders_to_resolve

    assert GetSettingsOk(any_servicer, token).email_reminders_to_resolve



class TestWhoami:

  async def test_returns_none_when_logged_out(self, any_servicer: Servicer):
    assert not any_servicer.Whoami(token=None, request=mvp_pb2.WhoamiRequest()).HasField('auth')

  async def test_returns_token_when_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert any_servicer.Whoami(token=token, request=mvp_pb2.WhoamiRequest()).auth == token


class TestSignOut:

  async def test_smoke_logged_out(self, any_servicer: Servicer):
    any_servicer.SignOut(token=None, request=mvp_pb2.SignOutRequest())

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    any_servicer.SignOut(token=token, request=mvp_pb2.SignOutRequest())


class TestRegisterUsername:

  async def test_returns_auth_when_successful(self, any_servicer: Servicer):
    token = RegisterUsernameOk(any_servicer, None, 'alice', 'secret').token
    assert token.owner == 'alice'

  async def test_can_log_in_after_registering(self, any_servicer: Servicer):
    assert 'no such user' in str(LogInUsernameErr(any_servicer, None, 'alice', 'secret'))
    RegisterUsernameOk(any_servicer, None, 'alice', 'secret')
    assert LogInUsernameOk(any_servicer, None, 'alice', 'secret').token.owner == 'alice'

  async def test_error_when_already_exists(self, any_servicer: Servicer):
    orig_token = new_user_token(any_servicer, 'rando')

    for password in ['rando password', 'some other password']:
      with assert_user_unchanged(any_servicer, orig_token, 'rando password'):
        assert 'username taken' in str(RegisterUsernameErr(any_servicer, None, 'rando', password))

  async def test_error_if_already_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    with assert_user_unchanged(any_servicer, token, 'rando password'):
      assert 'first, log out' in str(RegisterUsernameErr(any_servicer, token, 'alice', 'secret'))

  async def test_error_if_invalid_username(self, any_servicer: Servicer):
    assert 'username must be alphanumeric' in str(RegisterUsernameErr(any_servicer, None, 'foo bar!baz\xfequux', 'rando password'))


class TestLogInUsername:

  async def test_error_if_no_such_user(self, any_servicer: Servicer):
    assert 'no such user' in str(LogInUsernameErr(any_servicer, None, 'rando', 'rando password'))

  async def test_success_when_user_exists_and_password_right(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, 'rando', 'password')
    assert LogInUsernameOk(any_servicer, None, 'rando', 'password').token.owner == 'rando'

  async def test_error_if_wrong_password(self, any_servicer: Servicer):
    RegisterUsernameOk(any_servicer, None, 'rando', 'password')
    assert 'bad password' in str(LogInUsernameErr(any_servicer, None, 'rando', 'WRONG'))

  async def test_error_if_already_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'first, log out' in str(LogInUsernameErr(any_servicer, token, 'rando', 'rando password'))


class TestCreatePrediction:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in to create predictions' in str(CreatePredictionErr(any_servicer, None, {}))

  async def test_smoke_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, token, dict(prediction='a thing will happen'))
    assert GetPredictionOk(any_servicer, token, prediction_id).prediction == 'a thing will happen'

  async def test_returns_distinct_ids(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    ids = {CreatePredictionOk(any_servicer, token, {}) for _ in range(30)}
    assert len(ids) == 30
    for prediction_id in ids:
      GetPredictionOk(any_servicer, token, prediction_id)

  async def test_returns_urlsafe_ids(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    ids = {CreatePredictionOk(any_servicer, token, {}) for _ in range(30)}
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
    alice_token, bob_token = alice_bob_tokens(any_servicer)

    create_time = clock.now().timestamp()
    prediction_id = CreatePredictionOk(any_servicer, alice_token, req_kwargs)

    clock.tick()
    stake_time = clock.now().timestamp()
    StakeOk(any_servicer, bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=1_00))

    clock.tick()
    resolve_time = clock.now().timestamp()
    ResolveOk(any_servicer, alice_token, prediction_id, mvp_pb2.RESOLUTION_YES)

    resp = GetPredictionOk(any_servicer, bob_token, prediction_id)
    assert resp == mvp_pb2.UserPredictionView(
      prediction=req.prediction,
      certainty=req.certainty,
      maximum_stake_cents=req.maximum_stake_cents,
      remaining_stake_cents_vs_believers=req.maximum_stake_cents,
      remaining_stake_cents_vs_skeptics=req.maximum_stake_cents - resp.your_trades[0].creator_stake_cents,
      created_unixtime=create_time,
      closes_unixtime=create_time + req.open_seconds,
      resolves_at_unixtime=req.resolves_at_unixtime,
      special_rules=req.special_rules,
      creator='Alice',
      resolutions=[mvp_pb2.ResolutionEvent(unixtime=resolve_time, resolution=mvp_pb2.RESOLUTION_YES)],
      your_trades=[mvp_pb2.Trade(bettor=bob_token.owner, bettor_is_a_skeptic=True, bettor_stake_cents=1_00, creator_stake_cents=1_00, transacted_unixtime=stake_time)],
    )


  async def test_success_if_logged_out(self, any_servicer: Servicer):
    prediction_id = CreatePredictionOk(any_servicer, new_user_token(any_servicer, 'rando'), {})
    GetPredictionOk(any_servicer, None, prediction_id)

  async def test_success_if_logged_in(self, any_servicer: Servicer):
    prediction_id = CreatePredictionOk(any_servicer, new_user_token(any_servicer, 'rando'), {})
    GetPredictionOk(any_servicer, new_user_token(any_servicer, 'otherrando'), prediction_id)

  async def test_error_if_no_such_prediction(self, any_servicer: Servicer):
    assert 'no such prediction' in str(GetPredictionErr(any_servicer, new_user_token(any_servicer, 'otherrando'), PredictionId('12345')))

class TestListMyStakes:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
      assert 'must log in to create predictions' in str(CreatePredictionErr(any_servicer, None, {}))

  async def test_includes_own_predictions(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'creator')
    prediction_id = CreatePredictionOk(any_servicer, token, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, new_user_token(any_servicer, 'otherrando'), {})
    assert set(ListMyStakesOk(any_servicer, token).predictions.keys()) == {prediction_id}

  async def test_includes_others_predictions(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = CreatePredictionOk(any_servicer, bob_token, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, new_user_token(any_servicer, 'otherrando'), {})
    StakeOk(any_servicer, alice_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00))
    assert set(ListMyStakesOk(any_servicer, alice_token).predictions.keys()) == {prediction_id}


class TestListPredictions:

  async def test_success_listing_own(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, token, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, new_user_token(any_servicer, 'otherrando'), {})

    assert set(ListPredictionsOk(any_servicer, token, token.owner).predictions.keys()) == {prediction_id}

  async def test_success_listing_friend(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    alice_prediction_id = CreatePredictionOk(any_servicer, alice_token, {})
    irrelevant_prediction_id = CreatePredictionOk(any_servicer, bob_token, {})
    assert set(ListPredictionsOk(any_servicer, bob_token, alice_token.owner).predictions.keys()) == {alice_prediction_id}

  async def test_error_listing_untruster(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    SetTrustedOk(any_servicer, alice_token, bob_token.owner, False)
    alice_prediction_id = CreatePredictionOk(any_servicer, alice_token, {})
    for token in [bob_token, new_user_token(any_servicer, 'rando')]:
      assert "creator doesn\\'t trust you" in str(ListPredictionsErr(any_servicer, token, alice_token.owner))



class TestStake:

  async def test_error_if_resolved(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = CreatePredictionOk(any_servicer, alice_token, {})
    ResolveOk(any_servicer, alice_token, prediction_id, mvp_pb2.RESOLUTION_YES)

    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'prediction has already resolved' in str(StakeErr(any_servicer, bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)))

  async def test_error_if_closed(self, clock: MockClock, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = CreatePredictionOk(any_servicer, alice_token, dict(open_seconds=86400, resolves_at_unixtime=int(clock.now().timestamp() + 2*86400)))

    clock.tick(86401)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'prediction is no longer open for betting' in str(StakeErr(any_servicer, bob_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=1_00)))

  async def test_happy_path(self, any_servicer: Servicer, clock: MockClock):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = CreatePredictionOk(any_servicer, alice_token, dict(
        certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
        maximum_stake_cents=100_00,
    ))

    StakeOk(any_servicer, bob_token, mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=20_00,
    ))
    StakeOk(any_servicer, bob_token, mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=90_00,
    ))
    assert list(GetPredictionOk(any_servicer, alice_token, prediction_id).your_trades) == [
      mvp_pb2.Trade(
        bettor=bob_token.owner,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=20_00,
        creator_stake_cents=80_00,
        transacted_unixtime=clock.now().timestamp(),
      ),
      mvp_pb2.Trade(
        bettor=bob_token.owner,
        bettor_is_a_skeptic=False,
        bettor_stake_cents=90_00,
        creator_stake_cents=10_00,
        transacted_unixtime=clock.now().timestamp(),
      ),
    ]

  async def test_prevents_overpromising(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = CreatePredictionOk(any_servicer, alice_token, dict(
        certainty=mvp_pb2.CertaintyRange(low=0.80, high=0.90),
        maximum_stake_cents=100_00,
    ))

    StakeOk(any_servicer, bob_token, mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=True,
      bettor_stake_cents=25_00,
    ))
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'bet would exceed creator tolerance' in str(StakeErr(any_servicer, bob_token, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=1,
      )))

    StakeOk(any_servicer, bob_token, mvp_pb2.StakeRequest(
      prediction_id=prediction_id,
      bettor_is_a_skeptic=False,
      bettor_stake_cents=900_00,
    ))
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
      assert 'bet would exceed creator tolerance' in str(StakeErr(any_servicer, bob_token, mvp_pb2.StakeRequest(
        prediction_id=prediction_id,
        bettor_is_a_skeptic=False,
        bettor_stake_cents=9,
      )))

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, token, {})
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=token):
      assert 'must log in to bet' in str(StakeErr(any_servicer, None, mvp_pb2.StakeRequest(prediction_id=prediction_id)))

  async def test_error_if_creator_doesnt_trust_bettor(self, any_servicer: Servicer):
    creator_token = new_user_token(any_servicer, 'creator')
    prediction_id = CreatePredictionOk(any_servicer, creator_token, {})
    bettor_token = new_user_token(any_servicer, 'bettor')
    SetTrustedOk(any_servicer, bettor_token, creator_token.owner, True)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=creator_token):
      assert "creator doesn\\'t trust you" in str(StakeErr(any_servicer, bettor_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=10)))

  async def test_error_if_bettor_doesnt_trust_creator(self, any_servicer: Servicer):
    creator_token = new_user_token(any_servicer, 'creator')
    prediction_id = CreatePredictionOk(any_servicer, creator_token, {})
    bettor_token = new_user_token(any_servicer, 'bettor')
    SetTrustedOk(any_servicer, creator_token, bettor_token.owner, True)
    with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=creator_token):
      assert "you don\\'t trust the creator" in str(StakeErr(any_servicer, bettor_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_stake_cents=10)))


class TestResolve:

  async def test_happy_path(self, any_servicer: Servicer, clock: MockClock):
    rando_token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, rando_token, {})

    t0 = clock.now().timestamp()
    planned_events = [
      mvp_pb2.ResolutionEvent(unixtime=t0+0, resolution=mvp_pb2.RESOLUTION_YES),
      mvp_pb2.ResolutionEvent(unixtime=t0+1, resolution=mvp_pb2.RESOLUTION_NONE_YET),
      mvp_pb2.ResolutionEvent(unixtime=t0+2, resolution=mvp_pb2.RESOLUTION_NO),
    ]

    assert list(ResolveOk(any_servicer, rando_token, prediction_id, planned_events[0].resolution).resolutions) == planned_events[:1]
    assert list(GetPredictionOk(any_servicer, rando_token, prediction_id).resolutions) == planned_events[:1]

    clock.tick()
    t1 = clock.now().timestamp()
    assert list(ResolveOk(any_servicer, rando_token, prediction_id, planned_events[1].resolution).resolutions) == planned_events[:2]
    assert list(GetPredictionOk(any_servicer, rando_token, prediction_id).resolutions) == planned_events[:2]

    clock.tick()
    t2 = clock.now().timestamp()
    assert list(ResolveOk(any_servicer, rando_token, prediction_id, planned_events[2].resolution).resolutions) == planned_events[:3]
    assert list(GetPredictionOk(any_servicer, rando_token, prediction_id).resolutions) == planned_events

  async def test_error_if_no_such_prediction(self, any_servicer: Servicer):
    rando_token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, rando_token, {})
    assert 'no such prediction' in str(ResolveErr(any_servicer, rando_token, 'not_'+prediction_id, mvp_pb2.RESOLUTION_YES))

  async def test_error_if_notes_too_long(self, any_servicer: Servicer):
    rando_token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, rando_token, {})
    assert 'unreasonably long notes' in str(ResolveErr(any_servicer, rando_token, prediction_id, mvp_pb2.RESOLUTION_YES, notes=99999*'foo'))

  async def test_error_if_invalid_resolution(self, any_servicer: Servicer):
    rando_token = new_user_token(any_servicer, 'rando')
    prediction_id = CreatePredictionOk(any_servicer, rando_token, {})
    bad_resolution_value: mvp_pb2.Resolution.V = 99  # type: ignore
    assert 'unrecognized resolution' in str(ResolveErr(any_servicer, rando_token, prediction_id, bad_resolution_value))

  async def test_error_if_not_creator(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    prediction_id = CreatePredictionOk(any_servicer, alice_token, {})

    for token in [bob_token, new_user_token(any_servicer, 'rando')]:
      with assert_prediction_unchanged(any_servicer, prediction_id=prediction_id, creator_token=alice_token):
        assert 'not the creator' in str(ResolveErr(any_servicer, token, prediction_id, mvp_pb2.RESOLUTION_NO))

  async def test_sends_notifications(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    VerifyEmailOk(any_servicer, token, code)
    assert_oneof(any_servicer.UpdateSettings(token=token, request=mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=mvp_pb2.MaybeBool(value=True))),
      'update_settings_result', 'ok', mvp_pb2.GenericUserInfo)

    prediction_id = CreatePredictionOk(any_servicer, token, dict(prediction='a thing will happen'))
    ResolveOk(any_servicer, token, prediction_id, mvp_pb2.RESOLUTION_YES)
    emailer.send_resolution_notifications.assert_called_once_with(  # type: ignore
      bccs={'nobody@example.com'},
      prediction_id=prediction_id,
      prediction_text='a thing will happen',
      resolution=mvp_pb2.RESOLUTION_YES,
    )


class TestSetTrusted:

  async def test_error_when_logged_out(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    assert 'must log in to trust folks' in str(SetTrustedErr(any_servicer, None, 'rando', True))

  async def test_error_if_nonexistent(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'no such user' in str(SetTrustedErr(any_servicer, token, 'nonexistent', True))

  async def test_error_if_self(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'cannot set trust for self' in str(SetTrustedErr(any_servicer, token, 'rando', True))

  async def test_happy_path(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    new_user_token(any_servicer, 'other')

    alice_view_of_bob = GetUserOk(any_servicer, alice_token, 'Bob')
    assert alice_view_of_bob.trusted_by_you

    SetTrustedOk(any_servicer, alice_token, 'Bob', False)

    alice_view_of_bob = GetUserOk(any_servicer, alice_token, 'Bob')
    assert not alice_view_of_bob.trusted_by_you



class TestGetUser:

  async def test_error_when_nonexistent(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    assert 'no such user' in str(GetUserErr(any_servicer, None, 'nonexistentuser'))

  async def test_success_when_self(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    resp = GetUserOk(any_servicer, token, token.owner)
    assert resp == mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)

  async def test_success_when_friend(self, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    resp = GetUserOk(any_servicer, alice_token, bob_token.owner)
    assert resp == mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)

  async def test_shows_trust_correctly_when_logged_in(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    truster_token = new_user_token(any_servicer, 'truster')
    SetTrustedOk(any_servicer, truster_token, token.owner, True)
    trusted_token = new_user_token(any_servicer, 'trusted')
    SetTrustedOk(any_servicer, token, trusted_token.owner, True)
    resp = GetUserOk(any_servicer, token, truster_token.owner)
    assert resp == mvp_pb2.Relationship(trusted_by_you=False, trusts_you=True)
    resp = GetUserOk(any_servicer, token, trusted_token.owner)
    assert resp == mvp_pb2.Relationship(trusted_by_you=True, trusts_you=False)

  async def test_no_trust_when_logged_out(self, any_servicer: Servicer):
    new_user_token(any_servicer, 'rando')
    resp = GetUserOk(any_servicer, None, 'rando')
    assert resp == mvp_pb2.Relationship(trusted_by_you=False, trusts_you=False)


class TestChangePassword:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    real_token = new_user_token(any_servicer, 'rando')
    with assert_user_unchanged(any_servicer, real_token, 'rando password'):
      assert 'must log in' in str(ChangePasswordErr(any_servicer, None, 'rando password', 'new rando password'))

  async def test_can_log_in_with_new_password(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    ChangePasswordOk(any_servicer, token, 'rando password', 'new rando password')
    assert LogInUsernameOk(any_servicer, None, 'rando', 'new rando password').token.owner == 'rando'

  async def test_error_when_wrong_old_password(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    with assert_user_unchanged(any_servicer, token, 'rando password'):
      assert 'wrong old password' in str(ChangePasswordErr(any_servicer, token, 'WRONG', 'new rando password'))


class TestSetEmail:

  async def test_changes_settings(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    assert GetSettingsOk(any_servicer, token).email.code_sent.email == 'nobody@example.com'

  async def test_returns_new_flow_state(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert SetEmailOk(any_servicer, token, 'nobody@example.com').code_sent.email == 'nobody@example.com'

  async def test_sends_code_in_email(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    emailer.send_email_verification.assert_called_once_with(to='nobody@example.com', code=ANY)  # type: ignore

  async def test_works_in_code_sent_state(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'old@old.old')
    SetEmailOk(any_servicer, token, 'new@new.new')
    assert GetSettingsOk(any_servicer, token).email.code_sent.email == 'new@new.new'
    emailer.send_email_verification.assert_called_with(to='new@new.new', code=ANY)  # type: ignore

  async def test_works_in_verified_state(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'old@old.old')
    code: str = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    VerifyEmailOk(any_servicer, token, code)
    SetEmailOk(any_servicer, token, 'new@new.new')
    assert GetSettingsOk(any_servicer, token).email.code_sent.email == 'new@new.new'
    emailer.send_email_verification.assert_called_with(to='new@new.new', code=ANY)  # type: ignore

  async def test_clears_email_when_address_is_empty(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    emailer.send_email_verification.reset_mock()  # type: ignore
    assert SetEmailOk(any_servicer, token, '').WhichOneof('email_flow_state_kind') == 'unstarted'
    emailer.send_email_verification.assert_not_called()  # type: ignore

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(SetEmailErr(any_servicer, None, 'nobody@example.com'))

  async def test_validates_email(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    for good_email_address in ['a@b', 'b@c.com', 'a.b-c_d+tag@example.com']:
      assert SetEmailOk(any_servicer, token, good_email_address).code_sent.email == good_email_address
    for bad_email_address in ['bad email', 'bad@example.com  ', 'good@example.com, evil@example.com']:
      with assert_user_unchanged(any_servicer, token, 'rando password'):
        assert 'invalid-looking email' in str(SetEmailErr(any_servicer, token, bad_email_address))


class TestVerifyEmail:

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert VerifyEmailOk(any_servicer, token, code=code).verified == 'nobody@example.com'

  async def test_error_if_wrong_code(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    assert 'bad code' in str(VerifyEmailErr(any_servicer, token, code='not ' + code))

  async def test_error_if_unstarted(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert 'no pending email-verification' in str(VerifyEmailErr(any_servicer, token, code='some code'))

  async def test_error_if_restarted(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'old@old.old')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    SetEmailOk(any_servicer, token, 'new@new.new')
    assert 'bad code' in str(VerifyEmailErr(any_servicer, token, code=code))

  async def test_error_if_already_verified(self, emailer: Emailer, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    SetEmailOk(any_servicer, token, 'nobody@example.com')
    code = emailer.send_email_verification.call_args[1]['code']  # type: ignore
    VerifyEmailOk(any_servicer, token, code=code)
    assert 'no pending email-verification' in str(VerifyEmailErr(any_servicer, token, code=code))

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(VerifyEmailErr(any_servicer, None, code='foo'))


class TestGetSettings:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(GetSettingsErr(any_servicer, None))

  async def test_happy_path(self, emailer: Emailer, any_servicer: Servicer):
    alice_token, bob_token = alice_bob_tokens(any_servicer)
    geninfo = GetSettingsOk(any_servicer, alice_token)
    assert dict(geninfo.relationships) == {'Bob': mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)}


class TestUpdateSettings:

  async def test_error_if_logged_out(self, any_servicer: Servicer):
    assert 'must log in' in str(UpdateSettingsErr(any_servicer, None))

  async def test_notification_settings_are_persisted(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert not GetSettingsOk(any_servicer, token).email_resolution_notifications
    UpdateSettingsOk(any_servicer, token, email_resolution_notifications=True)
    assert GetSettingsOk(any_servicer, token).email_resolution_notifications

  async def test_reminder_settings_are_persisted(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    assert not GetSettingsOk(any_servicer, token).email_reminders_to_resolve
    UpdateSettingsOk(any_servicer, token, email_reminders_to_resolve=True)
    assert GetSettingsOk(any_servicer, token).email_reminders_to_resolve

  async def test_response_has_new_settings(self, any_servicer: Servicer):
    token = new_user_token(any_servicer, 'rando')
    resp = UpdateSettingsOk(any_servicer, token, email_reminders_to_resolve=True)
    assert resp == GetSettingsOk(any_servicer, token)
