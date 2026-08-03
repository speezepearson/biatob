#! /usr/bin/env python3

import argparse
import asyncio
import datetime
from pathlib import Path
import sys
import logging

import uvicorn

from .core import TokenMint
from .emailer import Emailer
from .sql_servicer import SqlConn, SqlServicer, forever, email_resolution_reminders, email_daily_backups, email_invariant_violations
from .sql_schema import create_engine
from .config import CredentialsConfig
from .asgi import build_app

# adapted from https://www.structlog.org/en/stable/examples.html?highlight=json#processors
# and https://www.structlog.org/en/stable/contextvars.html
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

logger = structlog.get_logger()

parser = argparse.ArgumentParser()
parser.add_argument("-H", "--host", default="localhost")
parser.add_argument("-p", "--port", type=int, default=8080)
parser.add_argument("--elm-dist", type=Path, default="elm/dist")
parser.add_argument("--credentials-path", type=Path, required=True)
parser.add_argument("--email-daily-backups-to", help='send daily backups to this email address')
parser.add_argument("--email-invariant-violations-to", help='send notifications of invariant violations to this email address')
parser.add_argument("-v", "--verbose", action="count", default=0)
parser.add_argument("--mock-out-emails", action="store_true")


def build_app_from_args(args: argparse.Namespace):
    credentials = CredentialsConfig.from_json(args.credentials_path.read_text())

    if args.mock_out_emails:
        from unittest.mock import Mock
        async def _mock_send(message, *a, **kw):
            print(message.as_string(), a, kw)
            await asyncio.sleep(0)
        testing_overrides = {'aiosmtplib_for_testing': Mock(send=_mock_send)}
    else:
        testing_overrides = {}

    emailer = Emailer(
        hostname=credentials.smtp.hostname,
        port=credentials.smtp.port,
        username=credentials.smtp.username,
        password=credentials.smtp.password,
        from_addr=credentials.smtp.from_addr,
        base_url=credentials.site_base_url,
        **testing_overrides,
    )
    token_mint = TokenMint(secret_key=credentials.token_signing_secret_bytes)
    raw_conn = create_engine(credentials.database).connect()
    conn = SqlConn(raw_conn)
    servicer = SqlServicer(conn=conn, token_mint=token_mint, emailer=emailer)

    def on_startup() -> None:
        loop = asyncio.get_running_loop()
        loop.create_task(forever(
            datetime.timedelta(hours=1),
            lambda now: email_resolution_reminders(conn, emailer, now),
        ))
        if args.email_daily_backups_to is not None:
            loop.create_task(forever(
                datetime.timedelta(hours=24),
                lambda now: email_daily_backups(conn=raw_conn, emailer=emailer, recipient_email=args.email_daily_backups_to, now=now),
            ))
        if args.email_invariant_violations_to is not None:
            loop.create_task(forever(
                datetime.timedelta(hours=1),
                lambda now: email_invariant_violations(raw_conn, emailer, recipient_email=args.email_invariant_violations_to, now=now),
            ))

    return build_app(servicer=servicer, token_mint=token_mint, elm_dist=args.elm_dist, on_startup=on_startup)


def main(args: argparse.Namespace) -> None:
    logging.basicConfig(level=logging.INFO if args.verbose == 0 else logging.DEBUG)
    if args.verbose < 2:
        logging.getLogger('filelock').setLevel(logging.WARN)
    app = build_app_from_args(args)
    print(f'Running forever on http://{args.host}:{args.port}...', file=sys.stderr)
    uvicorn.run(app, host=args.host, port=args.port, log_level='info' if args.verbose else 'warning')


if __name__ == '__main__':
    main(parser.parse_args())
