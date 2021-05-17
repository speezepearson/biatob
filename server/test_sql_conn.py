import datetime
from typing import Iterable, Optional

import pytest
import sqlalchemy

from .core import UsernameAlreadyRegisteredError, Username, PredictionId
from .sql_servicer import SqlConn
from .sql_schema import create_sqlite_engine
from .protobuf import mvp_pb2
from .test_utils import some_create_prediction_request

@pytest.fixture
def conn():
  return SqlConn(conn=create_sqlite_engine(':memory:'))

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

T0 = datetime.datetime(2020, 1, 1, 0, 0, 0)
T1 = datetime.datetime(2020, 1, 2, 0, 0, 0)
T2 = datetime.datetime(2020, 1, 3, 0, 0, 0)
T3 = datetime.datetime(2020, 1, 4, 0, 0, 0)

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
    conn.set_trusted(ALICE, BOB, True)
    assert conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, True)
    assert conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, False)
    assert not conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, False)
    assert not conn.trusts(ALICE, BOB)
    conn.set_trusted(ALICE, BOB, True)
    assert conn.trusts(ALICE, BOB)

  def test_trust_is_only_one_way(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.set_trusted(ALICE, BOB, True)
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


class TestInvitations:
  def test_invitation_is_open_between_create_and_accept(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')

    assert not conn.is_invitation_open(nonce='mynonce')
    conn.create_invitation(nonce='mynonce', inviter=ALICE, now=T0, notes='')
    assert conn.is_invitation_open(nonce='mynonce')
    conn.accept_invitation(nonce='mynonce', accepter=BOB, now=T1)
    assert not conn.is_invitation_open(nonce='mynonce')

  def test_no_accepting_closed_invitation(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.register_username(BOB, 'password', password_id='bobpwid')

    with pytest.raises(sqlalchemy.exc.IntegrityError):
      conn.accept_invitation(nonce='mynonce', accepter=BOB, now=T1)

    conn.create_invitation(nonce='mynonce', inviter=ALICE, now=T0, notes='')
    conn.accept_invitation(nonce='mynonce', accepter=BOB, now=T1)

    with pytest.raises(sqlalchemy.exc.IntegrityError):
      conn.accept_invitation(nonce='mynonce', accepter=BOB, now=T1)

class TestPredictions:
  def test_view_contains_all_creation_fields(self, conn: SqlConn):
    predid = PredictionId(123)
    conn.register_username(ALICE, 'password', password_id='alicepwid')

    conn.create_prediction(now=T0, prediction_id=predid, creator=ALICE, request=mvp_pb2.CreatePredictionRequest(
      prediction='a thing will happen',
      certainty=mvp_pb2.CertaintyRange(low=0.25, high=0.75),
      maximum_stake_cents=100,
      open_seconds=86400,
      special_rules='my rules',
      resolves_at_unixtime=100000,
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
      creator=mvp_pb2.UserUserView(username=ALICE, is_trusted=True, trusts_you=True),
      resolves_at_unixtime=100000,
    )

  def test_stake_errors_on_nonexistent_prediction(self, conn: SqlConn):
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    with pytest.raises(sqlalchemy.exc.IntegrityError):
      conn.stake(
        prediction_id=PredictionId(123),
        bettor=ALICE,
        bettor_is_a_skeptic=True,
        bettor_stake_cents=1,
        creator_stake_cents=1,
        now=T0,
      )

class TestEmails:
  @pytest.mark.parametrize("user", [ALICE, BOB])
  @pytest.mark.parametrize("efs,want_notifs,expected_addrs", [
    (mvp_pb2.EmailFlowState(verified='somebody@example.com'), True, ['somebody@example.com']),
    (mvp_pb2.EmailFlowState(verified='somebody@example.com'), False, []),
    (mvp_pb2.EmailFlowState(unstarted=mvp_pb2.VOID), True, []),
    (mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email='somebody@example.com', code=mvp_pb2.HashedPassword(salt=b'', scrypt=b''))), True, []),
  ])
  def test_get_resolution_notification_addrs_includes_creator_and_bettors_whose_user_settings_permit(
    self,
    conn: SqlConn,
    user: Username,
    efs: mvp_pb2.EmailFlowState,
    want_notifs: bool,
    expected_addrs: Iterable[str],
  ):
    prediction_id = PredictionId(456)
    conn.register_username(ALICE, 'password', password_id='alicepwid')
    conn.create_prediction(now=T0, prediction_id=prediction_id, creator=ALICE, request=some_create_prediction_request())

    conn.register_username(BOB, 'password', password_id='bobpwid')
    conn.stake(prediction_id=prediction_id, bettor=BOB, bettor_is_a_skeptic=True, bettor_stake_cents=1, creator_stake_cents=1, now=T0)

    conn.set_email(user, efs)
    conn.update_settings(user, mvp_pb2.UpdateSettingsRequest(email_resolution_notifications=mvp_pb2.MaybeBool(value=want_notifs)))
    assert set(conn.get_resolution_notification_addrs(prediction_id)) == set(expected_addrs)

  def test_get_resolution_notification_addrs_ignores_unrelated_predictions(self, conn: SqlConn):
    for creator, bettor, predid in [(ALICE, BOB, 123), (CHARLIE, DOLORES, 456)]:
      create_user(conn, creator, email_address=f'{creator}@example.com', email_resolution_notifications=True)
      create_user(conn, bettor, email_address=f'{bettor}@example.com', email_resolution_notifications=True)
      conn.create_prediction(now=T0, prediction_id=PredictionId(predid), creator=creator, request=some_create_prediction_request())
      conn.stake(prediction_id=PredictionId(predid), bettor=bettor, bettor_is_a_skeptic=True, bettor_stake_cents=1, creator_stake_cents=1, now=T0)

    assert set(conn.get_resolution_notification_addrs(PredictionId(456))) == {'charlie@example.com', 'dolores@example.com'}

  def test_get_predictions_needing_resolution_reminders_requires_email(self, conn: SqlConn):
    create_user(conn, ALICE, email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PredictionId(456), creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []
    conn.set_email(ALICE, mvp_pb2.EmailFlowState(verified='alice@example.com'))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == [456]

  def test_get_predictions_needing_resolution_reminders_requires_preferences(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com')
    conn.create_prediction(now=T0, prediction_id=PredictionId(456), creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=1))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T1)] == []
    conn.update_settings(ALICE, mvp_pb2.UpdateSettingsRequest(email_reminders_to_resolve=mvp_pb2.MaybeBool(value=True)))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T1)] == [456]

  def test_get_predictions_needing_resolution_reminders_requires_resolves_at_is_in_past(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    resolves_at = 50
    conn.create_prediction(now=T0, prediction_id=PredictionId(456), creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T2.timestamp()))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T1)] == []
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T3)] == [456]

  def test_get_predictions_needing_resolution_reminders_requires_prediction_is_unresolved(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PredictionId(456), creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == [456]
    conn.resolve(now=T1, request=mvp_pb2.ResolveRequest(prediction_id=456, resolution=mvp_pb2.RESOLUTION_YES))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []

  def test_get_predictions_needing_resolution_reminders_catches_flipflop_unresolved_predictions(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PredictionId(456), creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    conn.resolve(now=T1, request=mvp_pb2.ResolveRequest(prediction_id=456, resolution=mvp_pb2.RESOLUTION_YES))
    conn.resolve(now=T2, request=mvp_pb2.ResolveRequest(prediction_id=456, resolution=mvp_pb2.RESOLUTION_NONE_YET))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T3)] == [456]

  def test_get_predictions_needing_resolution_reminders_skips_previously_reminded(self, conn: SqlConn):
    create_user(conn, ALICE, email_address='alice@example.com', email_reminders_to_resolve=True)
    conn.create_prediction(now=T0, prediction_id=PredictionId(456), creator=ALICE, request=some_create_prediction_request(resolves_at_unixtime=T1.timestamp()))
    conn.mark_resolution_reminder_sent(prediction_id=PredictionId(456))
    assert [r['prediction_id'] for r in conn.get_predictions_needing_resolution_reminders(now=T2)] == []