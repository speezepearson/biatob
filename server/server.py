#! /usr/bin/env python3
# TODO: flock over the database file

from aiohttp import web
from .protobuf.protobuf import mvp_pb2

import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--elm-dist", default="elm/dist")
args = parser.parse_args()


async def create_market_handler(request):
    name = request.match_info.get('name', "Anonymous")
    create_req = mvp_pb2.CreateMarketRequest()
    create_req.ParseFromString(request.read())
    # TODO: reject user inputs that are permuted by HTML sanitization
    print(create_req.string)
    return web.Response(text='created something about {create_req.string}')

app = web.Application()
app.add_routes([
    web.static('/static', args.elm_dist),
    web.post('/create', create_market_handler),
    ])

if __name__ == '__main__':
    web.run_app(app)
