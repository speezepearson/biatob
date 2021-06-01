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
  '/p/{prediction_id}/embed.png',
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
  '/invitation/{nonce}',
])
async def test_smoke_for_invitation_paths(aiohttp_client, app, api_server, any_servicer, path: str, logged_in: bool):
  api_server.add_to_app(app)
  nonce = any_servicer.CreateInvitation(new_user_token(any_servicer, 'rando'), mvp_pb2.CreateInvitationRequest()).ok.nonce
  assert nonce

  cli = await aiohttp_client(app)
  if logged_in:
    await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='alice', password='alice'), mvp_pb2.RegisterUsernameResponse)

  resp = await cli.get(path.format(nonce=nonce))
  assert resp.status == 200
