from pathlib import Path
from typing import TypeVar, Type, Tuple
from unittest.mock import Mock

from aiohttp import web
import pytest
from google.protobuf.message import Message as PbMessage

from .protobuf import mvp_pb2
from .server import ApiServer, _Req, _Resp, HttpTokenGlue
from .test_utils import clock, fs_servicer, token_mint

SECRET_KEY = b'secret for testing'

@pytest.fixture
def api_server(fs_servicer, token_mint, clock):
  return ApiServer(token_glue=HttpTokenGlue(token_mint), servicer=fs_servicer, clock=clock.now)

@pytest.fixture
def app(loop, api_server):
  """Adapted from https://docs.aiohttp.org/en/stable/testing.html"""
  app = web.Application(loop=loop)
  api_server.add_to_app(app)
  return app


async def post_proto(client, url: str, request_pb: _Req, response_pb_cls: Type[_Resp], **kwargs) -> Tuple[web.Response, _Resp]:
  http_resp = await client.post(
    url,
    headers={'Content-Type': 'application/octet-stream'},
    data=request_pb.SerializeToString(),
  )
  assert http_resp.status == 200
  pb_resp = response_pb_cls()
  pb_resp.ParseFromString(await http_resp.content.read())
  return (http_resp, pb_resp)


async def test_Whoami_and_RegisterUsername(aiohttp_client, app):
  cli = await aiohttp_client(app)
  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert pb_resp.auth.owner.WhichOneof('kind') == None, pb_resp

  (http_resp, pb_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert pb_resp.ok.owner == mvp_pb2.UserId(username='potato'), pb_resp

  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert pb_resp.auth.owner == mvp_pb2.UserId(username='potato'), pb_resp

async def test_CreateMarket_and_GetMarket(aiohttp_client, app, clock):
  create_pb_req = mvp_pb2.CreateMarketRequest(
    prediction="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60*24*7,
    resolves_at_unixtime=int(clock.now() + 86400),
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app)
  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreateMarket', create_pb_req, mvp_pb2.CreateMarketResponse)
  assert create_pb_resp.WhichOneof('create_market_result') == 'error', create_pb_resp

  (http_resp, register_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert register_resp.WhichOneof('register_username_result') == 'ok', register_resp

  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreateMarket', create_pb_req, mvp_pb2.CreateMarketResponse)
  assert create_pb_resp.new_market_id > 0, create_pb_resp

  (http_resp, get_pb_resp) = await post_proto(cli, '/api/GetMarket', mvp_pb2.GetMarketRequest(market_id=create_pb_resp.new_market_id), mvp_pb2.GetMarketResponse)
  returned_market = get_pb_resp.market
  assert returned_market.prediction == create_pb_req.prediction
  assert returned_market.certainty == create_pb_req.certainty
  assert returned_market.maximum_stake_cents == create_pb_req.maximum_stake_cents
  assert returned_market.remaining_stake_cents_vs_believers == create_pb_req.maximum_stake_cents
  assert returned_market.remaining_stake_cents_vs_skeptics == create_pb_req.maximum_stake_cents
  assert returned_market.created_unixtime == clock.now()
  assert returned_market.closes_unixtime == returned_market.created_unixtime + create_pb_req.open_seconds
  assert returned_market.special_rules == create_pb_req.special_rules


async def test_CreateMarket_enforces_future_resolution(aiohttp_client, app, clock):
  create_pb_req = mvp_pb2.CreateMarketRequest(
    prediction="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60*24*7,
    resolves_at_unixtime=int(clock.now() - 1),
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app)
  (http_resp, register_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert register_resp.WhichOneof('register_username_result') == 'ok', register_resp

  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreateMarket', create_pb_req, mvp_pb2.CreateMarketResponse)
  assert 'must resolve in the future' in str(create_pb_resp.error), create_pb_resp



async def test_forgotten_token_recovery(aiohttp_client, app, fs_servicer):
  cli = await aiohttp_client(app)

  (http_resp, pb_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert pb_resp.ok.owner == mvp_pb2.UserId(username='potato'), pb_resp

  fs_servicer._set_state(mvp_pb2.WorldState())
  http_resp = await cli.post(
    '/api/RegisterUsername',
    headers={'Content-Type': 'application/octet-stream'},
    data=mvp_pb2.WhoamiRequest().SerializeToString(),
  )
  assert http_resp.status == 500
  assert b'obliterated your entire account' in await http_resp.content.read()

  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert pb_resp.auth.owner.WhichOneof('kind') == None, pb_resp
