import base64
import datetime
import functools
import io
from pathlib import Path
from typing import Optional

from aiohttp import web
from google.protobuf.message import Message
import jinja2
from PIL import Image, ImageDraw, ImageFont  # type: ignore
import structlog

from .core import Servicer
from .http import HttpTokenGlue
from .protobuf import mvp_pb2

logger = structlog.get_logger()

_HERE = Path(__file__).parent


try: IMAGE_EMBED_FONT = ImageFont.truetype('FreeSans.ttf', 18)
except Exception: IMAGE_EMBED_FONT = ImageFont.load_default()

@functools.lru_cache(maxsize=256)
def render_text(text: str, file_format: str = 'png') -> bytes:
    size = IMAGE_EMBED_FONT.getsize(text)
    img = Image.new('RGBA', size, color=(255,255,255,0))
    ImageDraw.Draw(img).text((0,0), text, fill=(0,128,0,255), font=IMAGE_EMBED_FONT)
    buf = io.BytesIO()
    img.save(buf, format=file_format)
    return buf.getvalue()


class WebServer:
    def __init__(self, servicer: Servicer, elm_dist: Path, token_glue: HttpTokenGlue) -> None:
        self._servicer = servicer
        self._elm_dist = elm_dist
        self._token_glue = token_glue

        self._jinja = jinja2.Environment( # adapted from https://jinja.palletsprojects.com/en/2.11.x/api/#basics
            loader=jinja2.FileSystemLoader(searchpath=[_HERE/'templates'], encoding='utf-8'),
            autoescape=jinja2.select_autoescape(['html', 'xml']),
        )
        self._jinja.undefined = jinja2.StrictUndefined  # raise exception if a template uses an undefined variable; adapted from https://stackoverflow.com/a/39127941/8877656

    def _get_auth_success(self, auth: Optional[mvp_pb2.AuthToken]) -> Optional[mvp_pb2.AuthSuccess]:
        if auth is None:
            return None
        get_settings_response = self._servicer.GetSettings(auth, mvp_pb2.GetSettingsRequest())
        if get_settings_response.WhichOneof('get_settings_result') != 'ok':
            logger.error('failed to get settings for valid-looking user', data_loss=True, auth=auth, get_settings_response=get_settings_response)
            return None
        return mvp_pb2.AuthSuccess(token=auth, user_info=get_settings_response.ok)

    async def get_static(self, req: web.Request) -> web.StreamResponse:
        filename = req.match_info['filename']
        if (not filename) or filename.startswith('.'):
            raise web.HTTPBadRequest()
        return web.FileResponse(_HERE/'static'/filename)

    async def get_wellknown(self, req: web.Request) -> web.StreamResponse:
        path = Path(req.match_info['path'])
        root = Path('/home/public/.well-known')
        try:
            return web.FileResponse(root / ((root/path).absolute().relative_to(root)))
        except Exception:
            raise web.HTTPBadRequest()

    async def get_elm_module(self, req: web.Request) -> web.StreamResponse:
        module = req.match_info['module']
        return web.FileResponse(_HERE.parent/f'elm/dist/{module}.js')

    async def get_index(self, req: web.Request) -> web.StreamResponse:
        auth = self._token_glue.parse_cookie(req)
        if auth is None:
            return web.HTTPTemporaryRedirect('/welcome')
        else:
            return await self.get_my_stakes(req)

    async def get_welcome(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('Welcome.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
            ))

    async def get_create_prediction_page(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('CreatePredictionPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
            ))

    async def get_view_prediction_page(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        prediction_id = int(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('ViewPredictionPage.html').render(
                title=f'Biatob - Prediction: by {datetime.datetime.fromtimestamp(get_prediction_resp.prediction.resolves_at_unixtime).strftime("%Y-%m-%d")}, {get_prediction_resp.prediction.prediction}',
                auth_success_pb_b64=pb_b64(auth_success),
                prediction_pb_b64=pb_b64(get_prediction_resp.prediction),
                prediction_id=prediction_id,
            ))

    async def get_prediction_img_embed(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        prediction_id = int(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        def format_cents(n: int) -> str:
            if n < 0: return '-' + format_cents(-n)
            return f'${n//100}' + ('' if n%100 == 0 else f'.{n%100 :02d}')
        prediction = get_prediction_resp.prediction
        text = f'[{format_cents(prediction.maximum_stake_cents)} @ {round(prediction.certainty.low*100)}-{round(prediction.certainty.high*100)}%]'

        return web.Response(content_type='image/png', body=render_text(text=text, file_format='png'))

    async def get_my_stakes(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        if auth is None:
            return web.Response(
                content_type='text/html',
                body=self._jinja.get_template('LoginPage.html').render(
                    auth_success_pb_b64=pb_b64(auth_success),
                ))
        list_my_stakes_resp = self._servicer.ListMyStakes(auth, mvp_pb2.ListMyStakesRequest())
        if list_my_stakes_resp.WhichOneof('list_my_stakes_result') == 'error':
            return web.Response(status=400, body=str(list_my_stakes_resp.error))
        assert list_my_stakes_resp.WhichOneof('list_my_stakes_result') == 'ok'
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('MyStakesPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                predictions_pb_b64=pb_b64(list_my_stakes_resp.ok),
            ))

    async def get_username(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        username = req.match_info['username']
        get_user_resp = self._servicer.GetUser(auth, mvp_pb2.GetUserRequest(who=username))
        if get_user_resp.WhichOneof('get_user_result') == 'error':
            return web.Response(status=400, body=str(get_user_resp.error))
        assert get_user_resp.WhichOneof('get_user_result') == 'ok'
        if get_user_resp.ok.trusts_you:
            list_predictions_resp = self._servicer.ListPredictions(auth, mvp_pb2.ListPredictionsRequest(creator=username))
            predictions: Optional[mvp_pb2.PredictionsById] = list_predictions_resp.ok  # TODO: error handling
        else:
            predictions = None
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('ViewUserPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                user_view_pb_b64=pb_b64(get_user_resp.ok),
                predictions_pb_b64=pb_b64(predictions),
            ))

    async def get_settings(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        if auth is None:
            return web.Response(
                content_type='text/html',
                body=self._jinja.get_template('LoginPage.html').render(
                    auth_success_pb_b64=pb_b64(auth_success),
                ))
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('SettingsPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
            ))

    async def get_invitation(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        invitation_id = mvp_pb2.InvitationId(
            inviter=req.match_info['username'],
            nonce=req.match_info['nonce'],
        )
        check_invitation_resp = self._servicer.CheckInvitation(auth, mvp_pb2.CheckInvitationRequest(invitation_id=invitation_id))
        if check_invitation_resp.WhichOneof('check_invitation_result') == 'error':
            return web.HTTPBadRequest(reason=str(check_invitation_resp.error))
        assert check_invitation_resp.WhichOneof('check_invitation_result') == 'is_open'
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('AcceptInvitationPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                invitation_is_open=check_invitation_resp.is_open,
                invitation_id_pb_b64=pb_b64(invitation_id),
            ))

    def add_to_app(self, app: web.Application) -> None:

        self._token_glue.add_to_app(app)

        app.router.add_get('/', self.get_index)
        app.router.add_get('/.well-known/{path:.*}', self.get_wellknown)
        app.router.add_get('/static/{filename}', self.get_static)
        app.router.add_get('/elm/{module}.js', self.get_elm_module)
        app.router.add_get('/welcome', self.get_welcome)
        app.router.add_get('/new', self.get_create_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}', self.get_view_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}/embed.png', self.get_prediction_img_embed)
        app.router.add_get('/my_stakes', self.get_my_stakes)
        app.router.add_get('/username/{username:[a-zA-Z0-9_-]+}', self.get_username)
        app.router.add_get('/settings', self.get_settings)
        app.router.add_get('/invitation/{username}/{nonce}', self.get_invitation)


def pb_b64(message: Optional[Message]) -> Optional[str]:
    if message is None:
        return None
    return base64.b64encode(message.SerializeToString()).decode('ascii')
