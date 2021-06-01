import argparse
import datetime
from pathlib import Path
import random

import google.protobuf.text_format  # type: ignore
import sqlalchemy

from server.protobuf import mvp_pb2, old_pb2
from server.sql_servicer import SqlConn, check_password
import server.sql_schema as schema

import structlog
import structlog.processors
import structlog.contextvars
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,  # type: ignore
        structlog.processors.TimeStamper(),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.JSONRenderer(sort_keys=True),
    ]
)

ACTUAL_TIME = datetime.datetime.now()

parser = argparse.ArgumentParser()
parser.add_argument('--protobuf-path', type=Path, required=True)
parser.add_argument('--protobuf-format', choices=['text', 'binary'], required=True)
parser.add_argument('--sqlite-path', type=Path, required=True)

def main(args):

  ws = (
    google.protobuf.text_format.Parse(args.protobuf_path.read_text(), old_pb2.WorldState())
    if args.protobuf_format == 'text' else
    old_pb2.WorldState.FromString(args.protobuf_path.read_bytes())
  )
  engine = schema.create_sqlite_engine(str(args.sqlite_path))
  with engine.connect() as raw_conn:
    conn = SqlConn(raw_conn)

    for username, settings in ws.user_settings.items():
      password_id = ''.join(random.choices('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567879_', k=16))
      conn.register_username(username, 'spencer super secret', password_id)
      raw_conn.execute(
        sqlalchemy.update(schema.passwords)
        .where(schema.passwords.c.password_id == password_id)
        .values(salt=settings.login_password.salt, scrypt=settings.login_password.scrypt)
      )
      assert not check_password('spencer super secret', conn.get_username_password_info(username))

      conn.update_settings(
        user=username,
        request=mvp_pb2.UpdateSettingsRequest(
          email_reminders_to_resolve=mvp_pb2.MaybeBool(value=settings.email_reminders_to_resolve),
          email_resolution_notifications=mvp_pb2.MaybeBool(value=settings.email_resolution_notifications),
        )
      )
      conn.set_email(username, settings.email)

    for username, settings in ws.user_settings.items():
      for nonce, invitation in settings.invitations.items():
        conn.create_invitation(
          nonce=nonce,
          inviter=username,
          now=datetime.datetime.fromtimestamp(invitation.created_unixtime),
          notes=invitation.notes,
        )
        if invitation.accepted_by:
          conn.accept_invitation(
            nonce=nonce,
            accepter=invitation.accepted_by,
            now=datetime.datetime.fromtimestamp(invitation.accepted_unixtime),
          )

      for other, relationship in settings.relationships.items():
        conn.set_trusted(subject_username=username, object_username=other, trusted=relationship.trusted)

    for prediction_id, prediction in ws.predictions.items():
      conn.create_prediction(
        now=datetime.datetime.fromtimestamp(prediction.created_unixtime),
        prediction_id=str(prediction_id),
        creator=prediction.creator,
        request=mvp_pb2.CreatePredictionRequest(
          prediction=prediction.prediction,
          certainty=mvp_pb2.CertaintyRange(low=prediction.certainty.low, high=prediction.certainty.high),
          maximum_stake_cents=prediction.maximum_stake_cents,
          open_seconds=round(prediction.closes_unixtime - prediction.created_unixtime),
          special_rules=prediction.special_rules,
          resolves_at_unixtime=prediction.resolves_at_unixtime,
        ),
      )
      raw_conn.execute(
        sqlalchemy.update(schema.predictions)
        .where(schema.predictions.c.prediction_id == prediction_id)
        .values(resolution_reminder_sent=(prediction.resolution_reminder_history.skipped or len(prediction.resolution_reminder_history.attempts) >= 3))
      )

      for trade in prediction.trades:
        conn.stake(
          prediction_id=str(prediction_id),
          bettor=trade.bettor,
          bettor_is_a_skeptic=trade.bettor_is_a_skeptic,
          bettor_stake_cents=trade.bettor_stake_cents,
          creator_stake_cents=trade.creator_stake_cents,
          now=datetime.datetime.fromtimestamp(trade.transacted_unixtime),
        )
      for res in prediction.resolutions:
        conn.resolve(
          now=datetime.datetime.fromtimestamp(res.unixtime),
          request=mvp_pb2.ResolveRequest(
            prediction_id=str(prediction_id),
            resolution=res.resolution,
            notes=res.notes,
          )
        )

if __name__ == '__main__':
  main(parser.parse_args())
