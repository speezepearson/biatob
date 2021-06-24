from __future__ import annotations

import datetime
from email.message import EmailMessage
import json
from pathlib import Path
from typing import Any, Iterable, Mapping, Optional, Sequence

import aiosmtplib
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
        self._Invitation_template = jenv.get_template('Invitation.html')

    async def _send(self, *, to: Optional[str], subject: str, body: str, headers: Mapping[str, str] = {}) -> None:
        # adapted from https://aiosmtplib.readthedocs.io/en/stable/usage.html#authentication
        message = EmailMessage()
        message["From"] = self._from_addr
        if to:
            message["To"] = to
        message["Subject"] = subject
        message["Reply-To"] = "contact@biatob.com"
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

    async def _send_bccs(self, *, bccs: Iterable[str], subject: str, body: str) -> None:
        bccs = list(set(bccs))
        for i in range(0, len(bccs), 32):
            bccs_chunk = bccs[i:i+32]
            await self._send(
                subject=subject,
                to=None,
                headers={'Bcc': ', '.join(bccs_chunk)},
                body=body,
            )

    async def send_resolution_notifications(
        self,
        bccs: Iterable[str],
        prediction_id: PredictionId,
        prediction_text: str,
        resolution: mvp_pb2.Resolution.V,
    ) -> None:
        await self._send_bccs(
            bccs=bccs,
            subject=f'Prediction resolved: {json.dumps(prediction_text)}',
            body=self._ResolutionNotification_template.render(
                prediction_id=prediction_id,
                prediction_text=prediction_text,
                verbed=(
                    'came true' if resolution == mvp_pb2.RESOLUTION_YES else
                    'did not come true' if resolution == mvp_pb2.RESOLUTION_NO else
                    'resolved INVALID' if resolution == mvp_pb2.RESOLUTION_INVALID else
                    'UN-resolved'
                ),
            ),
        )

    async def send_resolution_reminder(
        self,
        to: str,
        prediction_id: PredictionId,
        prediction_text: str,
    ) -> None:
        await self._send(
            to=to,
            subject=f'Resolve your prediction: {json.dumps(prediction_text)}',
            body=self._ResolutionReminder_template.render(
                prediction_id=prediction_id,
                prediction_text=prediction_text,
            ),
        )

    async def send_email_verification(self, to: str, code: str) -> None:
        await self._send(
            to=to,
            subject='Your Biatob email-verification',
            body=self._EmailVerification_template.render(email=to, code=code),
        )

    async def send_backup(self, to: str, now: datetime.datetime, body: str) -> None:
        await self._send(
            to=to,
            subject=f'Biatob backup for {now:%Y-%m-%d}',
            body=self._Backup_template.render(body=body),
        )

    async def send_invariant_violations(self, to: str, now: datetime.datetime, violations: Sequence[Mapping[str, Any]]) -> None:
        await self._send(
            to=to,
            subject=f'INVARIANT VIOLATIONS for {now:%Y-%m-%dT%H:%M:%S}',
            body=self._InvariantViolations_template.render(violations_json=json.dumps(violations, indent=True)),
        )

    async def send_invitation(
        self,
        nonce: str,
        inviter_username: Username,
        inviter_email: str,
        recipient_username: Username,
        recipient_email: str,
    ) -> None:
        await self._send(
            to=recipient_email,
            subject=f'Do you trust {inviter_email!r}?',
            body=self._Invitation_template.render(
                inviter_username=inviter_username,
                inviter_email=inviter_email,
                recipient_username=recipient_username,
                nonce=nonce,
            ),
        )
