import functools
import time
from typing import AbstractSet, Awaitable, Callable, TypeVar, Type

from aiohttp import web
from google.protobuf.message import Message
import structlog

from .core import ApiError, Servicer, TokenMint
from .http_glue import HttpTokenGlue
from .protobuf import mvp_pb2

logger = structlog.get_logger()

_Req = TypeVar('_Req', bound=Message)
_Resp = TypeVar('_Resp', bound=Message)


async def parse_proto(http_req: web.Request, pb_req_cls: Type[_Req]) -> _Req:
    req = pb_req_cls()
    req.ParseFromString(await http_req.content.read())
    return req
def proto_response(pb_resp: _Resp) -> web.Response:
    return web.Response(status=200, headers={'Content-Type':'application/octet-stream'}, body=pb_resp.SerializeToString())

def error_response(e: ApiError) -> web.Response:
    return web.Response(
        status=e.http_status,
        headers={'Content-Type': 'application/octet-stream'},
        body=mvp_pb2.ErrorResponse(catchall=e.catchall).SerializeToString(),
    )

_Handler = Callable[['ApiServer', web.Request], Awaitable[web.Response]]

def translates_api_errors(handler: _Handler) -> _Handler:
    """Turns an ApiError raised by the servicer into a non-2xx + ErrorResponse.

    Applied per-handler rather than as app middleware on purpose: the API and
    the server-rendered pages share one aiohttp Application, and an ApiError
    raised while rendering a page needs to become an HTML error, not a protobuf
    body. Each transport owns its own translation.
    """
    @functools.wraps(handler)
    async def wrapper(self: 'ApiServer', http_req: web.Request) -> web.Response:
        try:
            return await handler(self, http_req)
        except ApiError as e:
            logger.info('api error', path=http_req.path, status=e.http_status, catchall=e.catchall)
            return error_response(e)
    return wrapper


class ApiServer:

    def __init__(self, token_glue: HttpTokenGlue, servicer: Servicer) -> None:
        self._token_glue = token_glue
        self._servicer = servicer

    @translates_api_errors
    async def Whoami(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Whoami(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.WhoamiRequest)))
    @translates_api_errors
    async def SignOut(self, http_req: web.Request) -> web.Response:
        http_resp = proto_response(self._servicer.SignOut(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SignOutRequest)))
        self._token_glue.del_cookie(http_req, http_resp)
        return http_resp
    @translates_api_errors
    async def SendVerificationEmail(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SendVerificationEmail(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SendVerificationEmailRequest)))
    @translates_api_errors
    async def RegisterUsername(self, http_req: web.Request) -> web.Response:
        auth_success = self._servicer.RegisterUsername(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.RegisterUsernameRequest))
        http_resp = proto_response(auth_success)
        self._token_glue.set_cookie(auth_success.token, http_resp)
        return http_resp
    @translates_api_errors
    async def LogInUsername(self, http_req: web.Request) -> web.Response:
        auth_success = self._servicer.LogInUsername(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.LogInUsernameRequest))
        http_resp = proto_response(auth_success)
        self._token_glue.set_cookie(auth_success.token, http_resp)
        return http_resp
    @translates_api_errors
    async def CreatePrediction(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.CreatePrediction(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.CreatePredictionRequest)))
    @translates_api_errors
    async def GetPrediction(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetPrediction(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.GetPredictionRequest)))
    @translates_api_errors
    async def Stake(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Stake(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.StakeRequest)))
    @translates_api_errors
    async def Follow(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Follow(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.FollowRequest)))
    @translates_api_errors
    async def Resolve(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Resolve(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.ResolveRequest)))
    @translates_api_errors
    async def SetTrusted(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SetTrusted(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SetTrustedRequest)))
    @translates_api_errors
    async def GetUser(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetUser(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.GetUserRequest)))
    @translates_api_errors
    async def ChangePassword(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.ChangePassword(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.ChangePasswordRequest)))
    @translates_api_errors
    async def GetSettings(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetSettings(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.GetSettingsRequest)))
    @translates_api_errors
    async def SendInvitation(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SendInvitation(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SendInvitationRequest)))
    @translates_api_errors
    async def AcceptInvitation(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.AcceptInvitation(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.AcceptInvitationRequest)))

    def add_to_app(self, app: web.Application) -> None:
        app.router.add_post('/api/Whoami', self.Whoami)
        app.router.add_post('/api/SignOut', self.SignOut)
        app.router.add_post('/api/SendVerificationEmail', self.SendVerificationEmail)
        app.router.add_post('/api/RegisterUsername', self.RegisterUsername)
        app.router.add_post('/api/LogInUsername', self.LogInUsername)
        app.router.add_post('/api/CreatePrediction', self.CreatePrediction)
        app.router.add_post('/api/GetPrediction', self.GetPrediction)
        app.router.add_post('/api/Stake', self.Stake)
        app.router.add_post('/api/Follow', self.Follow)
        app.router.add_post('/api/Resolve', self.Resolve)
        app.router.add_post('/api/SetTrusted', self.SetTrusted)
        app.router.add_post('/api/GetUser', self.GetUser)
        app.router.add_post('/api/ChangePassword', self.ChangePassword)
        app.router.add_post('/api/GetSettings', self.GetSettings)
        app.router.add_post('/api/SendInvitation', self.SendInvitation)
        app.router.add_post('/api/AcceptInvitation', self.AcceptInvitation)
        self._token_glue.add_to_app(app)


def _reserved_toplevel_path_segments() -> AbstractSet[str]:
    server = ApiServer(token_glue=HttpTokenGlue(token_mint=TokenMint(secret_key=b'')), servicer=None)  # type: ignore
    app = web.Application()
    server.add_to_app(app)
    return {
        path.lstrip('/').split('/')[0]
        for path in (r.get_info().get('path') for r in app.router.routes())
        if path
    }
RESERVED_TOPLEVEL_PATH_SEGMENTS = _reserved_toplevel_path_segments()
