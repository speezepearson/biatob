import argparse
import asyncio
from pathlib import Path
import tempfile

from ..core import *
from ..protobuf import mvp_pb2

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
          email_resolution_notifications=True,
          email=mvp_pb2.EmailFlowState(verified=args.email),
        )),
        "participant": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
          email_resolution_notifications=True,
          email=mvp_pb2.EmailFlowState(verified=args.email),
        )),
      },
      predictions={
        123: mvp_pb2.WorldState.Prediction(
          prediction='a thing will happen',
          maximum_stake_cents=10000,
          low_probability=0.50,
          creator=mvp_pb2.UserId(username='creator'),
          trades=[mvp_pb2.Trade(bettor=mvp_pb2.UserId(username='participant'), bettor_stake_cents=10, creator_stake_cents=10)],
        ),
      },
    ))
    mint = TokenMint(b'test secret')
    token = mint.mint_token(owner=mvp_pb2.UserId(username='creator'), ttl_seconds=3600)

    servicer = FsBackedServicer(storage=storage, token_mint=mint, emailer=emailer)
    servicer.Resolve(token=token, request=mvp_pb2.ResolveRequest(prediction_id=123, resolution=mvp_pb2.RESOLUTION_YES))


if __name__ == '__main__':
  asyncio.run(main(parser.parse_args()))
