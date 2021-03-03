import argparse
import tempfile

from ..server import *

parser = argparse.ArgumentParser()
parser.add_argument('--no-dry-run', action='store_false', dest='dry_run')
parser.add_argument('--email', required=True)
parser.add_argument('--credentials-path', type=Path, required=True)

async def main(args):
  t = datetime.datetime(2020, 1, 1)

  credentials = google.protobuf.text_format.Parse(args.credentials_path.read_text(), mvp_pb2.CredentialsConfig())
  from unittest.mock import Mock
  emailer = Emailer(
    hostname=credentials.smtp.hostname,
    port=credentials.smtp.port,
    username=credentials.smtp.username,
    password=credentials.smtp.password,
    from_addr=credentials.smtp.from_addr,
    aiosmtplib_for_testing=Mock(send=lambda message, **kwargs: (print('### vvv EMAIL', message.as_string(), '### ^^^ EMAIL', sep='\n'), asyncio.sleep(0))[1]) if args.dry_run else aiosmtplib,
  )

  with tempfile.NamedTemporaryFile() as f:
    state_path = Path(f.name)
    storage = FsStorage(state_path)

    storage.put(mvp_pb2.WorldState(
      username_users={
        "creator": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
          email_reminders_to_resolve=True,
          email=mvp_pb2.EmailFlowState(verified=args.email),
        )),
      },
      predictions={
        123: mvp_pb2.WorldState.Prediction(
          prediction='a thing will happen',
          creator=mvp_pb2.UserId(username='creator'),
          resolves_at_unixtime=t.timestamp() - 100,
        ),
      },
    ))

    await email_resolution_reminder_if_necessary(now=t, emailer=emailer, storage=storage, prediction_id=PredictionId(123))
    await email_resolution_reminder_if_necessary(now=t, emailer=emailer, storage=storage, prediction_id=PredictionId(123))
    await email_resolution_reminder_if_necessary(now=t, emailer=emailer, storage=storage, prediction_id=PredictionId(123))


if __name__ == '__main__':
  asyncio.run(main(parser.parse_args()))