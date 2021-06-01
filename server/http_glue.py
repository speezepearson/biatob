import base64
from typing import Optional

from aiohttp import web
import structlog

from .core import TokenMint, ForgottenTokenError
from .protobuf import mvp_pb2

logger = structlog.get_logger()

class HttpTokenGlue:

    _AUTH_COOKIE_NAME = 'auth'

    def __init__(self, token_mint: TokenMint):
        self._mint = token_mint

    def add_to_app(self, app: web.Application) -> None:
        if self.middleware not in app.middlewares:
            app.middlewares.append(self.middleware)

    @web.middleware
    async def middleware(self, request, handler):
        try:
            return await handler(request)
        except ForgottenTokenError as e:
            logger.exception(e)
            response = web.HTTPInternalServerError(reason="I, uh, may have accidentally obliterated your entire account. Crap. I'm sorry.")
            self.del_cookie(request, response)
            return response

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

