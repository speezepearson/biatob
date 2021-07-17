import datetime
import json

from sqlalchemy.sql.ddl import CreateSchema
from server.core import PredictionId
from server.test_sql_conn import ALICE, BOB
from server.protobuf import mvp_pb2
from unittest import mock
from unittest.mock import Mock

import sqlalchemy

from .emailer import Emailer
from .sql_servicer import SqlConn, find_invariant_violations, _backup_text, SqlServicer, TokenMint, email_resolution_reminders
from . import sql_schema as schema
from .test_utils import emailer, some_create_prediction_request, sqlite_engine

class TestFindInvariantViolations:
  def test_initially_empty(self, sqlite_engine: sqlalchemy.engine.Engine):
    with sqlite_engine.connect() as raw_conn:
      assert find_invariant_violations(raw_conn) == []

  def test_detects_overpromising(self, sqlite_engine: sqlalchemy.engine.Engine):
    with sqlite_engine.connect() as raw_conn:
      now = datetime.datetime(2020, 1, 1, 0, 0, 0)
      conn = SqlConn(raw_conn)
      conn.register_username(ALICE, 'secret', 'alice_pwid')
      conn.register_username(BOB, 'secret', 'bob_pwid')
      predid = PredictionId('my_pred')
      conn.create_prediction(now, predid, ALICE, some_create_prediction_request(
        maximum_stake_cents=100,
        certainty=mvp_pb2.CertaintyRange(low=0.5, high=1.0),
      ))
      conn.stake(predid, BOB, True, 80, creator_stake_cents=80, state=mvp_pb2.TRADE_STATE_ACTIVE, now=now)
      conn.stake(predid, BOB, True, 70, creator_stake_cents=70, state=mvp_pb2.TRADE_STATE_ACTIVE, now=now+datetime.timedelta(seconds=1))

      assert find_invariant_violations(raw_conn) == [{
        'type': 'exposure exceeded',
        'prediction_id': predid,
        'maximum_stake_cents': 100,
        'actual_exposure': 150,
      }]

def test_backup_text(sqlite_engine: sqlalchemy.engine.Engine):
  with sqlite_engine.connect() as conn:
    j = json.loads(_backup_text(conn))
    assert 'users' in j
    assert 'predictions' in j

    conn.execute(sqlalchemy.insert(schema.passwords).values(password_id='pw', salt=b'abc', scrypt=b'def'))
    conn.execute(sqlalchemy.insert(schema.users).values(username='a', login_password_id='pw', email_flow_state=b'\x00foo\xffbar'))
    j = json.loads(_backup_text(conn))
    assert any(
      row['username'] == 'a'
      and row['login_password_id'] == 'pw'
      and row['email_flow_state'] == {'__type__': str(bytes), '__repr__': repr(b'\x00foo\xffbar')}
      for row in j['users']
    )

async def test_email_resolution_reminders_sends_all_emails(emailer: Emailer):
  conn = mock.Mock()
  conn.get_predictions_needing_resolution_reminders.return_value = [
    {'prediction_id': 12, 'prediction_text': 'prediction 12', 'email_address': 'pred12@example.com'},
    {'prediction_id': 34, 'prediction_text': 'prediction 34', 'email_address': 'pred34@example.com'},
  ]
  await email_resolution_reminders(conn=conn, emailer=emailer, now=datetime.datetime.now())
  emailer.send_resolution_reminder.assert_has_calls([  # type: ignore
    mock.call(prediction_id=12, prediction_text='prediction 12', to='pred12@example.com'),
    mock.call(prediction_id=34, prediction_text='prediction 34', to='pred34@example.com'),
  ])
