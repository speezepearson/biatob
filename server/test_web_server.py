from pathlib import Path
from typing import TypeVar, Type, Tuple
from unittest.mock import Mock

from aiohttp import web
import pytest
from google.protobuf.message import Message as PbMessage

from .protobuf import mvp_pb2
from .web_server import WebServer
from .http import HttpTokenGlue
from .test_utils import *
from .test_api_server import post_proto, api_server
from .test_fs_servicer import new_user_token, some_create_prediction_request

@pytest.fixture
def web_server(fs_servicer, token_mint, clock):
  return WebServer(servicer=fs_servicer, token_glue=HttpTokenGlue(token_mint), elm_dist=Path(__file__)/'elm'/'dist')

@pytest.fixture
def app(loop, web_server):
  """Adapted from https://docs.aiohttp.org/en/stable/testing.html"""
  app = web.Application(loop=loop)
  web_server.add_to_app(app)
  return app

async def test_smoke(aiohttp_client, app, api_server, fs_servicer):
  api_server.add_to_app(app)
  prediction_id = fs_servicer.CreatePrediction(new_user_token(fs_servicer, 'rando'), some_create_prediction_request()).new_prediction_id
  assert prediction_id > 0
  logged_in_cli = await aiohttp_client(app)
  await post_proto(logged_in_cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='alice', password='alice'), mvp_pb2.RegisterUsernameResponse)

  logged_out_cli = await aiohttp_client(app)

  paths = [
    '/elm/Prediction.js',
    '/',
    '/welcome',
    '/new',
    f'/p/{prediction_id}',
    f'/p/{prediction_id}/embed.png',
    '/my_stakes',
    '/username/alice',
    '/settings',
  ]
  for path in paths:
    resp = await logged_in_cli.get(path)
    assert resp.status == 200, path
    resp = await logged_out_cli.get(path)
    assert resp.status == 200, path
