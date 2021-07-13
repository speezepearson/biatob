from pathlib import Path

import aiohttp
from server.core import ForgottenTokenError
from typing import AnyStr, TypeVar, Type, Tuple
from unittest.mock import Mock, patch

from aiohttp import web
import pytest
from google.protobuf.message import Message as PbMessage

from .api_server import _Req, _Resp
from .protobuf import mvp_pb2
from .api_server import ApiServer
from .http_glue import HttpTokenGlue
from .test_utils import *

SECRET_KEY = b'secret for testing'

@pytest.fixture
def api_server(any_servicer: Servicer, token_mint: TokenMint):
  return ApiServer(token_glue=HttpTokenGlue(token_mint), servicer=any_servicer)

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
  assert not pb_resp.username, pb_resp

  (http_resp, pb_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert pb_resp.ok.token.owner == 'potato', pb_resp

  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert pb_resp.username == 'potato', pb_resp

async def test_CreatePrediction_and_GetPrediction(aiohttp_client, app, clock):
  create_pb_req = mvp_pb2.CreatePredictionRequest(
    prediction="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60,
    resolves_at_unixtime=int(clock.now().timestamp() + 86400),
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app)
  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreatePrediction', create_pb_req, mvp_pb2.CreatePredictionResponse)
  assert create_pb_resp.WhichOneof('create_prediction_result') == 'error', create_pb_resp

  (http_resp, register_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert register_resp.WhichOneof('register_username_result') == 'ok', register_resp

  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreatePrediction', create_pb_req, mvp_pb2.CreatePredictionResponse)
  assert create_pb_resp.new_prediction_id, create_pb_resp

  (http_resp, get_pb_resp) = await post_proto(cli, '/api/GetPrediction', mvp_pb2.GetPredictionRequest(prediction_id=create_pb_resp.new_prediction_id), mvp_pb2.GetPredictionResponse)
  returned_prediction = get_pb_resp.prediction
  assert returned_prediction.prediction == create_pb_req.prediction
  assert returned_prediction.certainty == create_pb_req.certainty
  assert returned_prediction.maximum_stake_cents == create_pb_req.maximum_stake_cents
  assert returned_prediction.remaining_stake_cents_vs_believers == create_pb_req.maximum_stake_cents
  assert returned_prediction.remaining_stake_cents_vs_skeptics == create_pb_req.maximum_stake_cents
  assert returned_prediction.created_unixtime == clock.now().timestamp()
  assert returned_prediction.closes_unixtime == returned_prediction.created_unixtime + create_pb_req.open_seconds
  assert returned_prediction.special_rules == create_pb_req.special_rules


async def test_CreatePrediction_enforces_future_resolution(aiohttp_client, app, clock):
  create_pb_req = mvp_pb2.CreatePredictionRequest(
    prediction="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60*24*7,
    resolves_at_unixtime=int(clock.now().timestamp() - 1),
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app)
  (http_resp, register_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret'), mvp_pb2.RegisterUsernameResponse)
  assert register_resp.WhichOneof('register_username_result') == 'ok', register_resp

  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreatePrediction', create_pb_req, mvp_pb2.CreatePredictionResponse)
  assert 'must resolve after betting closes' in str(create_pb_resp.error), create_pb_resp



async def test_forgotten_token_recovery(aiohttp_client, app, any_servicer: Servicer):
  cli = await aiohttp_client(app)

  with patch.object(any_servicer, 'Whoami', side_effect=ForgottenTokenError()):
    http_resp = await cli.post(
      '/api/Whoami',
      headers={'Content-Type': 'application/octet-stream'},
      data=mvp_pb2.WhoamiRequest().SerializeToString(),
    )
  assert http_resp.status == 500
  assert b'obliterated your entire account' in await http_resp.content.read()

  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert not pb_resp.username, pb_resp


@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('endpoint,request_pb,response_pb_cls', [
  ('/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse),
  ('/api/SignOut', mvp_pb2.SignOutRequest(), mvp_pb2.SignOutResponse),
  ('/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(), mvp_pb2.RegisterUsernameResponse),
  ('/api/LogInUsername', mvp_pb2.LogInUsernameRequest(), mvp_pb2.LogInUsernameResponse),
  ('/api/CreatePrediction', mvp_pb2.CreatePredictionRequest(), mvp_pb2.CreatePredictionResponse),
  ('/api/GetPrediction', mvp_pb2.GetPredictionRequest(), mvp_pb2.GetPredictionResponse),
  ('/api/Stake', mvp_pb2.StakeRequest(), mvp_pb2.StakeResponse),
  ('/api/Resolve', mvp_pb2.ResolveRequest(), mvp_pb2.ResolveResponse),
  ('/api/SetTrusted', mvp_pb2.SetTrustedRequest(), mvp_pb2.SetTrustedResponse),
  ('/api/GetUser', mvp_pb2.GetUserRequest(), mvp_pb2.GetUserResponse),
  ('/api/ChangePassword', mvp_pb2.ChangePasswordRequest(), mvp_pb2.ChangePasswordResponse),
  ('/api/SetEmail', mvp_pb2.SetEmailRequest(), mvp_pb2.SetEmailResponse),
  ('/api/VerifyEmail', mvp_pb2.VerifyEmailRequest(), mvp_pb2.VerifyEmailResponse),
  ('/api/GetSettings', mvp_pb2.GetSettingsRequest(), mvp_pb2.GetSettingsResponse),
  ('/api/UpdateSettings', mvp_pb2.UpdateSettingsRequest(), mvp_pb2.UpdateSettingsResponse),
  ('/api/SendInvitation', mvp_pb2.SendInvitationRequest(), mvp_pb2.SendInvitationResponse),
  ('/api/AcceptInvitation', mvp_pb2.AcceptInvitationRequest(), mvp_pb2.AcceptInvitationResponse),
])
async def test_smoke(aiohttp_client, app, any_servicer: Servicer, logged_in: bool, endpoint: str, request_pb: Message, response_pb_cls: Type[Message]):
  cli = await aiohttp_client(app)

  if logged_in:
    RegisterUsernameOk(any_servicer, None, u('rando'), password='pw')
    await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'), mvp_pb2.LogInUsernameResponse)

  await post_proto(cli, endpoint, request_pb, response_pb_cls)
