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


async def post_proto(client, url: str, request_pb: _Req, response_pb_cls: Type[_Resp], expected_status: int = 200, **kwargs) -> Tuple[web.Response, _Resp]:
  http_resp = await client.post(
    url,
    headers={'Content-Type': 'application/octet-stream'},
    data=request_pb.SerializeToString(),
  )
  assert http_resp.status == expected_status
  pb_resp = response_pb_cls()
  pb_resp.ParseFromString(await http_resp.content.read())
  return (http_resp, pb_resp)


async def test_Whoami_and_RegisterUsername(aiohttp_client, app, token_mint: TokenMint):
  cli = await aiohttp_client(app)
  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert not pb_resp.username, pb_resp

  (http_resp, reg_pb_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret', proof_of_email=token_mint.sign_proof_of_email('potato@example.com')), mvp_pb2.AuthSuccess)
  assert reg_pb_resp.token.owner == 'potato', reg_pb_resp

  (http_resp, pb_resp) = await post_proto(cli, '/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse)
  assert pb_resp.username == 'potato', pb_resp

async def test_CreatePrediction_and_GetPrediction(aiohttp_client, app, clock: MockClock, token_mint: TokenMint):
  create_pb_req = mvp_pb2.CreatePredictionRequest(
    prediction="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60,
    resolves_at_unixtime=int(clock.now().timestamp() + 86400),
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app)
  # Logged out: 401, not the 200-with-an-error-arm this used to assert.
  (http_resp, err) = await post_proto(cli, '/api/CreatePrediction', create_pb_req, mvp_pb2.ErrorResponse, expected_status=401)
  assert err.catchall == 'must log in to create predictions', err

  (http_resp, register_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret', proof_of_email=token_mint.sign_proof_of_email('potato@example.com')), mvp_pb2.AuthSuccess)

  (http_resp, create_pb_resp) = await post_proto(cli, '/api/CreatePrediction', create_pb_req, mvp_pb2.CreatePredictionResponse)
  assert create_pb_resp.new_prediction_id, create_pb_resp

  (http_resp, returned_prediction) = await post_proto(cli, '/api/GetPrediction', mvp_pb2.GetPredictionRequest(prediction_id=create_pb_resp.new_prediction_id), mvp_pb2.UserPredictionView)
  assert returned_prediction.prediction == create_pb_req.prediction
  assert returned_prediction.certainty == create_pb_req.certainty
  assert returned_prediction.maximum_stake_cents == create_pb_req.maximum_stake_cents
  assert returned_prediction.remaining_stake_cents_vs_believers == create_pb_req.maximum_stake_cents
  assert returned_prediction.remaining_stake_cents_vs_skeptics == create_pb_req.maximum_stake_cents
  assert returned_prediction.created_unixtime == clock.now().timestamp()
  assert returned_prediction.closes_unixtime == returned_prediction.created_unixtime + create_pb_req.open_seconds
  assert returned_prediction.special_rules == create_pb_req.special_rules


async def test_CreatePrediction_enforces_future_resolution(aiohttp_client, app, clock: MockClock, token_mint: TokenMint):
  create_pb_req = mvp_pb2.CreatePredictionRequest(
    prediction="Is 1 > 2?",
    certainty=mvp_pb2.CertaintyRange(low=0.90, high=1.00),
    maximum_stake_cents=100_00,
    open_seconds=60*60*24*7,
    resolves_at_unixtime=int(clock.now().timestamp() - 1),
    special_rules="special rules string",
  )

  cli = await aiohttp_client(app)
  (http_resp, register_resp) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(username='potato', password='secret', proof_of_email=token_mint.sign_proof_of_email('potato@example.com')), mvp_pb2.AuthSuccess)

  (http_resp, err) = await post_proto(cli, '/api/CreatePrediction', create_pb_req, mvp_pb2.ErrorResponse, expected_status=400)
  assert 'must resolve after betting closes' in err.catchall, err



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
@pytest.mark.parametrize('endpoint,request_pb,success_pb_cls', [
  ('/api/Whoami', mvp_pb2.WhoamiRequest(), mvp_pb2.WhoamiResponse),
  ('/api/SignOut', mvp_pb2.SignOutRequest(), mvp_pb2.SignOutResponse),
  ('/api/SendVerificationEmail', mvp_pb2.SendVerificationEmailRequest(), mvp_pb2.Empty),
  ('/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(), mvp_pb2.AuthSuccess),
  ('/api/LogInUsername', mvp_pb2.LogInUsernameRequest(), mvp_pb2.AuthSuccess),
  ('/api/CreatePrediction', mvp_pb2.CreatePredictionRequest(), mvp_pb2.CreatePredictionResponse),
  ('/api/GetPrediction', mvp_pb2.GetPredictionRequest(), mvp_pb2.UserPredictionView),
  ('/api/Stake', mvp_pb2.StakeRequest(), mvp_pb2.UserPredictionView),
  ('/api/Follow', mvp_pb2.FollowRequest(), mvp_pb2.UserPredictionView),
  ('/api/Resolve', mvp_pb2.ResolveRequest(), mvp_pb2.UserPredictionView),
  ('/api/SetTrusted', mvp_pb2.SetTrustedRequest(), mvp_pb2.GenericUserInfo),
  ('/api/GetUser', mvp_pb2.GetUserRequest(), mvp_pb2.Relationship),
  ('/api/ChangePassword', mvp_pb2.ChangePasswordRequest(), mvp_pb2.Empty),
  ('/api/GetSettings', mvp_pb2.GetSettingsRequest(), mvp_pb2.GenericUserInfo),
  ('/api/SendInvitation', mvp_pb2.SendInvitationRequest(), mvp_pb2.GenericUserInfo),
  ('/api/AcceptInvitation', mvp_pb2.AcceptInvitationRequest(), mvp_pb2.GenericUserInfo),
])
async def test_smoke(aiohttp_client, app, any_servicer: Servicer, logged_in: bool, endpoint: str, request_pb: Message, success_pb_cls: Type[Message]):
  """Every endpoint answers a blank request coherently.

  Deliberately does NOT assert an exact status per endpoint: a blank request is
  a failure for most of these, and *which* failure depends on validation order,
  which isn't what this test is about (the dedicated tests below cover that).
  What it pins is the invariant of the convention:

    - never a 500 -- an expected failure must be an ApiError, not a crash
    - a 200 body parses as that endpoint's success payload
    - a non-2xx body parses as an ErrorResponse that actually says something
  """
  cli = await aiohttp_client(app)

  if logged_in:
    create_user(any_servicer, u('rando'), password='pw')
    await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'), mvp_pb2.AuthSuccess)

  http_resp = await cli.post(endpoint, headers={'Content-Type': 'application/octet-stream'}, data=request_pb.SerializeToString())
  body = await http_resp.content.read()

  assert http_resp.status != 500, f'{endpoint} crashed: {body!r}'
  if http_resp.status == 200:
    success_pb_cls().ParseFromString(body)
  else:
    assert 400 <= http_resp.status < 500, f'{endpoint}: unexpected status {http_resp.status}'
    err = mvp_pb2.ErrorResponse()
    err.ParseFromString(body)
    assert err.catchall, f'{endpoint} returned {http_resp.status} with no explanation'


# --- HTTP-status error propagation -------------------------------------------
# These pin the behaviour this refactor is validating: failures leave via an
# exception, arrive as a non-2xx status, and carry an ErrorResponse body the
# client can actually read.

async def test_GetPrediction_nonexistent_is_404_with_readable_body(aiohttp_client, app):
  cli = await aiohttp_client(app)
  (http_resp, err) = await post_proto(
    cli, '/api/GetPrediction', mvp_pb2.GetPredictionRequest(prediction_id='nope'),
    mvp_pb2.ErrorResponse, expected_status=404)
  assert err.catchall == 'no such prediction', err


async def test_LogInUsername_bad_password_is_401_with_readable_body(aiohttp_client, app, any_servicer: Servicer):
  create_user(any_servicer, u('rando'), password='pw')
  cli = await aiohttp_client(app)
  (http_resp, err) = await post_proto(
    cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='wrong'),
    mvp_pb2.ErrorResponse, expected_status=401)
  assert err.catchall == 'bad password', err


async def test_LogInUsername_nonexistent_user_is_401(aiohttp_client, app):
  cli = await aiohttp_client(app)
  (http_resp, err) = await post_proto(
    cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='ghost', password='pw'),
    mvp_pb2.ErrorResponse, expected_status=401)
  assert 'no such user' in err.catchall, err


async def test_LogInUsername_failure_does_not_set_auth_cookie(aiohttp_client, app, any_servicer: Servicer):
  """The old code set the cookie inside `if WhichOneof(...) == 'ok'`; now the
  cookie line is simply unreachable on failure. Pin it so it stays that way."""
  create_user(any_servicer, u('rando'), password='pw')
  cli = await aiohttp_client(app)
  await post_proto(
    cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='wrong'),
    mvp_pb2.ErrorResponse, expected_status=401)
  assert 'auth' not in cli.session.cookie_jar.filter_cookies('http://127.0.0.1')


async def test_LogInUsername_success_is_200_and_sets_auth_cookie(aiohttp_client, app, any_servicer: Servicer):
  create_user(any_servicer, u('rando'), password='pw')
  cli = await aiohttp_client(app)
  (http_resp, auth_success) = await post_proto(
    cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'),
    mvp_pb2.AuthSuccess, expected_status=200)
  assert auth_success.token.owner == 'rando', auth_success
  assert 'auth' in cli.session.cookie_jar.filter_cookies('http://127.0.0.1')


# --- exception class -> HTTP status ------------------------------------------
# One case per status the ApiError hierarchy can produce, so a mis-set
# `http_status` on any class fails loudly rather than silently degrading to 400.

async def test_NotLoggedInError_is_401(aiohttp_client, app):
  cli = await aiohttp_client(app)
  (_, err) = await post_proto(cli, '/api/GetSettings', mvp_pb2.GetSettingsRequest(),
                              mvp_pb2.ErrorResponse, expected_status=401)
  assert err.catchall == 'must log in to see your settings', err


async def test_AlreadyLoggedInError_is_400(aiohttp_client, app, any_servicer: Servicer):
  create_user(any_servicer, u('rando'), password='pw')
  cli = await aiohttp_client(app)
  await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'), mvp_pb2.AuthSuccess)
  (_, err) = await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'),
                              mvp_pb2.ErrorResponse, expected_status=400)
  assert 'already authenticated' in err.catchall, err


async def test_ForbiddenError_is_403(aiohttp_client, app, any_servicer: Servicer, clock: MockClock):
  """Resolving someone else's prediction: authenticated, but not allowed."""
  create_user(any_servicer, u('creator'), password='pw')
  create_user(any_servicer, u('rando'), password='pw')
  prediction_id = CreatePredictionOk(any_servicer, au('creator'), dict(
    prediction='a thing will happen',
    resolves_at_unixtime=clock.now().timestamp() + 86400,
    certainty=mvp_pb2.CertaintyRange(low=0.40, high=0.60),
    maximum_stake_cents=100_00,
    open_seconds=3600,
  ))
  cli = await aiohttp_client(app)
  await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'), mvp_pb2.AuthSuccess)
  (_, err) = await post_proto(cli, '/api/Resolve',
                              mvp_pb2.ResolveRequest(prediction_id=prediction_id, resolution=mvp_pb2.RESOLUTION_YES),
                              mvp_pb2.ErrorResponse, expected_status=403)
  assert err.catchall == 'you are not the creator', err


async def test_NoSuchUserError_is_404(aiohttp_client, app):
  cli = await aiohttp_client(app)
  (_, err) = await post_proto(cli, '/api/GetUser', mvp_pb2.GetUserRequest(who='ghost'),
                              mvp_pb2.ErrorResponse, expected_status=404)
  assert err.catchall == 'no such user', err


async def test_NoSuchInvitationError_is_404(aiohttp_client, app):
  cli = await aiohttp_client(app)
  (_, err) = await post_proto(cli, '/api/AcceptInvitation', mvp_pb2.AcceptInvitationRequest(nonce='bogus'),
                              mvp_pb2.ErrorResponse, expected_status=404)
  assert err.catchall == 'no such invitation', err


async def test_AlreadyRegisteredError_is_409(aiohttp_client, app, any_servicer: Servicer, token_mint: TokenMint):
  create_user(any_servicer, u('taken'), password='pw')
  cli = await aiohttp_client(app)
  (_, err) = await post_proto(cli, '/api/RegisterUsername', mvp_pb2.RegisterUsernameRequest(
      username='taken', password='secret', proof_of_email=token_mint.sign_proof_of_email('other@example.com')),
      mvp_pb2.ErrorResponse, expected_status=409)
  assert err.catchall == 'username taken', err


async def test_InvalidRequestError_is_400(aiohttp_client, app, any_servicer: Servicer):
  """Trusting yourself is well-formed HTTP but nonsense."""
  create_user(any_servicer, u('rando'), password='pw')
  cli = await aiohttp_client(app)
  await post_proto(cli, '/api/LogInUsername', mvp_pb2.LogInUsernameRequest(username='rando', password='pw'), mvp_pb2.AuthSuccess)
  (_, err) = await post_proto(cli, '/api/SetTrusted', mvp_pb2.SetTrustedRequest(who='rando', trusted=True),
                              mvp_pb2.ErrorResponse, expected_status=400)
  assert err.catchall == 'cannot set trust for self', err
