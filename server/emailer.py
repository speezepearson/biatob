import datetime
from email.message import EmailMessage
import json
from pathlib import Path
from typing import Any, Mapping, Sequence #overload, Any, Mapping, Iterator, Optional, Container, NewType, Callable, NoReturn, Tuple, Iterable, Sequence, TypeVar, MutableSequence

import aiosmtplib
import google.protobuf.text_format  # type: ignore
import jinja2
import structlog

from .core import PredictionId, Username
from .protobuf import mvp_pb2

logger = structlog.get_logger()

_HERE = Path(__file__).parent

class Emailer:
    def __init__(
        self,
        hostname: str,
        port: int,
        username: str,
        password: str,
        from_addr: str,
        *,
        aiosmtplib_for_testing=aiosmtplib,
    ) -> None:
        self._hostname = hostname
        self._port = port
        self._username = username
        self._password = password
        self._from_addr = from_addr
        self._aiosmtplib = aiosmtplib_for_testing

        jenv = jinja2.Environment( # adapted from https://jinja.palletsprojects.com/en/2.11.x/api/#basics
            loader=jinja2.FileSystemLoader(searchpath=[_HERE/'templates'/'emails'], encoding='utf-8'),
            autoescape=jinja2.select_autoescape(['html', 'xml']),
        )
        jenv.undefined = jinja2.StrictUndefined  # raise exception if a template uses an undefined variable; adapted from https://stackoverflow.com/a/39127941/8877656
        self._ResolutionNotification_template = jenv.get_template('ResolutionNotification.html')
        self._ResolutionReminder_template = jenv.get_template('ResolutionReminder.html')
        self._EmailVerification_template = jenv.get_template('EmailVerification.html')
        self._Backup_template = jenv.get_template('Backup.html')
        self._InvariantViolations_template = jenv.get_template('InvariantViolations.html')

    async def _send(self, *, to: str, subject: str, body: str, headers: Mapping[str, str] = {}) -> None:
        # adapted from https://aiosmtplib.readthedocs.io/en/stable/usage.html#authentication
        message = EmailMessage()
        message["From"] = self._from_addr
        message["To"] = to
        message["Subject"] = subject
        for k, v in headers.items():
            message[k] = v
        message.set_content(body)
        message.set_type('text/html')
        await self._aiosmtplib.send(
            message=message,
            hostname=self._hostname,
            port=self._port,
            username=self._username,
            password=self._password,
            use_tls=True,
        )
        logger.info('sent email', subject=subject, to=to)

    async def _send_bccs(self, *, bccs: Sequence[str], subject: str, body: str) -> None:
        for i in range(0, len(bccs), 32):
            bccs_chunk = bccs[i:i+32]
            await self._send(
                subject=subject,
                to='blackhole@biatob.com',
                headers={'Bcc': ', '.join(bccs_chunk)},
                body=body,
            )

    async def send_resolution_notifications(self, bccs: Sequence[str], prediction_id: PredictionId, prediction: mvp_pb2.WorldState.Prediction) -> None:
        if not prediction.resolutions:
            raise ValueError(f'trying to email resolution-notifications for prediction {prediction_id}, but it has never resolved')
        resolution = prediction.resolutions[-1].resolution
        await self._send_bccs(
            bccs=bccs,
            subject=f'Prediction resolved: {json.dumps(prediction.prediction)}',
            body=self._ResolutionNotification_template.render(prediction_id=prediction_id, resolution=resolution, mvp_pb2=mvp_pb2),
        )

    async def send_resolution_reminder(self, to: str, prediction_id: PredictionId, prediction: mvp_pb2.WorldState.Prediction) -> None:
        await self._send(
            to=to,
            subject=f'Resolve your prediction: {json.dumps(prediction.prediction)}',
            body=self._ResolutionReminder_template.render(prediction_id=prediction_id, prediction=prediction),
        )

    async def send_email_verification(self, to: str, code: str) -> None:
        await self._send(
            to=to,
            subject='Your Biatob email-verification',
            body=self._EmailVerification_template.render(code=code),
        )

    async def send_backup(self, to: str, now: datetime.datetime, wstate: mvp_pb2.WorldState) -> None:
        await self._send(
            to=to,
            subject=f'Biatob backup for {now:%Y-%m-%d}',
            body=self._Backup_template.render(wstate_textproto=google.protobuf.text_format.MessageToString(wstate)),
        )

    async def send_invariant_violations(self, to: str, now: datetime.datetime, violations: Sequence[Mapping[str, Any]]) -> None:
        await self._send(
            to=to,
            subject=f'INVARIANT VIOLATIONS for {now:%Y-%m-%dT%H:%M:%S}',
            body=self._InvariantViolations_template.render(violations_json=json.dumps(violations, indent=True)),
        )
