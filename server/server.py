#! /usr/bin/env python3
# TODO: flock over the database file

import abc
import argparse
import base64
import contextlib
import copy
import hmac
from pathlib import Path
import random
import secrets
import time
from typing import Iterator, Optional, Container, NewType, Callable, NoReturn, Tuple

import bcrypt  # type: ignore
from aiohttp import web
from .protobuf import mvp_pb2

MarketId = NewType('MarketId', int)

class UsernameAlreadyRegisteredError(Exception): pass
class NoSuchUserError(Exception): pass
class BadPasswordError(Exception): pass

def weak_rand_not_in(rng: random.Random, limit: int, xs: Container[int]) -> int:
    result = rng.randrange(0, limit)
    while result in xs:
        result = rng.randrange(0, limit)
    return result

def indent(s: str) -> str:
    return '\n'.join('  '+line for line in s.splitlines())

def ensure_user_exists(wstate: mvp_pb2.WorldState, user: mvp_pb2.UserId) -> None:
    if user.WhichOneof('kind') == 'username':
        if user.username not in wstate.username_users:
            raise NoSuchUserError(user.username)
    else:
        raise RuntimeError(f'unrecognized UserId kind: {user!r}')

def raise_(e: Exception) -> NoReturn: raise e

def remaining_stake_cents(market: mvp_pb2.WorldState.Market) -> Tuple[int, int]:
    # TODO: fix the almost-certainly-wrong math below, and figure out why it's so unintuitive
    pool_against = pool_for = float(market.maximum_stake_cents)
    for trade in market.trades:
        if trade.bettor_expected_resolution:
            pool_against -= trade.bettor_stake * market.certainty.low/(1-market.certainty.low)
        else:
            pool_for -= trade.bettor_stake * market.certainty.high/(1-market.certainty.high)
    return (int(pool_against), int(pool_for))


def compute_token_hmac(key: bytes, token: mvp_pb2.AuthToken) -> bytes:
    scratchpad = copy.copy(token)
    scratchpad.hmac_of_rest = b''
    return hmac.digest(key=key, msg=scratchpad.SerializeToString(), digest='sha256')

def sign_token(key: bytes, token: mvp_pb2.AuthToken) -> None:
    token.hmac_of_rest = compute_token_hmac(key, token)

class Marketplace(abc.ABC):
    def register_username(self, username: str, password: str) -> None: pass
    def get_username_info(self, username: str) -> Optional[mvp_pb2.WorldState.UsernameInfo]: pass
    def create_market(self, market: mvp_pb2.WorldState.Market) -> MarketId: pass
    def get_market(self, market_id: MarketId) -> Optional[mvp_pb2.WorldState.Market]: pass
    def resolve_market(self, market_id: MarketId, resolution: bool) -> None: pass
    def set_trust(self, *, truster: mvp_pb2.UserId, trusted: mvp_pb2.UserId, trusts: bool) -> None: pass
    def bet(self, market_id: MarketId, bettor: mvp_pb2.UserId, expected_resolution: bool, bettor_stake_cents: int) -> None: pass

class FSMarketplace(Marketplace):
    def __init__(self, state_path: Path, random_seed: Optional[int] = None, clock: Callable[[], int] = lambda: int(time.time())) -> None:
        self._state_path = state_path
        self._rng = random.Random(random_seed)
        self._clock = clock

    def _get_state(self) -> mvp_pb2.WorldState:
        result = mvp_pb2.WorldState()
        if self._state_path.exists():
            result.ParseFromString(self._state_path.read_bytes())
        return result
    def _set_state(self, wstate: mvp_pb2.WorldState) -> None:
        self._state_path.write_bytes(wstate.SerializeToString())
    @contextlib.contextmanager
    def _mutate_state(self) -> Iterator[mvp_pb2.WorldState]:
        wstate = self._get_state()
        yield wstate
        self._set_state(wstate)

    def register_username(self, username: str, password: str) -> None:
        with self._mutate_state() as wstate:
            if username in wstate.username_users:
                raise UsernameAlreadyRegisteredError(username)
            wstate.username_users[username].MergeFrom(mvp_pb2.WorldState.UsernameInfo(
                password_bcrypt=bcrypt.hashpw(password.encode('utf8'), bcrypt.gensalt()),
                info=mvp_pb2.WorldState.GenericUserInfo(trusted_users=[]),
            ))

    def get_username_info(self, username: str) -> Optional[mvp_pb2.WorldState.UsernameInfo]:
        return self._get_state().username_users.get(username)

    def create_market(self, market: mvp_pb2.WorldState.Market) -> MarketId:
        with self._mutate_state() as wstate:
            mid = MarketId(weak_rand_not_in(self._rng, limit=2**64, xs=wstate.markets.keys()))
            wstate.markets[mid].MergeFrom(market)
            return mid

    def get_market(self, market_id: MarketId) -> Optional[mvp_pb2.WorldState.Market]:
        wstate = self._get_state()
        return wstate.markets.get(market_id)

    def resolve_market(self, market_id: MarketId, resolution: bool) -> None:
        with self._mutate_state() as wstate:
            if market_id not in wstate.markets:
                raise KeyError(market_id)
            wstate.markets[market_id].resolution = mvp_pb2.RESOLUTION_YES if resolution else mvp_pb2.RESOLUTION_NO

    def set_trust(self, *, truster: mvp_pb2.UserId, trusted: mvp_pb2.UserId, trusts: bool) -> None:
        with self._mutate_state() as wstate:
            ensure_user_exists(wstate, truster)
            ensure_user_exists(wstate, trusted)
            info: mvp_pb2.WorldState.GenericUserInfo = (wstate.username_users[truster.username] if truster.WhichOneof('kind')=='username' else raise_(RuntimeError(truster))).info
            if trusts:
                info.trusted_users.append(trusted)
            else:
                info.trusted_users.remove(trusted)

    def bet(self, market_id: MarketId, bettor: mvp_pb2.UserId, bettor_expected_resolution: bool, bettor_stake_cents: int) -> None:
        with self._mutate_state() as wstate:
            if market_id not in wstate.markets:
                raise KeyError(market_id)
            ensure_user_exists(wstate, bettor)
            # TODO: more validity-checking
            wstate.markets[market_id].trades.append(mvp_pb2.WorldState.Trade(
                bettor=bettor,
                bettor_expected_resolution=bettor_expected_resolution,
                bettor_stake=bettor_stake_cents,
                transacted_unixtime=self._clock(),
            ))


from typing import TypeVar, Type, Tuple, Union, Awaitable
from google.protobuf.message import Message
_Req = TypeVar('_Req', bound=Message)
_Resp = TypeVar('_Resp', bound=Message)
def proto_handler(req_t: Type[_Req], resp_t: Type[_Resp]):
    def wrap(f: Callable[[web.Request, _Req], Awaitable[Tuple[web.Response, _Resp]]]) -> Callable[[web.Request], Awaitable[web.Response]]:
        async def wrapped(http_req: web.Request) -> web.Response:
            pb_req = req_t()
            pb_req.ParseFromString(await http_req.content.read())
            (http_resp, pb_resp) = await f(http_req, pb_req)
            http_resp.content_type = 'application/octet-stream'
            http_resp.body = pb_resp.SerializeToString()
            return http_resp
        return wrapped
    return wrap

class ApiServer:

    _AUTH_COOKIE_NAME = 'auth'

    def __init__(self, secret_key: bytes, marketplace: Marketplace, clock: Callable[[], float] = time.time) -> None:
        self._secret_key = secret_key
        self._marketplace = marketplace
        self._clock = clock

    def _auth_from_headers(self, http_req: web.Request) -> Optional[mvp_pb2.AuthToken]:
        token_header = http_req.cookies.get(self._AUTH_COOKIE_NAME)
        if token_header is None:
            return None
        token_bytes = base64.b64decode(token_header)
        token = mvp_pb2.AuthToken()
        token.ParseFromString(token_bytes)
        alleged_hmac = token.hmac_of_rest
        true_hmac = compute_token_hmac(self._secret_key, token)
        if not hmac.compare_digest(alleged_hmac, true_hmac):
            return None
        now = self._clock()
        if not (token.minted_unixtime <= now <= token.expires_unixtime):
            return None
        return token

    def make_routes(self) -> web.RouteTableDef:
        routes = web.RouteTableDef()

        @routes.post('/api/whoami')
        @proto_handler(mvp_pb2.WhoamiRequest, mvp_pb2.WhoamiResponse)
        async def api_whoami(http_req: web.Request, pb_req: mvp_pb2.WhoamiRequest) -> Tuple[web.Response, mvp_pb2.WhoamiResponse]:
            return (web.Response(), mvp_pb2.WhoamiResponse(auth=self._auth_from_headers(http_req)))

        @routes.post('/api/register_username')
        @proto_handler(mvp_pb2.RegisterUsernameRequest, mvp_pb2.RegisterUsernameResponse)
        async def api_register_username(http_req: web.Request, pb_req: mvp_pb2.RegisterUsernameRequest) -> Tuple[web.Response, mvp_pb2.RegisterUsernameResponse]:
            try:
                self._marketplace.register_username(pb_req.username, pb_req.password)
            except UsernameAlreadyRegisteredError:
                return (web.Response(status=404), mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(username_taken=mvp_pb2.VOID)))
            now = int(self._clock())
            token = mvp_pb2.AuthToken(
                owner=mvp_pb2.UserId(username=pb_req.username),
                minted_unixtime=now,
                expires_unixtime=now + 60*60*24,
            )
            sign_token(self._secret_key, token)

            http_resp = web.Response()
            http_resp.set_cookie(self._AUTH_COOKIE_NAME, base64.b64encode(token.SerializeToString()).decode('ascii'))
            return (http_resp, mvp_pb2.RegisterUsernameResponse(ok=mvp_pb2.VOID))

        @routes.post('/api/create_market')
        @proto_handler(mvp_pb2.CreateMarketRequest, mvp_pb2.CreateMarketResponse)
        async def api_create_market(http_req: web.Request, pb_req: mvp_pb2.CreateMarketRequest) -> Tuple[web.Response, mvp_pb2.CreateMarketResponse]:
            auth = self._auth_from_headers(http_req)
            if auth is None:
                return (web.Response(status=403), mvp_pb2.CreateMarketResponse(error=mvp_pb2.CreateMarketResponse.Error(catchall='not logged in')))
            now = int(self._clock())
            market = mvp_pb2.WorldState.Market(
                question=pb_req.question,
                certainty=pb_req.certainty,
                maximum_stake_cents=pb_req.maximum_stake_cents,
                created_unixtime=now,
                closes_unixtime=now + pb_req.open_seconds,
                special_rules=pb_req.special_rules,
                creator=auth.owner,
                trades=[],
                resolution=mvp_pb2.RESOLUTION_NONE_YET,
            )
            market_id = self._marketplace.create_market(market)
            print(f'market id {market_id} =>\n{indent(str(market))}')
            return (web.Response(), mvp_pb2.CreateMarketResponse(new_market_id=market_id))

        @routes.post('/api/get_market')
        @proto_handler(mvp_pb2.GetMarketRequest, mvp_pb2.GetMarketResponse)
        async def api_get_market(http_req: web.Request, pb_req: mvp_pb2.GetMarketRequest) -> Tuple[web.Response, mvp_pb2.GetMarketResponse]:
            # TODO: ensure market should be visible to current user
            # auth = self._auth_from_headers(http_req)
            print('getting market', pb_req.market_id)
            ws_market = self._marketplace.get_market(market_id=MarketId(pb_req.market_id))
            if ws_market is None:
                return (web.Response(status=404), mvp_pb2.GetMarketResponse(error=mvp_pb2.GetMarketResponse.Error(no_such_market=mvp_pb2.VOID)))

            (rem_no, rem_yes) = remaining_stake_cents(ws_market)
            return (
                web.Response(),
                mvp_pb2.GetMarketResponse(market=mvp_pb2.GetMarketResponse.Market(
                    question=ws_market.question,
                    certainty=ws_market.certainty,
                    maximum_stake_cents=ws_market.maximum_stake_cents,
                    remaining_yes_stake_cents=rem_no,
                    remaining_no_stake_cents=rem_yes,
                    created_unixtime=ws_market.created_unixtime,
                    closes_unixtime=ws_market.closes_unixtime,
                    special_rules=ws_market.special_rules,
                    creator=mvp_pb2.UserInfo(display_name='TODO'),
                    resolution=ws_market.resolution,
                )),
            )


        return routes


parser = argparse.ArgumentParser()
parser.add_argument("--elm-dist", default="elm/dist")
parser.add_argument("--state-path", type=Path, default="server.WorldState.pb")

if __name__ == '__main__':
    args = parser.parse_args()
    app = web.Application()
    app.add_routes([web.static('/static', args.elm_dist)])
    app.add_routes(ApiServer(
        secret_key=b'TODO super secret',
        marketplace=FSMarketplace(state_path=args.state_path),
    ).make_routes())

    web.run_app(app)
