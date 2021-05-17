#! /usr/bin/env python3

import argparse
import asyncio
from pathlib import Path
import sys
import argparse
import logging
import os
from email.message import EmailMessage

from aiohttp import web
import google.protobuf.text_format  # type: ignore

from .api_server import *
from .core import *
from .emailer import *
from .http import *
from .web_server import *
from .protobuf import mvp_pb2
from .sql_servicer import *
from .sql_schema import create_sqlite_engine

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
parser.add_argument("--state-path", type=Path, required=True)
parser.add_argument("--credentials-path", type=Path, required=True)
parser.add_argument("--email-daily-backups-to", help='send daily backups to this email address')
parser.add_argument("--email-invariant-violations-to", help='send notifications of invariant violations to this email address')
parser.add_argument("-v", "--verbose", action="count", default=0)

async def main(args):
    logging.basicConfig(level=logging.INFO if args.verbose==0 else logging.DEBUG)
    if args.verbose < 2:
        logging.getLogger('filelock').setLevel(logging.WARN)
        logging.getLogger('aiohttp.access').setLevel(logging.WARN)
    app = web.Application()

    credentials = google.protobuf.text_format.Parse(args.credentials_path.read_text(), mvp_pb2.CredentialsConfig())

    # from unittest.mock import Mock
    emailer = Emailer(
        hostname=credentials.smtp.hostname,
        port=credentials.smtp.port,
        username=credentials.smtp.username,
        password=credentials.smtp.password,
        from_addr=credentials.smtp.from_addr,
        # aiosmtplib_for_testing=Mock(send=lambda message, *args, **kwargs: (print(message.as_string(), args, kwargs), asyncio.sleep(0))[1])
    )
    token_mint = TokenMint(secret_key=credentials.token_signing_secret)
    token_glue = HttpTokenGlue(token_mint=token_mint)
    raw_conn = create_sqlite_engine(args.state_path).connect()
    conn = SqlConn(raw_conn)
    servicer = SqlServicer(conn=conn, token_mint=token_mint, emailer=emailer)

    token_glue.add_to_app(app)
    WebServer(
        token_glue=token_glue,
        elm_dist=args.elm_dist,
        servicer=servicer,
    ).add_to_app(app)
    ApiServer(
        token_glue=token_glue,
        servicer=servicer,
    ).add_to_app(app)

    asyncio.get_running_loop().create_task(forever(
        datetime.timedelta(seconds=13),
        lambda now: email_resolution_reminders(conn, emailer, now),
    ))
    if args.email_daily_backups_to is not None:
        asyncio.get_running_loop().create_task(email_daily_backups_forever(conn=conn, emailer=emailer, recipient_email=args.email_daily_backups_to))
    # if args.email_invariant_violations_to is not None:
    #     asyncio.get_running_loop().create_task(email_invariant_violations_forever(storage=storage, emailer=emailer, recipient_email=args.email_daily_backups_to))

    # adapted from https://docs.aiohttp.org/en/stable/web_advanced.html#application-runners
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host=args.host, port=args.port)
    await site.start()
    print(f'Running forever on http://{args.host}:{args.port}...', file=sys.stderr)
    try:
        while True:
            await asyncio.sleep(3600)
    except KeyboardInterrupt:
        print('Shutting down server...', file=sys.stderr)
        await runner.cleanup()
        print('...server shut down.', file=sys.stderr)

if __name__ == '__main__':
    asyncio.run(main(parser.parse_args()))
