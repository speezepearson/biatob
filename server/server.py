#! /usr/bin/env python3
# TODO: flock over the database file

import secrets

import bcrypt
from aiohttp import web
from .protobuf import mvp_pb2

import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--elm-dist", default="elm/dist")
args = parser.parse_args()

def register_user(wstate: mvp_pb2.WorldState, username: str, password: str) -> None:
    uid = secrets.randbelow(2**64)
    while uid in wstate.users: uid = secrets.randbelow(2**64)
    wstate.users.get_or_create(uid).MergeFrom(mvp_pb2.WorldState.UserInfoTodoUnclash(
        username=username,
        password_bcrypt=bcrypt.hashpw(password.encode('utf8'), bcrypt.gensalt()),
        trusted_users=[],
    ))


async def create_market_handler(request):
    name = request.match_info.get('name', "Anonymous")
    create_req = mvp_pb2.CreateMarketRequest()
    create_req.ParseFromString(await request.read())
    # TODO: reject user inputs that are permuted by HTML sanitization
    print(create_req.question)
    return web.Response(text='created something about {create_req.question}')

app = web.Application()
app.add_routes([
    web.static('/static', args.elm_dist),
    web.post('/api/create_market', create_market_handler),
    ])

if __name__ == '__main__':
    web.run_app(app)
