#! /usr/bin/env python3
# TODO: flock over the database file

import abc
import argparse
import base64
import contextlib
import contextvars
import copy
import hmac
import json
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

def user_exists(wstate: mvp_pb2.WorldState, user: mvp_pb2.UserId) -> bool:
    if user.WhichOneof('kind') == 'username':
        return user.username in wstate.username_users
    else:
        raise RuntimeError(f'unrecognized UserId kind: {user!r}')


class TokenMint:

    def __init__(self, secret_key: bytes, clock: Callable[[], float] = time.time) -> None:
        self._secret_key = secret_key
        self._clock = clock

    def _compute_token_hmac(self, token: mvp_pb2.AuthToken) -> bytes:
        scratchpad = copy.copy(token)
        scratchpad.hmac_of_rest = b''
        return hmac.digest(key=self._secret_key, msg=scratchpad.SerializeToString(), digest='sha256')

    def _sign_token(self, token: mvp_pb2.AuthToken) -> None:
        token.hmac_of_rest = self._compute_token_hmac(token=token)

    def mint_token(self, owner: mvp_pb2.UserId, ttl_seconds: int) -> mvp_pb2.AuthToken:
        now = int(self._clock())
        token = mvp_pb2.AuthToken(
            owner=owner,
            minted_unixtime=now,
            expires_unixtime=now + ttl_seconds,
        )
        self._sign_token(token=token)
        return token

    def check_token(self, token: Optional[mvp_pb2.AuthToken]) -> Optional[mvp_pb2.AuthToken]:
        if token is None:
            return None
        now = int(self._clock())
        if not (token.minted_unixtime <= now < token.expires_unixtime):
            return None

        alleged_hmac = token.hmac_of_rest
        true_hmac = self._compute_token_hmac(token)
        if not hmac.compare_digest(alleged_hmac, true_hmac):
            return None

        return token

    def revoke_token(self, token: mvp_pb2.AuthToken) -> None:
        raise NotImplementedError()


class Servicer(abc.ABC):
    def Whoami(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse: pass
    def SignOut(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse: pass
    def RegisterUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse: pass
    def LogInUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse: pass
    def CreateMarket(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreateMarketRequest) -> mvp_pb2.CreateMarketResponse: pass
    def GetMarket(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetMarketRequest) -> mvp_pb2.GetMarketResponse: pass
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse: pass


def checks_token(f):
    import functools
    @functools.wraps(f)
    def wrapped(self: 'FsBackedServicer', token: Optional[mvp_pb2.AuthToken], *args, **kwargs):
        token = self._token_mint.check_token(token)
        if (token is not None) and not user_exists(self._get_state(), token.owner):
            raise RuntimeError('got valid token for nonexistent user!?', token)
        return f(self, token, *args, **kwargs)
    return wrapped

class FsBackedServicer(Servicer):
    def __init__(self, state_path: Path, token_mint: TokenMint, random_seed: Optional[int] = None, clock: Callable[[], float] = time.time) -> None:
        self._state_path = state_path
        self._token_mint = token_mint
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

    @checks_token
    def Whoami(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.WhoamiRequest) -> mvp_pb2.WhoamiResponse:
        return mvp_pb2.WhoamiResponse(auth=token)

    @checks_token
    def SignOut(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.SignOutRequest) -> mvp_pb2.SignOutResponse:
        if token is not None:
            pass # self._token_mint.revoke_token(token)  # TODO: implement
        return mvp_pb2.SignOutResponse()

    @checks_token
    def RegisterUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.RegisterUsernameRequest) -> mvp_pb2.RegisterUsernameResponse:
        if token is not None:
            return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='already authenticated; first, log out'))

        with self._mutate_state() as wstate:
            if request.username in wstate.username_users:
                return mvp_pb2.RegisterUsernameResponse(error=mvp_pb2.RegisterUsernameResponse.Error(catchall='username taken'))
            wstate.username_users[request.username].MergeFrom(mvp_pb2.WorldState.UsernameInfo(
                password_bcrypt=bcrypt.hashpw(request.password.encode('utf8'), bcrypt.gensalt()),
                info=mvp_pb2.WorldState.GenericUserInfo(trusted_users=[]),
            ))
            return mvp_pb2.RegisterUsernameResponse(ok=self._token_mint.mint_token(owner=mvp_pb2.UserId(username=request.username), ttl_seconds=60*60*24*7))

    @checks_token
    def LogInUsername(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.LogInUsernameRequest) -> mvp_pb2.LogInUsernameResponse:
        if token is not None:
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='already authenticated; first, log out'))

        info = self._get_state().username_users.get(request.username)
        if info is None:
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='no such user'))
        if not bcrypt.checkpw(request.password.encode('utf8'), info.password_bcrypt):
            return mvp_pb2.LogInUsernameResponse(error=mvp_pb2.LogInUsernameResponse.Error(catchall='bad password'))

        token = self._token_mint.mint_token(owner=mvp_pb2.UserId(username=request.username), ttl_seconds=86400)
        return mvp_pb2.LogInUsernameResponse(ok=token)

    @checks_token
    def CreateMarket(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.CreateMarketRequest) -> mvp_pb2.CreateMarketResponse:
        if token is None:
            return mvp_pb2.CreateMarketResponse(error=mvp_pb2.CreateMarketResponse.Error(catchall='must log in to create markets'))
        now = int(self._clock())
        with self._mutate_state() as wstate:
            mid = MarketId(weak_rand_not_in(self._rng, limit=2**32, xs=wstate.markets.keys()))
            market = mvp_pb2.WorldState.Market(
                question=request.question,
                certainty=request.certainty,
                maximum_stake_cents=request.maximum_stake_cents,
                created_unixtime=now,
                closes_unixtime=now + request.open_seconds,
                special_rules=request.special_rules,
                creator=token.owner,
                trades=[],
                resolution=mvp_pb2.RESOLUTION_NONE_YET,
            )
            wstate.markets[mid].MergeFrom(market)
            return mvp_pb2.CreateMarketResponse(new_market_id=mid)

    @checks_token
    def GetMarket(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.GetMarketRequest) -> mvp_pb2.GetMarketResponse:
        ws_market = self._get_state().markets.get(request.market_id)
        if ws_market is None:
            return mvp_pb2.GetMarketResponse(error=mvp_pb2.GetMarketResponse.Error(no_such_market=mvp_pb2.VOID))

        return mvp_pb2.GetMarketResponse(market=mvp_pb2.GetMarketResponse.Market(
            question=ws_market.question,
            certainty=ws_market.certainty,
            maximum_stake_cents=ws_market.maximum_stake_cents,
            remaining_stake_cents_vs_believers=ws_market.maximum_stake_cents - sum(t.creator_stake_cents for t in ws_market.trades if not t.bettor_is_a_skeptic),
            remaining_stake_cents_vs_skeptics=ws_market.maximum_stake_cents - sum(t.creator_stake_cents for t in ws_market.trades if t.bettor_is_a_skeptic),
            created_unixtime=ws_market.created_unixtime,
            closes_unixtime=ws_market.closes_unixtime,
            special_rules=ws_market.special_rules,
            creator=mvp_pb2.UserInfo(display_name='TODO'),
            resolution=ws_market.resolution,
            your_trades=[
                mvp_pb2.GetMarketResponse.Trade(
                    bettor_is_a_skeptic=t.bettor_is_a_skeptic,
                    creator_stake_cents=t.creator_stake_cents,
                    bettor_stake_cents=t.bettor_stake_cents,
                    transacted_unixtime=t.transacted_unixtime,
                )
                for t in ws_market.trades
                if (token is not None) and (t.bettor == token.owner)
            ],
        ))

    @checks_token
    def Stake(self, token: Optional[mvp_pb2.AuthToken], request: mvp_pb2.StakeRequest) -> mvp_pb2.StakeResponse:
        if token is None:
            return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='must log in to bet'))

        with self._mutate_state() as wstate:
            market = wstate.markets.get(request.market_id)
            if market is None:
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='no such market'))
            if request.bettor_is_a_skeptic:
                lowP = market.certainty.low
                creator_stake_cents = int(request.bettor_stake_cents * lowP/(1-lowP))
                existing_stake = sum(t.creator_stake_cents for t in market.trades if t.bettor_is_a_skeptic)
                if existing_stake + creator_stake_cents > market.maximum_stake_cents:
                    return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall='bet would exceed creator tolerance'))
            else:
                highP = market.certainty.high
                creator_stake_cents = int(request.bettor_stake_cents * (1-highP)/highP)
                existing_stake = sum(t.creator_stake_cents for t in market.trades if not t.bettor_is_a_skeptic)
            if existing_stake + creator_stake_cents > market.maximum_stake_cents:
                return mvp_pb2.StakeResponse(error=mvp_pb2.StakeResponse.Error(catchall=f'bet would exceed creator tolerance ({existing_stake} existing + {creator_stake_cents} new stake > {market.maximum_stake_cents} max)'))
            market.trades.append(mvp_pb2.WorldState.Trade(
                bettor=token.owner,
                bettor_is_a_skeptic=request.bettor_is_a_skeptic,
                creator_stake_cents=creator_stake_cents,
                bettor_stake_cents=request.bettor_stake_cents,
                transacted_unixtime=int(self._clock()),
            ))
            return mvp_pb2.StakeResponse(ok=mvp_pb2.VOID)


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

async def parse_proto(http_req: web.Request, pb_req_cls: Type[_Req]) -> _Req:
    req = pb_req_cls()
    req.ParseFromString(await http_req.content.read())
    return req
def proto_response(pb_resp: _Resp) -> web.Response:
    return web.Response(status=200, headers={'Content-Type':'application/octet-stream'}, body=pb_resp.SerializeToString())


class HttpTokenGlue:
    
    _AUTH_COOKIE_NAME = 'auth'

    def __init__(self, token_mint: TokenMint):
        self._mint = token_mint
        self._ctxvar: contextvars.ContextVar[Optional[mvp_pb2.AuthToken]] = contextvars.ContextVar('token', default=None)

    def add_to_app(self, app: web.Application) -> None:
        if self.middleware not in app.middlewares:
            app.middlewares.append(self.middleware)

    def get(self):
        return self._ctxvar.get()

    @web.middleware
    async def middleware(self, request, handler):
        ctxtok = self._ctxvar.set(self.parse_cookie(request))
        try:
            return await handler(request)
        finally:
            self._ctxvar.reset(ctxtok)

    def set_cookie(self, token: mvp_pb2.AuthToken, response: web.Response) -> mvp_pb2.AuthToken:
        response.set_cookie(self._AUTH_COOKIE_NAME, base64.b64encode(token.SerializeToString()).decode('ascii'))
        return token

    def del_cookie(self, req: web.Request, resp: web.Response) -> None:
        token = self.parse_cookie(req)
        if token is not None:
            self._mint.revoke_token(token)
        resp.del_cookie(self._AUTH_COOKIE_NAME)

    def parse_cookie(self, req: web.Request) -> Optional[mvp_pb2.AuthToken]:
        cookie = req.cookies.get(self._AUTH_COOKIE_NAME)
        if cookie is None:
            return None
        try:
            token_bytes = base64.b64decode(cookie)
        except ValueError:
            return None

        token = mvp_pb2.AuthToken()
        token.ParseFromString(token_bytes)
        return self._mint.check_token(token)


class ApiServer:

    def __init__(self, token_glue: HttpTokenGlue, servicer: Servicer, clock: Callable[[], float] = time.time) -> None:
        self._token_glue = token_glue
        self._servicer = servicer
        self._clock = clock

    def add_to_app(self, app: web.Application) -> None:
        routes = web.RouteTableDef()

        @routes.post('/api/Whoami')
        async def api_Whoami(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.Whoami(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.WhoamiRequest)))
        @routes.post('/api/SignOut')
        async def api_SignOut(http_req: web.Request) -> web.Response:
            http_resp = proto_response(self._servicer.SignOut(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.SignOutRequest)))
            self._token_glue.del_cookie(http_req, http_resp)
            return http_resp
        @routes.post('/api/RegisterUsername')
        async def api_RegisterUsername(http_req: web.Request) -> web.Response:
            pb_resp = self._servicer.RegisterUsername(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.RegisterUsernameRequest))
            http_resp = proto_response(pb_resp)
            if pb_resp.WhichOneof('register_username_result') == 'ok':
                self._token_glue.set_cookie(pb_resp.ok, http_resp)
            return http_resp
        @routes.post('/api/LogInUsername')
        async def api_LogInUsername(http_req: web.Request) -> web.Response:
            pb_resp = self._servicer.LogInUsername(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.LogInUsernameRequest))
            http_resp = proto_response(pb_resp)
            if pb_resp.WhichOneof('log_in_username_result') == 'ok':
                self._token_glue.set_cookie(pb_resp.ok, http_resp)
            return http_resp
        @routes.post('/api/CreateMarket')
        async def api_CreateMarket(http_req: web.Request) -> web.Response:
            import sys; print('client cookie:', http_req.cookies.get('auth'), file=sys.stderr)
            return proto_response(self._servicer.CreateMarket(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.CreateMarketRequest)))
        @routes.post('/api/GetMarket')
        async def api_GetMarket(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.GetMarket(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.GetMarketRequest)))
        @routes.post('/api/Stake')
        async def api_Stake(http_req: web.Request) -> web.Response:
            return proto_response(self._servicer.Stake(token=self._token_glue.get(), request=await parse_proto(http_req, mvp_pb2.StakeRequest)))

        self._token_glue.add_to_app(app)
        app.add_routes(routes)

class WebServer:
    def __init__(self, servicer: Servicer, elm_dist: Path, token_glue: HttpTokenGlue) -> None:
        self._servicer = servicer
        self._elm_dist = elm_dist
        self._token_glue = token_glue

    def add_to_app(self, app: web.Application) -> None:
        routes = web.RouteTableDef()

        @routes.get('/elm/{module}.js')
        async def get_elm_module(req: web.Request) -> web.Response:
            module = req.match_info['module']
            return web.Response(content_type='text/javascript', body=(Path(__file__).parent.parent/f'elm/dist/{module}.js').read_text())

        @routes.get('/new')
        async def get_create_market_page(req: web.Request) -> web.Response:
            auth = self._token_glue.get()
            auth_token_pb_b64 = json.dumps(base64.b64encode(auth.SerializeToString()).decode('ascii') if auth else None)
            return web.Response(content_type='text/html', body=(Path(__file__).parent/'templates'/'CreateMarketPage.html').read_text().replace(r'{{auth_token_pb_b64}}', auth_token_pb_b64))

        @routes.get('/market/{market_id:[0-9]+}')
        async def get_view_market_page(req: web.Request) -> web.Response:
            return web.Response(content_type='text/plain', body=str(self._servicer.GetMarket(self._token_glue.get(), mvp_pb2.GetMarketRequest(market_id=int(req.match_info['market_id'])))))

        self._token_glue.add_to_app(app)
        app.add_routes(routes)


parser = argparse.ArgumentParser()
parser.add_argument("--elm-dist", type=Path, default="elm/dist")
parser.add_argument("--state-path", type=Path, default="server.WorldState.pb")

if __name__ == '__main__':
    args = parser.parse_args()
    app = web.Application()
    token_mint = TokenMint(secret_key=b'TODO super secret')
    token_glue = HttpTokenGlue(token_mint=token_mint)
    servicer = FsBackedServicer(state_path=args.state_path, token_mint=token_mint)

    token_glue.add_to_app(app)
    WebServer(
        token_glue=token_glue,
        elm_dist=args.elm_dist,
        servicer=servicer,
    ).add_to_app(app)
    ApiServer(
        token_glue=token_glue,
        servicer=servicer,
    ).add_to_app(app)

    web.run_app(app)
