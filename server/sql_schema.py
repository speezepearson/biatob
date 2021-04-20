from sqlalchemy import create_engine, MetaData, Table, Column, Integer, String, BOOLEAN, ForeignKey, BINARY, select, insert, values, Index, REAL, CheckConstraint
import sqlalchemy

metadata = MetaData()

users = Table(
  "users",
  metadata,
  Column('username', String(64), primary_key=True, nullable=False),
  Column('email_reminders_to_resolve', BOOLEAN(), nullable=False, default=False),
  Column('email_resolution_notifications', BOOLEAN(), nullable=False, default=False),
  Column('login_password_id', ForeignKey('passwords.login_password_id'), nullable=False),  # will be nullable someday, if we add OAuth or something
)

passwords = Table(
  "passwords",
  metadata,
  Column('login_password_id', String(64), primary_key=True, nullable=False),
  Column('salt', BINARY(), nullable=False),
  Column('scrypt', BINARY(), nullable=False),
)

relationships = Table(
  'relationships',
  metadata,
  Column('subject_username', ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('object_username', ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('trusted', BOOLEAN(), nullable=False, default=False),
)
Index('relationships_by_subject_username', relationships.c.subject_username)
Index('relationships_by_object_username', relationships.c.object_username)

side_payments = Table(
  'side_payments',
  metadata,
  Column('from_username', ForeignKey('users.username'), nullable=False),
  Column('to_username', ForeignKey('users.username'), nullable=False),
  Column('sent_at_unixtime', REAL(), nullable=False),
  Column('cents', Integer(), nullable=False),
  Column('certified_by_sender', BOOLEAN(), default=0),
  Column('certified_by_recipient', BOOLEAN(), default=0),
)
Index('side_payments_by_from_username', side_payments.c.from_username)
Index('side_payments_by_to_username', side_payments.c.to_username)
Index('side_payments_by_pair', side_payments.c.from_username, side_payments.c.to_username)

predictions = Table(
  'predictions',
  metadata,
  Column('prediction_id', Integer(), primary_key=True, nullable=False),
  Column('prediction', String(1024), CheckConstraint('LENGTH(prediction) > 0'), nullable=False),
  Column('certainty_low_p', REAL(), nullable=False),
  Column('certainty_high_p', REAL(), nullable=False),
  Column('maximum_stake_cents', Integer(), nullable=False),
  Column('created_at_unixtime', REAL(), nullable=False),
  Column('closes_at_unixtime', REAL(), nullable=False),
  Column('resolves_at_unixtime', REAL(), nullable=False),
  Column('special_rules', String(65535), nullable=False),
  Column('creator', ForeignKey('users.username'), nullable=False),
)

trades = Table(
  'trades',
  metadata,
  Column('prediction_id', ForeignKey('predictions.prediction_id'), nullable=False),
  Column('bettor', ForeignKey('users.username'), nullable=False),
  Column('bettor_is_a_skeptic', BOOLEAN(), nullable=False),
  Column('bettor_stake_cents', Integer(), nullable=False),
  Column('creator_stake_cents', Integer(), nullable=False),
  Column('transacted_at_unixtime', REAL(), nullable=False)
)
Index('trades_by_prediction_id', trades.c.prediction_id)
Index('trades_by_bettor', trades.c.bettor)

resolutions = Table(
  'resolutions',
  metadata,
  Column('prediction_id', ForeignKey('predictions.prediction_id'), nullable=False),
  Column('resolution', String(64), CheckConstraint("resolution IN ('RESOLUTION_NONE_YET', 'RESOLUTION_YES', 'RESOLUTION_NO', 'RESOLUTION_INVALID')"), nullable=False),
  Column('resolved_at_unixtime', REAL(), nullable=False),
  Column('notes', String(65535), nullable=False, default=''),
)
Index('resolutions_by_prediction_id', resolutions.c.prediction_id)

email_attempts = Table(
  'email_attempts',
  metadata,
  Column('email_id', String(64), nullable=False),
  Column('sent_at_unixtime', REAL(), nullable=False),
  Column('succeeded', BOOLEAN()),
)
Index('email_attempts_by_email_id', email_attempts.c.email_id)


invitations = Table(
  'invitations',
  metadata,
  Column('nonce', String(64), primary_key=True, nullable=False),
  Column('inviter', ForeignKey('users.username'), nullable=False),
  Column('created_at_unixtime', REAL(), nullable=False),
  Column('notes', String(65535), nullable=False, default=''),
)
Index('invitations_by_inviter', invitations.c.inviter)

invitation_acceptances = Table(
  'invitation_acceptances',
  metadata,
  Column('invitation_nonce', ForeignKey('invitations.nonce'), primary_key=True, nullable=False),
  Column('accepted_at_unixtime', REAL(), nullable=False),
  Column('accepted_by', ForeignKey('users.username'), nullable=False),
)



if __name__ == '__main__':
  
  # Adapted from https://docs.sqlalchemy.org/en/14/dialects/sqlite.html#foreign-key-support
  from sqlalchemy.engine import Engine
  from sqlalchemy import event
  @event.listens_for(Engine, "connect")
  def set_sqlite_pragma(dbapi_connection, connection_record):
      cursor = dbapi_connection.cursor()
      cursor.execute("PRAGMA foreign_keys=ON")
      cursor.close()

  import autopsy; autopsy.activate()
  from .sql_servicer import *
  from unittest.mock import Mock
  from .protobuf import mvp_pb2
  engine = create_engine('sqlite+pysqlite:///:memory:')
  metadata.create_all(engine)
  with engine.connect() as conn:
    mint = TokenMint(secret_key=b'123')
    servicer = SqlServicer(
      conn=conn,
      token_mint=mint,
      emailer=Mock(),
      random_seed=0,
    )
    print('invalid login')
    servicer.LogInUsername(None, mvp_pb2.LogInUsernameRequest(username='foo', password='bar'))
    print('registering user')
    token = servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='foo', password='bar')).ok.token
    print('creating prediction')
    prediction_id = servicer.CreatePrediction(token, mvp_pb2.CreatePredictionRequest(
      prediction='a thing will happen',
      certainty=mvp_pb2.CertaintyRange(low=0.4, high=0.6),
      maximum_stake_cents=123,
      open_seconds=456,
      special_rules='my special rules',
      resolves_at_unixtime=int(2e9),
    )).new_prediction_id
    print('getting as creator')
    print(servicer.GetPrediction(token, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)))
    print('getting as nobody')
    print(servicer.GetPrediction(None, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id)))

    other_token = servicer.RegisterUsername(None, mvp_pb2.RegisterUsernameRequest(username='bob', password='bob')).ok.token
    print(servicer.Stake(other_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=30)))
    
    assert servicer.SetTrusted(token, mvp_pb2.SetTrustedRequest(who=other_token.owner, trusted=True)).WhichOneof('set_trusted_result') == 'ok'
    assert servicer.SetTrusted(other_token, mvp_pb2.SetTrustedRequest(who=token.owner, trusted=True)).WhichOneof('set_trusted_result') == 'ok'

    print(servicer.Stake(other_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=30)))

    print(servicer.Stake(other_token, mvp_pb2.StakeRequest(prediction_id=prediction_id, bettor_is_a_skeptic=True, bettor_stake_cents=3000)))
