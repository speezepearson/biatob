from pathlib import Path
from typing import TypeVar, Type, Tuple
from unittest.mock import Mock

from aiohttp import web
import pytest
from google.protobuf.message import Message as PbMessage

from .protobuf import mvp_pb2
from .server import ApiServer, FSMarketplace, _Req, _Resp
from .test_utils import temp_path_fixture, clock_fixture

SECRET_KEY = b'secret for testing'

@pytest.fixture
def marketplace_fixture(temp_path_fixture, clock_fixture):
  return FSMarketplace(temp_path_fixture, clock=clock_fixture.now)

@pytest.fixture
def server_fixture(marketplace_fixture, clock_fixture):
  return ApiServer(secret_key=SECRET_KEY, marketplace=marketplace_fixture, clock=clock_fixture.now)

@pytest.fixture
def app_fixture(loop, server_fixture):
  """Adapted from https://docs.aiohttp.org/en/stable/testing.html"""
  app = web.Application(loop=loop)
  app.add_routes(server_fixture.make_routes())
  return app


async def post_proto(client, url: str, request_pb: _Req, response_pb_cls: Type[_Resp], **kwargs) -> Tuple[web.Response, _Resp]:
  http_resp = await client.post(
    url,
    headers={'Content-Type': 'application/octet-stream'},
    data=request_pb.SerializeToString(),
  )
  pb_resp = response_pb_cls()
  pb_resp.ParseFromString(await http_resp.content.read())
  return (http_resp, pb_resp)


async def test_whoami(aiohttp_client, marketplace_fixture, app_fixture):
  cli = await aiohttp_client(app_fixture)
  (http_resp, pb_resp) = await post_proto(cli, '/api/whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert http_resp.status == 200
  assert pb_resp.auth.owner == mvp_pb2.UserId()

  (http_resp, _) = await post_proto(cli, '/api/register_username', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert http_resp.status == 200

  (http_resp, pb_resp) = await post_proto(cli, '/api/whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert http_resp.status == 200
  assert pb_resp.auth.owner == mvp_pb2.UserId(username='potato')


async def test_create_market(aiohttp_client, marketplace_fixture, app_fixture):
  pb_req = mvp_pb2.CreateMarketRequest(
    question="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60*24*7,
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app_fixture)
  (http_resp, pb_resp) = await post_proto(cli, '/api/create_market', pb_req, mvp_pb2.CreateMarketResponse)
  assert http_resp.status == 403

  (http_resp, _) = await post_proto(cli, '/api/register_username', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert http_resp.status == 200

  (http_resp, pb_resp) = await post_proto(cli, '/api/create_market', pb_req, mvp_pb2.CreateMarketResponse)
  assert http_resp.status == 200
  assert pb_resp.new_market_id > 0
