from pathlib import Path
from aiohttp import web
import pytest

from .protobuf import mvp_pb2
from .web_server import WebServer
from .http_glue import HttpTokenGlue
from .test_utils import *
from .test_api_server import post_proto, api_server

@pytest.fixture
def web_server(any_servicer, token_mint, clock):
  return WebServer(servicer=any_servicer, token_glue=HttpTokenGlue(token_mint), elm_dist=Path(__file__)/'elm'/'dist')

@pytest.fixture
def app(loop, web_server):
  """Adapted from https://docs.aiohttp.org/en/stable/testing.html"""
  app = web.Application(loop=loop)
  web_server.add_to_app(app)
  return app

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/elm/Prediction.js',
  '/',
  '/welcome',
  '/new',
  '/my_stakes',
  '/username/alice',
  '/settings',
])
async def test_smoke(aiohttp_client, app, api_server, any_servicer, path: str, logged_in: bool):
  api_server.add_to_app(app)
  prediction_id = any_servicer.CreatePrediction(new_user_token(any_servicer, 'rando'), some_create_prediction_request()).new_prediction_id
  assert prediction_id

  cli = await aiohttp_client(app)
  if logged_in:
    await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='alice', password='alice'), mvp_pb2.RegisterUsernameResponse)

  resp = await cli.get(path)
  assert resp.status == 200

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/p/{prediction_id}',
  '/p/{prediction_id}/embed-darkgreen-14pt.png',
])
async def test_smoke_for_prediction_paths(aiohttp_client, app, api_server, any_servicer, path: str, logged_in: bool):
  api_server.add_to_app(app)
  prediction_id = any_servicer.CreatePrediction(new_user_token(any_servicer, 'rando'), some_create_prediction_request()).new_prediction_id
  assert prediction_id

  cli = await aiohttp_client(app)
  if logged_in:
    await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='alice', password='alice'), mvp_pb2.RegisterUsernameResponse)

  resp = await cli.get(path.format(prediction_id=prediction_id))
  assert resp.status == 200

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path', [
  '/invitation/{nonce}/accept',
])
async def test_smoke_for_invitation_paths(aiohttp_client, app, api_server, any_servicer: Servicer, emailer: Emailer, path: str, logged_in: bool):
  api_server.add_to_app(app)

  recipient_token = new_user_token(any_servicer, 'recipient')
  set_and_verify_email(any_servicer, emailer, recipient_token, 'recipient@example.com')
  any_servicer.UpdateSettings(recipient_token, mvp_pb2.UpdateSettingsRequest(allow_email_invitations=mvp_pb2.MaybeBool(value=True)))

  inviter_token = new_user_token(any_servicer, 'inviter')
  set_and_verify_email(any_servicer, emailer, inviter_token, 'inviter@example.com')
  assert_oneof(any_servicer.SendInvitation(inviter_token, mvp_pb2.SendInvitationRequest(recipient='recipient')), 'send_invitation_result', 'ok', object)
  nonce = get_call_kwarg(emailer.send_invitation, 'nonce')

  cli = await aiohttp_client(app)
  if logged_in:
    await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='alice', password='alice'), mvp_pb2.RegisterUsernameResponse)

  resp = await cli.get(path.format(nonce=nonce))
  assert resp.status == 200
