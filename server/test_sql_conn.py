import datetime
from typing import Iterable, Optional, TypeVar

import pytest
import sqlalchemy

from .core import UsernameAlreadyRegisteredError, Username, PredictionId
from .sql_servicer import SqlConn
from .protobuf import mvp_pb2
from .test_utils import au, some_create_prediction_request, sqlite_engine

@pytest.fixture
def conn(sqlite_engine: sqlalchemy.engine.Engine):
  return SqlConn(conn=sqlite_engine.connect())

def create_user(
  conn: SqlConn,
  username: Username,
  email_address: Optional[str] = None,
  email_resolution_notifications: Optional[bool] = None,
  email_reminders_to_resolve: Optional[bool] = None,
) -> None:
  conn.register_username(username, 'password', password_id=f'{username} pwid')
  if email_address:
    conn.set_email(username, mvp_pb2.EmailFlowState(verified=email_address))
  if email_resolution_notifications is not None:
    conn.update_settings(username, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=mvp_pb2.MaybeBool(value=email_resolution_notifications)))
  if email_reminders_to_resolve is not None:
    conn.update_settings(username, mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=email_reminders_to_resolve)))

ALICE = Username('alice')
BOB = Username('bob')
CHARLIE = Username('charlie')
DOLORES = Username('dolores')

PRED_ID = PredictionId('my_pred_id')

T0 = datetime.datetime(2020, 1, 1, 0, 0, 0)
T1 = T0 + datetime.timedelta(hours=1)
T2 = T1 + datetime.timedelta(hours=1)
T3 = T2 + datetime.timedelta(hours=1)
T4 = T3 + datetime.timedelta(hours=1)

def test_enforces_foreign_keys(conn: SqlConn):
  with pytest.raises(sqlalchemy.exc.IntegrityError):
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request())

class TestRegisterUsername:
  def test_user_exists_after(self, conn: SqlConn):
    assert not conn.user_exists(ALICE)
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    assert conn.user_exists(ALICE)

  def test_no_double_registration(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    with pytest.raises(UsernameAlreadyRegisteredError):
      conn.register_username(ALICE, 'password', password_id='alicepwid')


class TestTrust:
  def test_initially_no_trust_until_set_trust(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    assert not conn.trusts(ALICE, BOB)

  def test_trust_follows_last_set_trust(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, True, now=T0)
    assert conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, True, now=T0)
    assert conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, False, now=T0)
    assert not conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, False, now=T0)
    assert not conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, True, now=T0)
    assert conn.trusts(ALICE, BOB)

  def test_trust_is_only_one_way(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, True, now=T0)
    assert conn.trusts(ALICE, BOB)
    assert not conn.trusts(BOB, ALICE)

  def test_false_if_either_user_nonexistent(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    assert not conn.trusts(ALICE, BOB)
    assert not conn.trusts(BOB, ALICE)
    assert not conn.trusts(BOB, Username('charlie'))

  def test_everyone_trusts_self(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    assert conn.trusts(ALICE, ALICE)


_T = TypeVar('_T')
def must(x: Optional[_T]) -> _T:
  assert x
  return x

class TestSettings:
  def test_get_settings_includes_trusted_users(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, True, now=T0)
    assert must(conn.get_settings(au(ALICE))).relationships == {BOB: mvp_pb2.Relationship(trusted_by_you=True)}

  def test_get_settings_includes_mutually_trusting_users(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, True, now=T0)
    conn.set_trusted(BOB, ALICE, True, now=T0)
    assert must(conn.get_settings(au(ALICE))).relationships == {BOB: mvp_pb2.Relationship(trusted_by_you=True, trusts_you=True)}

  def test_get_settings_includes_explicitly_untrusted_users(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, False, now=T0)
    assert must(conn.get_settings(au(ALICE))).relationships == {BOB: mvp_pb2.Relationship(trusted_by_you=False)}

  @pytest.mark.parametrize('a_trusts_b', [True, False])
  @pytest.mark.parametrize('b_trusts_a', [True, False, None])
  def test_get_settings_reports_trust_correctly(self, conn: SqlConn, a_trusts_b: bool, b_trusts_a: Optional[bool]):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, a_trusts_b, now=T0)
    if b_trusts_a is not None:
      conn.set_trusted(BOB, ALICE, b_trusts_a, now=T0)
    assert must(conn.get_settings(au(ALICE))).relationships == {BOB: mvp_pb2.Relationship(trusted_by_you=a_trusts_b or False, trusts_you=b_trusts_a or False)}

  @pytest.mark.parametrize('b_trusts_a', [True, False, None])
  def test_get_settings_ignores_unacknowledged_users(self, conn: SqlConn, b_trusts_a: Optional[bool]):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    if b_trusts_a is not None:
      conn.set_trusted(BOB, ALICE, b_trusts_a, now=T0)
    assert must(conn.get_settings(au(ALICE))).relationships == {}

  @pytest.mark.parametrize('b_trusts_a', [True, False, None])
  def test_get_settings_includes_unacknowledged_users_if_explicitly_requested(self, conn: SqlConn, b_trusts_a: Optional[bool]):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    if b_trusts_a is not None:
      conn.set_trusted(BOB, ALICE, b_trusts_a, now=T0)
    assert must(conn.get_settings(au(ALICE), include_relationships_with_users=[BOB])).relationships == {BOB: mvp_pb2.Relationship(trusts_you=b_trusts_a or False)}

  def test_persists_updated_settings(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.update_settings(ALICE, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=mvp_pb2.MaybeBool(value=True)))
    assert must(conn.get_settings(au(ALICE))).email_resolution_notifications

  def test_persists_set_email(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    efs = mvp_pb2.EmailFlowState(verified='a@a')
    conn.set_email(ALICE, efs)
    assert must(conn.get_settings(au(ALICE))).email == efs



class TestInvitations:
  def test_accept_returns_params_from_create(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.create_invitation('mynonce', inviter=ALICE, recipient=BOB)
    assert conn.accept_invitation('mynonce', now=T0) == mvp_pb2.CheckInvitationResponse.Result(inviter=ALICE, recipient=BOB)

  def test_returns_none_if_no_such_invitation(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.create_invitation('one nonce', inviter=ALICE, recipient=BOB)
    assert conn.accept_invitation('some other nonce', now=T0) is None


class TestPredictions:
  def test_view_contains_all_creation_fields(self, conn: SqlConn):
    predid = PredictionId(PRED_ID)
    conn.register_username(ALICE, 'password', password_id='alicepwid')

    conn.create_prediction(now=T0, prediction_id=predid, creator=ALICE, request=mvp_pb2.CreatePredictionRequest(
      prediction='a thing will happen',
      certainty=mvp_pb2.CertaintyRange(low=0.25, high=0.75),
      maximum_stake_cents=100,
      open_seconds=86400,
      special_rules='my rules',
      resolves_at_unixtime=T1.timestamp(),
    ))
    assert conn.view_prediction(viewer=ALICE, prediction_id=predid) == mvp_pb2.UserPredictionView(
      prediction='a thing will happen',
      certainty=mvp_pb2.CertaintyRange(low=0.25, high=0.75),
      maximum_stake_cents=100,
      remaining_stake_cents_vs_believers=100,
      remaining_stake_cents_vs_skeptics=100,
      created_unixtime=T0.timestamp(),
      closes_unixtime=T0.timestamp() + 86400,
      special_rules='my rules',
      creator=ALICE,
      resolves_at_unixtime=T1.timestamp(),
    )

  def test_stake_errors_on_nonexistent_prediction(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    with pytest.raises(sqlalchemy.exc.IntegrityError):
      conn.stake(
        prediction_id=PredictionId(PRED_ID),
        bettor=ALICE,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=1,
        creator_stake_cents=1,
        state=mvp_pb2.TRADE_STATE_ACTIVE,
        now=T0,
      )

class TestResolutionNotifications:
  @pytest.mark.parametrize('efs,wants_notifs,expect_email', [
    (mvp_pb2.EmailFlowState(unstarted=mvp_pb2.VOID), True, False),
    (mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email='bob@example.com')), True, False),
    (mvp_pb2.EmailFlowState(verified='bob@example.com'), True, True),
    (mvp_pb2.EmailFlowState(verified='bob@example.com'), False, False),
  ])
  def test_emails_bettors_with_verified_email_and_setting_enabled(self, conn: SqlConn, efs: mvp_pb2.EmailFlowState, wants_notifs: bool, expect_email: bool):
    conn.register_username(ALICE, 'password', password_id='alicepwid')

    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_email(BOB, efs)
    conn.update_settings(BOB, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=mvp_pb2.MaybeBool(value=wants_notifs)))

    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request())
    conn.stake(prediction_id=PRED_ID, bettor=BOB, bettor_is_a_skeptic=True, bettor_stake_cents=1, creator_stake_cents=1, state=mvp_pb2.TRADE_STATE_ACTIVE, now=T0)

    expected_emails = {efs.verified} if expect_email else set()
    assert set(conn.get_resolution_notification_addrs(PRED_ID)) == expected_emails

  def test_does_not_email_creator(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.set_email(ALICE, mvp_pb2.EmailFlowState(verified='alice@example.com'))
    conn.update_settings(ALICE, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=mvp_pb2.MaybeBool(value=True)))
    conn.register_username(BOB, 'password', password_id='bobpwid')

    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request())
    conn.stake(prediction_id=PRED_ID, bettor=BOB, bettor_is_a_skeptic=True, bettor_stake_cents=1, creator_stake_cents=1, state=mvp_pb2.TRADE_STATE_ACTIVE, now=T0)

    assert not conn.get_resolution_notification_addrs(PRED_ID)

  def test_ignores_unrelated_predictions(self, conn: SqlConn):
    for user in [ALICE, BOB, CHARLIE, DOLORES]:
      create_user(conn, user, email_address=f'{user}@example.com', email_resolution_notifications=True)

    for creator, bettor, predid in [(ALICE, BOB, '123'), (BOB, CHARLIE, '234'), (ALICE, DOLORES, '345'), (CHARLIE, DOLORES, '456')]:
      conn.create_prediction(now=T0, prediction_id=PredictionId(predid), creator=creator, request=some_create_prediction_request())
      conn.stake(prediction_id=PredictionId(predid), bettor=bettor, bettor_is_a_skeptic=True, bettor_stake_cents=1, creator_stake_cents=1, state=mvp_pb2.TRADE_STATE_ACTIVE, now=T0)

    assert set(conn.get_resolution_notification_addrs(PredictionId('456'))) == {'dolores@example.com'}

class TestResolutionReminders:
  def test_requires_email(self, conn: SqlConn):
    create_user(conn, ALICE, email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []
    conn.set_email(ALICE, mvp_pb2.EmailFlowState(verified='alice@example.com'))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == [PRED_ID]

  def test_requires_preferences(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com')
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    conn.update_settings(ALICE, mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=False)))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []
    conn.update_settings(ALICE, mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=True)))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == [PRED_ID]

  def test_requires_resolves_at_is_in_past(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T2.timestamp()))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T1)] == []
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T3)] == [PRED_ID]

  def test_requires_prediction_is_unresolved(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == [PRED_ID]
    conn.resolve(now=T1, request=mvp_pb2.ResolveRequest(prediction_id=PRED_ID, resolution=mvp_pb2.RESOLUTION_YES))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []

  def test_catches_flipflop_unresolved_predictions(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    conn.resolve(now=T1, request=mvp_pb2.ResolveRequest(prediction_id=PRED_ID, resolution=mvp_pb2.RESOLUTION_YES))
    conn.resolve(now=T2, request=mvp_pb2.ResolveRequest(prediction_id=PRED_ID, resolution=mvp_pb2.RESOLUTION_NONE_YET))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T3)] == [PRED_ID]

  def test_ignores_flipflop_resolved_predictions(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    conn.resolve(now=T1, request=mvp_pb2.ResolveRequest(prediction_id=PRED_ID, resolution=mvp_pb2.RESOLUTION_YES))
    conn.resolve(now=T2, request=mvp_pb2.ResolveRequest(prediction_id=PRED_ID, resolution=mvp_pb2.RESOLUTION_NONE_YET))
    conn.resolve(now=T3, request=mvp_pb2.ResolveRequest(prediction_id=PRED_ID, resolution=mvp_pb2.RESOLUTION_YES))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T4)] == []

  def test_skips_previously_reminded(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PRED_ID, creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    conn.mark_resolution_reminder_sent(prediction_id=PRED_ID)
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []
