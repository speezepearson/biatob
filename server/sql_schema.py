from sqlalchemy import event
from sqlalchemy import MetaData, Table, Column, Integer, String, BOOLEAN, ForeignKey, BINARY, Index, REAL, CheckConstraint
import sqlalchemy

metadata = MetaData()

users = Table(
  "users",
  metadata,
  Column('username', String(64), primary_key=True, nullable=False),
  Column('email_reminders_to_resolve', BOOLEAN(), nullable=False, default=False),
  Column('email_resolution_notifications', BOOLEAN(), nullable=False, default=False),
  Column('allow_email_invitations', BOOLEAN(), nullable=False, default=False),
  Column('login_password_id', ForeignKey('passwords.password_id'), nullable=False),  # will be nullable someday, if we add OAuth or something
  Column('email_flow_state', BINARY(), nullable=False),
)

passwords = Table(
  "passwords",
  metadata,
  Column('password_id', String(64), primary_key=True, nullable=False),
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
  Column('prediction_id', String(64), primary_key=True, nullable=False),
  Column('prediction', String(1024), CheckConstraint('LENGTH(prediction) > 0'), nullable=False),
  Column('certainty_low_p', REAL(), CheckConstraint('0 < certainty_low_p AND certainty_low_p < 1'), nullable=False),
  Column('certainty_high_p', REAL(), CheckConstraint('certainty_low_p <= certainty_high_p AND certainty_high_p <= 1'), nullable=False),
  Column('maximum_stake_cents', Integer(), CheckConstraint('maximum_stake_cents > 0'), nullable=False),
  Column('created_at_unixtime', REAL(), nullable=False),
  Column('closes_at_unixtime', REAL(), CheckConstraint('closes_at_unixtime > created_at_unixtime'), nullable=False),
  Column('resolves_at_unixtime', REAL(), CheckConstraint('resolves_at_unixtime > created_at_unixtime'), nullable=False),
  Column('special_rules', String(65535), nullable=False),
  Column('creator', ForeignKey('users.username'), nullable=False),
  Column('resolution_reminder_sent', BOOLEAN(), nullable=False, default=False),
)

trades = Table(
  'trades',
  metadata,
  Column('prediction_id', ForeignKey('predictions.prediction_id'), nullable=False),
  Column('bettor', ForeignKey('users.username'), nullable=False),
  Column('bettor_is_a_skeptic', BOOLEAN(), nullable=False),
  Column('bettor_stake_cents', Integer(), CheckConstraint('bettor_stake_cents > 0'), nullable=False),
  Column('creator_stake_cents', Integer(), CheckConstraint('creator_stake_cents > 0'), nullable=False),
  Column('transacted_at_unixtime', REAL(), nullable=False)
)
Index('trades_by_prediction_id', trades.c.prediction_id)
Index('trades_by_bettor', trades.c.bettor)

resolutions = Table(
  'resolutions',
  metadata,
  Column('prediction_id', ForeignKey('predictions.prediction_id'), primary_key=True, nullable=False),
  Column('resolved_at_unixtime', REAL(), primary_key=True, nullable=False),
  Column('resolution', String(64), CheckConstraint("resolution IN ('RESOLUTION_NONE_YET', 'RESOLUTION_YES', 'RESOLUTION_NO', 'RESOLUTION_INVALID')"), nullable=False),
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

migrations = Table(
  'migrations',
  metadata,
  Column('id', Integer(), primary_key=True, nullable=False),
  Column('stmt', String(4096), nullable=False),
)

_MIGRATION_STMTS = [
  'ALTER TABLE users ADD COLUMN allow_email_invitations BOOLEAN NOT NULL DEFAULT 0'
]
_N_MIGRATIONS = len(_MIGRATION_STMTS)


# Adapted from https://docs.sqlalchemy.org/en/14/dialects/sqlite.html#foreign-key-support
def set_sqlite_pragma(dbapi_connection, connection_record):
  cursor = dbapi_connection.cursor()
  cursor.execute("PRAGMA foreign_keys=ON")
  cursor.close()


def create_sqlite_engine(database: str) -> sqlalchemy.engine.Engine:
  engine = sqlalchemy.create_engine(f'sqlite+pysqlite:///{database}')
  event.listen(engine, "connect", set_sqlite_pragma)

  if sqlalchemy.inspect(engine).has_table('migrations'):
    with engine.connect() as conn:
      existing_migration_rows = list(conn.execute(sqlalchemy.select(migrations.c).order_by(migrations.c.id.asc())).fetchall())
      if len(existing_migration_rows) > _N_MIGRATIONS:
        raise RuntimeError(f'I only know about {_N_MIGRATIONS} migrations, but the DB has records of {len(existing_migration_rows)}; I have no idea what\'s going on')

      for id, migration_stmt in enumerate(_MIGRATION_STMTS):
        if id < len(existing_migration_rows):
          row = existing_migration_rows[id]
          if id != row['id']:
            raise RuntimeError(f'migration {id} (0-indexed) should have id {id}, but has id {row["id"]}')
          if row['stmt'] != migration_stmt:
            raise RuntimeError(f'migration with id {id} should have had statement {migration_stmt!r}, but DB records it as {row["stmt"]!r} instead; I have no idea what\'s going on')
        else:
          with conn.begin():
            conn.execute(sqlalchemy.text(migration_stmt))
            conn.execute(sqlalchemy.insert(migrations).values(id=id, stmt=migration_stmt))
  else:
    metadata.create_all(engine)
    with engine.connect() as conn:
      for id, migration_stmt in enumerate(_MIGRATION_STMTS):
        # all migrations have already been applied in the sqlalchemy defns
        conn.execute(sqlalchemy.insert(migrations).values(id=id, stmt=migration_stmt))

  return engine
