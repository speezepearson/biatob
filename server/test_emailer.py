import asyncio
from unittest.mock import Mock, ANY

from .server import Emailer

async def test_emailer():
  mock_smtp = Mock()
  mock_smtp.send.return_value = asyncio.sleep(0)
  emailer = Emailer(
    hostname='myhostname',
    port=12345,
    username='myusername',
    password='mypassword',
    from_addr='myfrom@ddre.ss',
    aiosmtplib_for_testing=mock_smtp,
  )

  await emailer.send(to='recip@ddre.ss', subject='mysubject', body='mybody')
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
