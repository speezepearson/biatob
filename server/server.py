#! /usr/bin/env python3
# TODO: flock over the database file

import abc
import argparse
import contextlib
import hmac
from pathlib import Path
import random
import secrets
import time
from typing import Iterator, Optional, Container, NewType, Callable, NoReturn

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

class Marketplace(abc.ABC):
    def register_username(self, username: str, password: str) -> None: pass
    def get_username_info(self, username: str) -> Optional[mvp_pb2.WorldState.UsernameInfo]: pass
    def create_market(self, market: mvp_pb2.WorldState.Market) -> MarketId: pass
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

    def bet(self, market_id: MarketId, bettor: mvp_pb2.UserId, expected_resolution: bool, bettor_stake_cents: int) -> None:
        with self._mutate_state() as wstate:
            if market_id not in wstate.markets:
                raise KeyError(market_id)
            ensure_user_exists(wstate, bettor)
            # TODO: more validity-checking
            wstate.markets[market_id].trades.append(mvp_pb2.WorldState.Trade(
                bettor=bettor,
                expected_resolution=expected_resolution,
                bettor_stake=bettor_stake_cents,
                transacted_unixtime=self._clock(),
            ))


parser = argparse.ArgumentParser()
parser.add_argument("--elm-dist", default="elm/dist")
parser.add_argument("--state-path", type=Path, default="server.WorldState.pb")

def proto_response(message_pb) -> web.Response:
    return web.Response(status=200, content_type='application/octet-stream', body=message_pb.SerializeToString())

def make_routes(marketplace: Marketplace) -> web.RouteTableDef:
    routes = web.RouteTableDef()

    @routes.post('/api/create_market')
    async def api_create_market(http_request: web.Request) -> web.StreamResponse:
        creator = mvp_pb2.UserId(username='TODO_user')
        create_req = mvp_pb2.CreateMarketRequest()
        create_req.ParseFromString(await http_request.read())
        now = int(time.time())
        market = mvp_pb2.WorldState.Market(
            question=create_req.question,
            certainty=create_req.certainty,
            maximum_stake_cents=create_req.maximum_stake_cents,
            created_unixtime=now,
            closes_unixtime=now + create_req.open_seconds,
            special_rules=create_req.special_rules,
            creator=creator,
            trades=[],
            resolution=mvp_pb2.RESOLUTION_NONE_YET,
        )
        market_id = marketplace.create_market(market)
        print(f'market id {market_id} =>\n{indent(str(market))}')
        return proto_response(mvp_pb2.CreateMarketResponse(new_market_id=market_id))

    return routes

if __name__ == '__main__':
    args = parser.parse_args()
    app = web.Application()
    app.add_routes([web.static('/static', args.elm_dist)])
    app.add_routes(make_routes(FSMarketplace(state_path=args.state_path)))

    web.run_app(app)
