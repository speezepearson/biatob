from pathlib import Path
from typing import TypeVar, Type, Tuple
from unittest.mock import Mock

from aiohttp import web
import pytest
from google.protobuf.message import Message as PbMessage

from .protobuf import mvp_pb2
from .server import WebServer, _Req, _Resp, HttpTokenGlue
from .test_utils import *
from .test_api_server import api_server
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

async def test_smoke(aiohttp_client, app, fs_servicer):
  token = new_user_token(fs_servicer, 'alice')
  prediction_id = fs_servicer.CreatePrediction(token, some_create_prediction_request()).new_prediction_id
  assert prediction_id > 0
  cli = await aiohttp_client(app)
  paths = [
    '/static/base.css',
    '/elm/ViewMarketPage.js',
    '/',
    '/welcome',
    '/new',
    f'/p/{prediction_id}',
    f'/p/{prediction_id}/embed.png',
    '/my_predictions',
    '/username/alice',
    '/settings',
  ]
  for path in paths:
    resp = await cli.get(path)
    assert resp.status == 200
