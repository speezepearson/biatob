import asyncio
import datetime
from email.message import EmailMessage
from unittest.mock import Mock, ANY

import pytest

from .emailer import Emailer
from .core import PredictionId
from .protobuf import mvp_pb2

@pytest.fixture
def aiosmtplib():
  return Mock(send=Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)))

@pytest.fixture
def emailer(aiosmtplib):
  return Emailer(
    hostname='myhostname',
    port=12345,
    username='myusername',
    password='mypassword',
    from_addr='myfrom@ddre.ss',
    aiosmtplib_for_testing=aiosmtplib,
  )

async def test_smtp_call(aiosmtplib, emailer: Emailer):
  await emailer._send(to='recip@ddre.ss', subject='mysubject', body='mybody')
  aiosmtplib.send.assert_called_once_with(
    message=ANY,
    hostname='myhostname',
    port=12345,
    username='myusername',
    password='mypassword',
    use_tls=True,
  )

  message = aiosmtplib.send.call_args[1]['message']
  assert message['From'] == 'myfrom@ddre.ss'
  assert message['To'] == 'recip@ddre.ss'
  assert message['Subject'] == 'mysubject'
  assert message.get_content_type() == 'text/html'
  assert message.get_content().strip() == 'mybody'

def message_to_string(message: EmailMessage) -> str:
  return message.as_string().replace('=\n', '')

class TestSendBackup:
  async def test_smoke(self, aiosmtplib, emailer: Emailer):
    await emailer.send_backup(to='a@a', now=datetime.datetime.now(), body='backup body')
    assert 'backup body' in message_to_string(aiosmtplib.send.call_args[1]['message'])

class TestEmailVerification:
  async def test_smoke(self, aiosmtplib, emailer: Emailer):
    await emailer.send_email_verification(to='a@a', proof_of_email=mvp_pb2.ProofOfEmail())
    assert 'secret code' in message_to_string(aiosmtplib.send.call_args[1]['message'])

class TestResolutionNotification:
  async def test_smoke(self, aiosmtplib, emailer: Emailer):
    await emailer.send_resolution_notifications(bccs=['a','b'], prediction_id=PredictionId('my_pred_id'), prediction_text='a thing will happen', resolution=mvp_pb2.RESOLUTION_YES)
    body = message_to_string(aiosmtplib.send.call_args[1]['message'])
    assert 'a thing will happen' in body
    assert 'came true' in body
    assert 'https://biatob.com/p/my_pred_id' in body

class TestResolutionReminder:
  async def test_smoke(self, aiosmtplib, emailer: Emailer):
    await emailer.send_resolution_reminder(to='a', prediction_id=PredictionId('my_pred_id'), prediction_text='a thing will happen')
    assert 'a thing will happen' in message_to_string(aiosmtplib.send.call_args[1]['message'])

class TestInvariantViolations:
  async def test_smoke(self, aiosmtplib, emailer: Emailer):
    await emailer.send_invariant_violations(to='a', now=datetime.datetime.now(), violations=[{'foo': 'some violation string'}])
    assert 'some violation string' in message_to_string(aiosmtplib.send.call_args[1]['message'])
