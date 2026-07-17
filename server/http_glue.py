from typing import Optional

from aiohttp import web
import structlog

from .core import AuthorizingUsername, TokenMint, ForgottenTokenError, Username
from .tokens import AuthToken

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
            response = web.HTTPInternalServerError(reason="I, uh, may have accidentally obliterated your entire account. Crap. I'm sorry. Refresh the page to try again?")
            self.del_cookie(request, response)
            return response

    def set_cookie(self, token: AuthToken, response: web.Response) -> AuthToken:
        response.set_cookie(self._AUTH_COOKIE_NAME, self._mint.seal_token(token))
        return token

    def set_cookie_for_owner(self, owner: Username, response: web.Response) -> AuthToken:
        return self.set_cookie(self._mint.mint_token(owner), response)

    def del_cookie(self, req: web.Request, resp: web.Response) -> None:
        token = self.parse_cookie(req)
        if token is not None:
            self._mint.revoke_token(token)
        resp.del_cookie(self._AUTH_COOKIE_NAME)

    def parse_cookie(self, req: web.Request) -> Optional[AuthToken]:
        cookie = req.cookies.get(self._AUTH_COOKIE_NAME)
        if cookie is None:
            return None
        token = self._mint.unseal_token(cookie)
        return None if (self._mint.check_token(token) is None) else token

    def get_authorizing_user(self, req: web.Request) -> Optional[AuthorizingUsername]:
        token = self.parse_cookie(req)
        return None if (token is None) else AuthorizingUsername(Username(token.owner))
