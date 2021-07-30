import time
from typing import AbstractSet, Callable, TypeVar, Type

from aiohttp import web
from google.protobuf.message import Message

from .core import Servicer, TokenMint
from .http_glue import HttpTokenGlue
from .protobuf import mvp_pb2

_Req = TypeVar('_Req', bound=Message)
_Resp = TypeVar('_Resp', bound=Message)


async def parse_proto(http_req: web.Request, pb_req_cls: Type[_Req]) -> _Req:
    req = pb_req_cls()
    req.ParseFromString(await http_req.content.read())
    return req
def proto_response(pb_resp: _Resp) -> web.Response:
    return web.Response(status=200, headers={'Content-Type':'application/octet-stream'}, body=pb_resp.SerializeToString())


class ApiServer:

    def __init__(self, token_glue: HttpTokenGlue, servicer: Servicer) -> None:
        self._token_glue = token_glue
        self._servicer = servicer

    async def Whoami(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Whoami(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.WhoamiRequest)))
    async def SignOut(self, http_req: web.Request) -> web.Response:
        http_resp = proto_response(self._servicer.SignOut(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SignOutRequest)))
        self._token_glue.del_cookie(http_req, http_resp)
        return http_resp
    async def SendVerificationEmail(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SendVerificationEmail(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SendVerificationEmailRequest)))
    async def RegisterUsername(self, http_req: web.Request) -> web.Response:
        pb_resp = self._servicer.RegisterUsername(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.RegisterUsernameRequest))
        http_resp = proto_response(pb_resp)
        if pb_resp.WhichOneof('register_username_result') == 'ok':
            self._token_glue.set_cookie(pb_resp.ok.token, http_resp)
        return http_resp
    async def LogInUsername(self, http_req: web.Request) -> web.Response:
        pb_resp = self._servicer.LogInUsername(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.LogInUsernameRequest))
        http_resp = proto_response(pb_resp)
        if pb_resp.WhichOneof('log_in_username_result') == 'ok':
            self._token_glue.set_cookie(pb_resp.ok.token, http_resp)
        return http_resp
    async def CreatePrediction(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.CreatePrediction(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.CreatePredictionRequest)))
    async def GetPrediction(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetPrediction(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.GetPredictionRequest)))
    async def Stake(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Stake(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.StakeRequest)))
    async def Resolve(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.Resolve(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.ResolveRequest)))
    async def SetTrusted(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SetTrusted(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SetTrustedRequest)))
    async def GetUser(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetUser(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.GetUserRequest)))
    async def ChangePassword(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.ChangePassword(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.ChangePasswordRequest)))
    async def GetSettings(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.GetSettings(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.GetSettingsRequest)))
    async def SendInvitation(self, http_req: web.Request) -> web.Response:
        return proto_response(self._servicer.SendInvitation(actor=self._token_glue.get_authorizing_user(http_req), request=await parse_proto(http_req, mvp_pb2.SendInvitationRequest)))
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
