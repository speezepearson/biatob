import asyncio
import datetime
from unittest.mock import Mock, ANY

import pytest

from .server import Emailer
from .protobuf import mvp_pb2

async def test_smtp_call():
  mock_smtp = Mock(send=Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)))
  emailer = Emailer(
    hostname='myhostname',
    port=12345,
    username='myusername',
    password='mypassword',
    from_addr='myfrom@ddre.ss',
    aiosmtplib_for_testing=mock_smtp,
  )

  await emailer._send(to='recip@ddre.ss', subject='mysubject', body='mybody')
  mock_smtp.send.assert_called_once_with(
    message=ANY,
    hostname='myhostname',
    port=12345,
    username='myusername',
    password='mypassword',
    use_tls=True,
  )

  message = mock_smtp.send.call_args[1]['message']
  assert message['From'] == 'myfrom@ddre.ss'
  assert message['To'] == 'recip@ddre.ss'
  assert message['Subject'] == 'mysubject'
  assert message.get_content_type() == 'text/html'
  assert message.get_content().strip() == 'mybody'

async def test_smoke():
  mock_smtp = Mock(send=Mock(wraps=lambda *args, **kwargs: asyncio.sleep(0)))
  emailer = Emailer(
    hostname='myhostname',
    port=12345,
    username='myusername',
    password='mypassword',
    from_addr='myfrom@ddre.ss',
    aiosmtplib_for_testing=mock_smtp,
  )

  await emailer.send_backup(to='a@a', now=datetime.datetime.now(), wstate=mvp_pb2.WorldState())
  await emailer.send_email_verification(to='a@a', code='b')
  await emailer.send_resolution_notifications(bccs=['a','b'], prediction_id=12345, prediction=mvp_pb2.WorldState.Prediction(resolutions=[mvp_pb2.ResolutionEvent(resolution=mvp_pb2.RESOLUTION_YES)]))
  await emailer.send_resolution_reminder(to='a', prediction_id=12345, prediction=mvp_pb2.WorldState.Prediction())

  with pytest.raises(ValueError):
    await emailer.send_resolution_notifications(bccs=['a','b'], prediction_id=12345, prediction=mvp_pb2.WorldState.Prediction(resolutions=[]))
