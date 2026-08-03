"""HTTP-boundary tests for the JSON API.

The servicer's business logic is covered by test_servicers (still protobuf);
these tests pin the JSON wire: that requests/responses round-trip through the
proto_bridge, that the ApiError hierarchy maps to the right HTTP status with a
readable ErrorResponse body, and that auth cookies are set/cleared correctly.
"""

from pathlib import Path

import httpx
import pytest

from . import api_types as T
from .asgi import build_app
from .test_utils import *


@pytest.fixture
def app(any_servicer: Servicer, token_mint: TokenMint):
  return build_app(servicer=any_servicer, token_mint=token_mint, elm_dist=Path(__file__).parent / 'elm' / 'dist')

@pytest.fixture
def cli(app):
  return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test')


async def post(client, path: str, request, response_cls, expected_status: int = 200):
  http_resp = await client.post(path, content=request.model_dump_json(), headers={'Content-Type': 'application/json'})
  assert http_resp.status_code == expected_status, (http_resp.status_code, http_resp.text)
  return (http_resp, response_cls.model_validate_json(http_resp.content))


def _register(cli, token_mint, username='potato', password='secret'):
  return post(cli, '/api/RegisterUsername', T.RegisterUsernameRequest(
      username=username, password=password,
      proof_of_email_token=token_mint.sign_proof_of_email(f'{username}@example.com')), T.AuthSuccess)


async def test_whoami_register_roundtrip_and_cookie(cli, token_mint: TokenMint):
  (_, who) = await post(cli, '/api/Whoami', T.WhoamiRequest(), T.WhoamiResponse)
  assert who.username == ''

  (http_resp, reg) = await _register(cli, token_mint)
  assert reg.owner == 'potato'
  assert 'auth' in cli.cookies  # register logs you in

  (_, who) = await post(cli, '/api/Whoami', T.WhoamiRequest(), T.WhoamiResponse)
  assert who.username == 'potato'


async def test_create_and_get_prediction_roundtrips_through_the_bridge(cli, token_mint: TokenMint, clock: MockClock):
  await _register(cli, token_mint)
  req = T.CreatePredictionRequest(
      prediction='Is 1 > 2?', view_privacy=T.PredictionViewPrivacy.ANYBODY,
      certainty=T.CertaintyRange(low=0.90, high=1.00), maximum_stake_cents=100_00,
      open_seconds=3600, special_rules='special rules string',
      resolves_at_unixtime=int(clock.now().timestamp() + 86400))
  (_, created) = await post(cli, '/api/CreatePrediction', req, T.CreatePredictionResponse)
  assert created.new_prediction_id

  (_, view) = await post(cli, '/api/GetPrediction', T.GetPredictionRequest(prediction_id=created.new_prediction_id), T.UserPredictionView)
  # every field survived the JSON<->proto bridge: scalars, a nested model, an enum
  assert view.prediction == req.prediction
  assert view.certainty == req.certainty
  assert view.maximum_stake_cents == req.maximum_stake_cents
  assert view.created_unixtime == clock.now().timestamp()
  assert view.closes_unixtime == view.created_unixtime + req.open_seconds
  assert view.resolution is None  # unresolved
  # the creator is auto-following their own prediction
  assert view.your_following_status == T.PredictionFollowingStatus.MANDATORY_BECAUSE_STAKED
  assert view.your_trades == []


async def test_login_failure_is_401_no_cookie_success_is_200_with_cookie(cli, token_mint: TokenMint, any_servicer: Servicer):
  create_user(any_servicer, u('rando'), password='pw')

  (_, err) = await post(cli, '/api/LogInUsername', T.LogInUsernameRequest(username='rando', password='wrong'), T.ErrorResponse, expected_status=401)
  assert err.catchall == 'bad password'
  assert 'auth' not in cli.cookies

  (_, ok) = await post(cli, '/api/LogInUsername', T.LogInUsernameRequest(username='rando', password='pw'), T.AuthSuccess)
  assert ok.owner == 'rando'
  assert 'auth' in cli.cookies


# --- the ApiError hierarchy -> HTTP status, one case per status --------------

async def test_NotLoggedInError_is_401(cli):
  (_, err) = await post(cli, '/api/GetSettings', T.GetSettingsRequest(include_relationships_with_users=[]), T.ErrorResponse, expected_status=401)
  assert err.catchall == 'must log in to see your settings'


async def test_AlreadyLoggedInError_is_400(cli, token_mint: TokenMint):
  await _register(cli, token_mint, username='rando')
  (_, err) = await post(cli, '/api/LogInUsername', T.LogInUsernameRequest(username='rando', password='secret'), T.ErrorResponse, expected_status=400)
  assert 'already authenticated' in err.catchall


async def test_ForbiddenError_is_403(cli, any_servicer: Servicer, token_mint: TokenMint, clock: MockClock):
  create_user(any_servicer, u('creator'), password='pw')
  prediction_id = CreatePredictionOk(any_servicer, au('creator'), dict(
      prediction='a thing will happen', resolves_at_unixtime=clock.now().timestamp() + 86400,
      certainty=mvp_pb2.CertaintyRange(low=0.40, high=0.60), maximum_stake_cents=100_00, open_seconds=3600))
  await _register(cli, token_mint, username='rando')
  (_, err) = await post(cli, '/api/Resolve', T.ResolveRequest(prediction_id=prediction_id, resolution=T.Resolution.YES, notes=''), T.ErrorResponse, expected_status=403)
  assert err.catchall == 'you are not the creator'


async def test_NoSuchPredictionError_is_404(cli):
  (_, err) = await post(cli, '/api/GetPrediction', T.GetPredictionRequest(prediction_id='nope'), T.ErrorResponse, expected_status=404)
  assert err.catchall == 'no such prediction'


async def test_NoSuchUserError_is_404(cli):
  (_, err) = await post(cli, '/api/GetUser', T.GetUserRequest(who='ghost'), T.ErrorResponse, expected_status=404)
  assert err.catchall == 'no such user'


async def test_AlreadyRegisteredError_is_409(cli, any_servicer: Servicer, token_mint: TokenMint):
  create_user(any_servicer, u('taken'), password='pw')
  (_, err) = await post(cli, '/api/RegisterUsername', T.RegisterUsernameRequest(
      username='taken', password='secret', proof_of_email_token=token_mint.sign_proof_of_email('other@example.com')),
      T.ErrorResponse, expected_status=409)
  assert err.catchall == 'username taken'


async def test_InvalidRequestError_is_400(cli, token_mint: TokenMint):
  await _register(cli, token_mint, username='rando')
  (_, err) = await post(cli, '/api/SetTrusted', T.SetTrustedRequest(who='rando', trusted=True), T.ErrorResponse, expected_status=400)
  assert err.catchall == 'cannot set trust for self'


# --- smoke: every endpoint answers a blank request coherently ----------------

_ENDPOINTS = [(f'/api/{name}', req, resp) for (name, req, resp) in T.ENDPOINTS
              if name in ('Whoami', 'SignOut', 'SendVerificationEmail', 'RegisterUsername', 'LogInUsername',
                          'CreatePrediction', 'GetPrediction', 'Stake', 'Follow', 'Resolve', 'SetTrusted',
                          'GetUser', 'ChangePassword', 'GetSettings', 'SendInvitation', 'AcceptInvitation')]

@pytest.mark.parametrize('logged_in', [True, False])
@pytest.mark.parametrize('path,request_model,success_model', _ENDPOINTS)
async def test_smoke(cli, any_servicer: Servicer, token_mint: TokenMint, logged_in: bool, path, request_model, success_model):
  """Never a 500; a 200 parses as the success payload; a non-2xx parses as an
  ErrorResponse that says something. Deliberately not asserting an exact status
  -- a blank request's failure mode depends on validation order (covered above)."""
  if logged_in:
    await _register(cli, token_mint, username='rando')

  http_resp = await cli.post(path, content='{}', headers={'Content-Type': 'application/json'})
  assert http_resp.status_code != 500, f'{path} crashed: {http_resp.text}'
  if http_resp.status_code == 200:
    success_model.model_validate_json(http_resp.content)
  else:
    assert 400 <= http_resp.status_code < 500, f'{path}: unexpected {http_resp.status_code}'
    assert T.ErrorResponse.model_validate_json(http_resp.content).catchall, f'{path}: {http_resp.status_code} with no explanation'
