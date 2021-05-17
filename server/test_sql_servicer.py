import datetime
import json
from unittest import mock
from unittest.mock import Mock

import sqlalchemy

from .emailer import Emailer
from .sql_servicer import SqlConn, find_invariant_violations, _backup_text, SqlServicer, TokenMint, email_resolution_reminders
from . import sql_schema as schema
from .test_utils import emailer

# TODO: update this function to take a SqlConn instead
#def test_find_invariant_violations():
#  engine = schema.create_sqlite_engine(':memory:')
#  with engine.connect() as conn:
#    assert find_invariant_violations(conn) == []
#
#    conn.execute(sqlalchemy.insert(schema.predictions).values(
#      prediction_id=1,
#      prediction='a',
#      certainty_low_p=0.4,
#      certainty_high_p=0.6,
#      maximum_stake_cents=100,
#      created_at_unixtime=1,
#      closes_at_unixtime=3,
#      resolves_at_unixtime=4,
#      special_rules='',
#      creator='creator',
#    ))
#    assert find_invariant_violations(conn) == []
#
#    conn.execute(sqlalchemy.insert(schema.trades).values(prediction_id=1, bettor='bettor', transacted_at_unixtime=2, bettor_stake_cents=120, creator_stake_cents=200, bettor_is_a_skeptic=False))
#    assert find_invariant_violations(conn) == [{'type': 'exposure exceeded', 'prediction_id': 1, 'actual_exposure': 200, 'maximum_stake_cents': 100}]

def test_backup_text():
  engine = schema.create_sqlite_engine(':memory:')
  with engine.connect() as conn:
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
