from pathlib import Path

import httpx
import pytest

from .protobuf import mvp_pb2
from .test_utils import *
from .test_api_server import post_proto, app, cli


async def _log_in_as_alice(cli, any_servicer):
  create_user(any_servicer, u('alice'), password='alice')
  await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='alice', password='alice'), mvp_pb2.AuthSuccess)


@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/elm/Prediction.js',
  '/',
  '/welcome',
  '/new',
  '/my_stakes',
  '/settings',
  '/fast',
])
async def test_smoke(cli, any_servicer, path: str, logged_in: bool):
  create_user(any_servicer, u('rando'))
  prediction_id = any_servicer.CreatePrediction(u('rando'), some_create_prediction_request()).new_prediction_id
  assert prediction_id

  if logged_in:
    await _log_in_as_alice(cli, any_servicer)

  resp = await cli.get(path, follow_redirects=True)
  assert resp.status_code == 200

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/p/{prediction_id}',
  '/p/{prediction_id}/embed-darkgreen-14pt.png',
])
async def test_smoke_for_prediction_paths(cli, any_servicer: Servicer, path: str, logged_in: bool):
  create_user(any_servicer, u('rando'))
  prediction_id = any_servicer.CreatePrediction(au('rando'), some_create_prediction_request()).new_prediction_id
  assert prediction_id

  if logged_in:
    await _log_in_as_alice(cli, any_servicer)

  resp = await cli.get(path.format(prediction_id=prediction_id), follow_redirects=True)
  assert resp.status_code == 200

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/username/{username}',
  '/u/{username}',
  '/{username}',
])
async def test_smoke_for_username_paths(cli, any_servicer: Servicer, path: str, logged_in: bool):
  create_user(any_servicer, u('viewee'))

  if logged_in:
    await _log_in_as_alice(cli, any_servicer)

  resp = await cli.get(path.format(username=u('viewee')), follow_redirects=True)
  assert resp.status_code == 200

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/invitation/{nonce}/accept',
])
async def test_smoke_for_invitation_paths(cli, any_servicer: Servicer, emailer: Emailer, path: str, logged_in: bool):
  create_user(any_servicer, u('recipient'))
  create_user(any_servicer, u('inviter'))
  any_servicer.SendInvitation(au('inviter'), mvp_pb2.SendInvitationRequest(recipient='recipient'))
  nonce = get_call_kwarg(emailer.send_invitation, 'nonce')

  if logged_in:
    await _log_in_as_alice(cli, any_servicer)

  resp = await cli.get(path.format(nonce=nonce), follow_redirects=True)
  assert resp.status_code == 200
