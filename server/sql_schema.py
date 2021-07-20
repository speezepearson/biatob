from sqlalchemy.sql.sqltypes import VARBINARY
from server.protobuf import mvp_pb2
from sqlalchemy import event
from sqlalchemy import MetaData, Table, Column, Integer, String, BOOLEAN, ForeignKey, BINARY, Index, REAL, CheckConstraint, VARBINARY, BLOB, TEXT
import sqlalchemy

metadata = MetaData()

pwid_t = String(64)
username_t = String(64)
predid_t = String(64)

passwords = Table(
  'passwords',
  metadata,
  Column('password_id', pwid_t, primary_key=True, nullable=False),
  Column('salt', VARBINARY(255), nullable=False),
  Column('scrypt', VARBINARY(255), nullable=False),
)

users = Table(
    'users',
    metadata,
    Column('username', username_t, primary_key=True, nullable=False),
    Column('email_reminders_to_resolve', BOOLEAN(), nullable=False, server_default=sqlalchemy.text('TRUE')),
    Column('email_resolution_notifications', BOOLEAN(), nullable=False, server_default=sqlalchemy.text('TRUE')),
    Column('allow_email_invitations', BOOLEAN(), nullable=False, server_default=sqlalchemy.text('TRUE')),
    Column('email_invitation_acceptance_notifications', BOOLEAN(), nullable=False, server_default=sqlalchemy.text('TRUE')),
    Column('login_password_id', pwid_t, ForeignKey('passwords.password_id'), nullable=False),  # will be nullable someday, if we add OAuth or something
    Column('email_flow_state', BLOB(), nullable=False),
)

relationships = Table(
  'relationships',
  metadata,
  Column('subject_username', username_t, ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('object_username', username_t, ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('trusted', BOOLEAN(), nullable=False, server_default=sqlalchemy.text('FALSE')),
)
Index('relationships_by_subject_username', relationships.c.subject_username)
Index('relationships_by_object_username', relationships.c.object_username)

predictions = Table(
  'predictions',
  metadata,
  Column('prediction_id', predid_t, primary_key=True, nullable=False),
  Column('prediction', String(1024), CheckConstraint('LENGTH(prediction) > 0'), nullable=False),
  Column('certainty_low_p', REAL(), CheckConstraint('0 < certainty_low_p AND certainty_low_p < 1'), nullable=False),
  Column('certainty_high_p', REAL(), CheckConstraint('certainty_low_p <= certainty_high_p AND certainty_high_p <= 1'), nullable=False),
  Column('maximum_stake_cents', Integer(), CheckConstraint('maximum_stake_cents > 0'), nullable=False),
  Column('created_at_unixtime', REAL(), nullable=False),
  Column('closes_at_unixtime', REAL(), CheckConstraint('closes_at_unixtime > created_at_unixtime'), nullable=False),
  Column('resolves_at_unixtime', REAL(), CheckConstraint('resolves_at_unixtime > created_at_unixtime'), nullable=False),
  Column('special_rules', TEXT(), nullable=False),
  Column('creator', username_t, ForeignKey('users.username'), nullable=False),
  Column('resolution_reminder_sent', BOOLEAN(), nullable=False, server_default=sqlalchemy.text('FALSE')),
  Column('view_privacy', String(96), CheckConstraint("view_privacy in ('PREDICTION_VIEW_PRIVACY_ANYBODY', 'PREDICTION_VIEW_PRIVACY_ANYBODY_WITH_THE_LINK')"), nullable=False, server_default='PREDICTION_VIEW_PRIVACY_ANYBODY'),
)

trades = Table(
  'trades',
  metadata,
  Column('prediction_id', predid_t, ForeignKey('predictions.prediction_id'), primary_key=True, nullable=False),
  Column('bettor', username_t, ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('transacted_at_unixtime', REAL(), primary_key=True, nullable=False),
  Column('bettor_is_a_skeptic', BOOLEAN(), nullable=False),
  Column('bettor_stake_cents', Integer(), CheckConstraint('bettor_stake_cents > 0'), nullable=False),
  Column('creator_stake_cents', Integer(), CheckConstraint('creator_stake_cents > 0'), nullable=False),
  Column('state', String(64), CheckConstraint("state in ('TRADE_STATE_ACTIVE', 'TRADE_STATE_DEQUEUE_FAILED', 'TRADE_STATE_DISAVOWED', 'TRADE_STATE_QUEUED')"), nullable=False),
  Column('updated_at_unixtime', REAL(), nullable=False),
  Column('notes', TEXT(), nullable=False, server_default=sqlalchemy.text("''")),
)
Index('trades_by_prediction_id', trades.c.prediction_id)
Index('trades_by_bettor', trades.c.bettor)

resolutions = Table(
  'resolutions',
  metadata,
  Column('prediction_id', predid_t, ForeignKey('predictions.prediction_id'), primary_key=True, nullable=False),
  Column('resolved_at_unixtime', REAL(), primary_key=True, nullable=False),
  Column('resolution', String(64), CheckConstraint("resolution IN ('RESOLUTION_INVALID', 'RESOLUTION_NO', 'RESOLUTION_NONE_YET', 'RESOLUTION_YES')"), nullable=False),
  Column('notes', TEXT(), nullable=False, server_default=sqlalchemy.text("''")),
)
Index('resolutions_by_prediction_id', resolutions.c.prediction_id)

email_invitations = Table(
  'email_invitations',
  metadata,
  Column('inviter', username_t, ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('recipient', username_t, ForeignKey('users.username'), primary_key=True, nullable=False),
  Column('nonce', String(64), unique=True, nullable=False),
)
Index('email_invitations_by_nonce', email_invitations.c.nonce)
Index('email_invitations_by_inviter', email_invitations.c.inviter)
Index('email_invitations_by_recipient', email_invitations.c.recipient)


# Adapted from https://docs.sqlalchemy.org/en/14/dialects/sqlite.html#foreign-key-support
def set_sqlite_pragma(dbapi_connection, connection_record):
  cursor = dbapi_connection.cursor()
  cursor.execute("PRAGMA foreign_keys=ON")
  cursor.close()


def create_engine(dbinfo: mvp_pb2.DatabaseInfo) -> sqlalchemy.engine.Engine:
  engine = sqlalchemy.create_engine(get_db_url(dbinfo))
  if dbinfo.WhichOneof('database_kind') == 'sqlite':
    event.listen(engine, "connect", set_sqlite_pragma)
  return engine


def get_db_url(dbinfo: mvp_pb2.DatabaseInfo) -> str:
  if dbinfo.WhichOneof('database_kind') == 'sqlite':
    return f'sqlite+pysqlite:///{dbinfo.sqlite}'
  assert dbinfo.WhichOneof('database_kind') == 'mysql'
  return f'mysql+pymysql://{dbinfo.mysql.username}:{dbinfo.mysql.password}@{dbinfo.mysql.hostname}/{dbinfo.mysql.dbname}'
