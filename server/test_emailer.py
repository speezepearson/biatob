import asyncio
import datetime
from unittest.mock import Mock, ANY

import pytest

from .server import (
  Emailer,
  PredictionId,
  prediction_needs_email_reminder,
  get_email_for_resolution_reminder,
  email_resolution_reminder_if_necessary,
)
from .protobuf import mvp_pb2
from .test_utils import emailer, fs_storage

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

def test_prediction_needs_email_reminder():
  now = datetime.datetime.now()
  now_unixtime = now.timestamp()
  assert prediction_needs_email_reminder(now=now, prediction=mvp_pb2.WorldState.Prediction(
    resolves_at_unixtime=now_unixtime - 100,
    resolution_reminder_history=None,
  ))
  assert prediction_needs_email_reminder(now=now, prediction=mvp_pb2.WorldState.Prediction(
    resolves_at_unixtime=now_unixtime - 100,
    resolution_reminder_history=mvp_pb2.WorldState.ResolutionReminderHistory(attempts=[
      mvp_pb2.EmailAttempt(unixtime=now_unixtime - 50, succeeded=False)
    ]),
  ))

  assert not prediction_needs_email_reminder(now=now, prediction=mvp_pb2.WorldState.Prediction(
    resolves_at_unixtime=now_unixtime - 100,
    resolution_reminder_history=mvp_pb2.WorldState.ResolutionReminderHistory(attempts=[
      mvp_pb2.EmailAttempt(unixtime=now_unixtime - 50, succeeded=True)
    ]),
  ))
  assert not prediction_needs_email_reminder(now=now, prediction=mvp_pb2.WorldState.Prediction(
    resolves_at_unixtime=now_unixtime - 100,
    resolution_reminder_history=mvp_pb2.WorldState.ResolutionReminderHistory(attempts=[
      mvp_pb2.EmailAttempt(unixtime=now_unixtime - 50 + i, succeeded=False)
      for i in range(5)
    ]),
  ))
  assert not prediction_needs_email_reminder(now=now, prediction=mvp_pb2.WorldState.Prediction(
    resolves_at_unixtime=now_unixtime + 100,
    resolution_reminder_history=None,
  ))
  assert not prediction_needs_email_reminder(now=now, prediction=mvp_pb2.WorldState.Prediction(
    resolves_at_unixtime=now_unixtime - 100,
    resolution_reminder_history=mvp_pb2.WorldState.ResolutionReminderHistory(skipped=True),
  ))


def test_get_email_for_resolution_reminder():
  assert get_email_for_resolution_reminder(mvp_pb2.GenericUserInfo(
    email_reminders_to_resolve=True,
    email=mvp_pb2.EmailFlowState(verified='addr')
  )) == 'addr'
  assert get_email_for_resolution_reminder(mvp_pb2.GenericUserInfo(
    email_reminders_to_resolve=False,
    email=mvp_pb2.EmailFlowState(verified='addr')
  )) is None
  assert get_email_for_resolution_reminder(mvp_pb2.GenericUserInfo(
    email_reminders_to_resolve=True,
    email=mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email='addr'))
  )) is None
  

async def test_email_resolution_reminder_if_necessary_sends_email_once(emailer, fs_storage):
  now = datetime.datetime.now()
  fs_storage.put(mvp_pb2.WorldState(
    username_users={
      "has_email": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
        email_reminders_to_resolve=True,
        email=mvp_pb2.EmailFlowState(verified='has_email@example.com'),
      )),
    },
    predictions={
      123: mvp_pb2.WorldState.Prediction(creator=mvp_pb2.UserId(username='has_email'),
                                         resolves_at_unixtime=now.timestamp() - 100),
      789: mvp_pb2.WorldState.Prediction(creator=mvp_pb2.UserId(username='has_email'),
                                         resolves_at_unixtime=now.timestamp() + 100),
    },
  ))

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_called_once()
  emailer.send_resolution_reminder.reset_mock()

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_not_called()
  emailer.send_resolution_reminder.reset_mock()


async def test_email_resolution_reminder_if_necessary_retries_failed_send(emailer, fs_storage):
  now = datetime.datetime.now()
  fs_storage.put(mvp_pb2.WorldState(
    username_users={
      "has_email": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
        email_reminders_to_resolve=True,
        email=mvp_pb2.EmailFlowState(verified='has_email@example.com'),
      )),
    },
    predictions={
      123: mvp_pb2.WorldState.Prediction(creator=mvp_pb2.UserId(username='has_email'),
                                         resolves_at_unixtime=now.timestamp() - 100),
    },
  ))

  emailer.send_resolution_reminder.side_effect = RuntimeError()
  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_called_once()
  emailer.send_resolution_reminder.side_effect = None
  emailer.send_resolution_reminder.reset_mock()
  assert fs_storage.get().predictions[123].resolution_reminder_history.attempts

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_called_once()
  emailer.send_resolution_reminder.reset_mock()

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_not_called()
  emailer.send_resolution_reminder.reset_mock()


async def test_email_resolution_reminder_if_necessary_respects_email_preferences(emailer, fs_storage):
  now = datetime.datetime.now()
  fs_storage.put(mvp_pb2.WorldState(
    username_users={
      "has_email": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
        email_reminders_to_resolve=False,
        email=mvp_pb2.EmailFlowState(verified='has_email@example.com'),
      )),
    },
    predictions={
      123: mvp_pb2.WorldState.Prediction(creator=mvp_pb2.UserId(username='has_email'),
                                         resolves_at_unixtime=now.timestamp() - 100),
    },
  ))

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_not_called()
  assert fs_storage.get().predictions[123].resolution_reminder_history.skipped


async def test_email_resolution_reminder_if_necessary_does_not_send_for_future_predictions(emailer, fs_storage):
  now = datetime.datetime.now()
  fs_storage.put(mvp_pb2.WorldState(
    username_users={
      "has_email": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
        email_reminders_to_resolve=False,
        email=mvp_pb2.EmailFlowState(verified='has_email@example.com'),
      )),
    },
    predictions={
      123: mvp_pb2.WorldState.Prediction(creator=mvp_pb2.UserId(username='has_email'),
                                         resolves_at_unixtime=now.timestamp() + 100),
    },
  ))

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_not_called()
  assert not fs_storage.get().predictions[123].resolution_reminder_history.skipped


async def test_email_resolution_reminder_if_necessary_skips_when_creator_has_no_email(emailer, fs_storage):
  now = datetime.datetime.now()
  fs_storage.put(mvp_pb2.WorldState(
    username_users={
      "no_email": mvp_pb2.UsernameInfo(info=mvp_pb2.GenericUserInfo(
        email=mvp_pb2.EmailFlowState(code_sent=mvp_pb2.EmailFlowState.CodeSent(email='no_email@example.com')),
      )),
    },
    predictions={
      123: mvp_pb2.WorldState.Prediction(creator=mvp_pb2.UserId(username='no_email'),
                                         resolves_at_unixtime=now.timestamp() - 100),
    },
  ))

  await email_resolution_reminder_if_necessary(now=now, emailer=emailer, storage=fs_storage, prediction_id=PredictionId(123))
  emailer.send_resolution_reminder.assert_not_called()
  emailer.send_resolution_reminder.reset_mock()
  assert fs_storage.get().predictions[123].resolution_reminder_history.skipped
