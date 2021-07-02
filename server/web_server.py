import base64
import datetime
import functools
import io
from pathlib import Path
import re
from typing import Callable, Optional, Tuple

from aiohttp import web
from attr import dataclass
from google.protobuf.message import Message
import jinja2
from PIL import Image, ImageDraw, ImageFont  # type: ignore
import structlog

from .core import Servicer, Username
from .http_glue import HttpTokenGlue
from .protobuf import mvp_pb2

logger = structlog.get_logger()

_HERE = Path(__file__).parent

ARIAL_PATH = _HERE / 'arial.ttf'
WARNOCK_PRO_PATH = _HERE / 'warnock-pro.otf'


@dataclass(frozen=True)
class Style:
    color: Tuple[int, int, int]
    fontpath: Path
    fontsize: int
    underline: bool

    @staticmethod
    def parse(s: str) -> 'Style':
        s = s.lstrip('-')
        m = re.search(r'(?:-|^)([0-9]{1,2})pt\b', s)
        if m:
            fontsize = min(30, int(m.group(1)))
            s = s.replace(m.group(), '', 1)
        else:
            fontsize = 12

        if s == 'lesswrong':
            return Style(color=(0x5f, 0x9b, 0x65), fontpath=WARNOCK_PRO_PATH, fontsize=fontsize, underline=False)

        m = re.search('(?:-|^)(' + '|'.join(COLOR_NAME_TO_COLOR.keys()) + r')\b', s)
        if m:
            color = COLOR_NAME_TO_COLOR[m.group(1)]
            s = s.replace(m.group(), '', 1)
        else:
            color = COLOR_NAME_TO_COLOR['darkgreen']

        return Style(color=color, fontpath=ARIAL_PATH, fontsize=fontsize, underline=True)

COLOR_NAME_TO_COLOR = {
    'red'      : (255, 0  , 0  ),
    'darkgreen': (0  , 128, 0  ),
    'darkblue' : (0  , 0  , 128),
    'black'    : (0  , 0  , 0  ),
    'white'    : (255, 255, 255),
    'plainlink' : (0x0a, 0x58, 0xca),
    'lwlinkgreen': (0x5f, 0x9b, 0x65),
}

@functools.lru_cache(maxsize=256)
def render_text(text: str, style: Style, file_format: str = 'png') -> bytes:
    font = ImageFont.truetype(str(style.fontpath.resolve()), style.fontsize)
    w, h = font.getsize(text)
    if style.underline:
        h += 2
    img = Image.new('RGBA', (w, h), color=(255,255,255,0))
    draw = ImageDraw.Draw(img)
    draw.text((0,0), text, fill=style.color, font=font)
    if style.underline:
        draw.line([(0, h-1), (w, h-1)], fill=style.color)
    buf = io.BytesIO()
    img.save(buf, format=file_format)
    return buf.getvalue()


def stupid_file_response(path: Path) -> web.Response:
    '''For some reason, web.FileResponse sometimes results in a 404 even when the file exists. Dodge that.'''
    if path.is_file():
        return web.Response(status=200, body=path.read_bytes(), content_type='text/html' if path.name.endswith('.html') else 'text/css' if path.name.endswith('.css') else 'text/javascript' if path.name.endswith('.js') else 'application/octet-stream')
    return web.Response(status=404)


class WebServer:
    def __init__(self, servicer: Servicer, elm_dist: Path, token_glue: HttpTokenGlue, clock: Callable[[], datetime.datetime] = datetime.datetime.now) -> None:
        self._servicer = servicer
        self._elm_dist = elm_dist
        self._token_glue = token_glue
        self._clock = clock

        self._jinja = jinja2.Environment( # adapted from https://jinja.palletsprojects.com/en/2.11.x/api/#basics
            loader=jinja2.FileSystemLoader(searchpath=[_HERE/'templates'], encoding='utf-8'),
            autoescape=jinja2.select_autoescape(['html', 'xml']),
        )
        self._jinja.undefined = jinja2.StrictUndefined  # raise exception if a template uses an undefined variable; adapted from https://stackoverflow.com/a/39127941/8877656

    def _get_auth_success(self, auth: Optional[mvp_pb2.AuthToken], req: mvp_pb2.GetSettingsRequest = mvp_pb2.GetSettingsRequest()) -> Optional[mvp_pb2.AuthSuccess]:
        if auth is None:
            return None
        get_settings_response = self._servicer.GetSettings(auth, req)
        if get_settings_response.WhichOneof('get_settings_result') != 'ok':
            logger.error('failed to get settings for valid-looking user', data_loss=True, auth=auth, get_settings_response=get_settings_response)
            return None
        return mvp_pb2.AuthSuccess(token=auth, user_info=get_settings_response.ok)

    async def get_static(self, req: web.Request) -> web.StreamResponse:
        filename = req.match_info['filename']
        static_dir = _HERE / 'static'
        return stupid_file_response(static_dir / (static_dir/filename).relative_to(static_dir))

    async def get_wellknown(self, req: web.Request) -> web.StreamResponse:
        path = Path(req.match_info['path'])
        root = Path('/home/public/.well-known')
        try:
            return stupid_file_response(root / ((root/path).absolute().relative_to(root)))
        except Exception:
            raise web.HTTPBadRequest()

    async def get_elm_module(self, req: web.Request) -> web.StreamResponse:
        module = req.match_info['module']
        elmdist = _HERE.parent/'elm'/'dist'
        return stupid_file_response(elmdist / (elmdist/f'{module}.js').relative_to(elmdist))

    async def get_index(self, req: web.Request) -> web.StreamResponse:
        auth = self._token_glue.parse_cookie(req)
        if auth is None:
            return web.HTTPTemporaryRedirect('/welcome')
        else:
            return await self.get_my_stakes(req)

    async def get_fast_bet(self, req: web.Request) -> web.Response:
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('FastBetPage.html').render()
        )

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
        prediction_id = str(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        prediction = get_prediction_resp.prediction
        auth_success = self._get_auth_success(auth, mvp_pb2.GetSettingsRequest(include_relationships_with_users=[prediction.creator]))
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('ViewPredictionPage.html').render(
                title=f'Prediction: by {datetime.datetime.fromtimestamp(prediction.resolves_at_unixtime).strftime("%Y-%m-%d")}, {prediction.prediction}',
                auth_success_pb_b64=pb_b64(auth_success),
                predictions_pb_b64=pb_b64(mvp_pb2.PredictionsById(predictions={prediction_id: prediction})),
                prediction_id=prediction_id,
            ))

    async def get_prediction_img_embed(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        prediction_id = str(req.match_info['prediction_id'])
        get_prediction_resp = self._servicer.GetPrediction(auth, mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        if get_prediction_resp.WhichOneof('get_prediction_result') == 'error':
            return web.Response(status=404, body=str(get_prediction_resp.error))

        assert get_prediction_resp.WhichOneof('get_prediction_result') == 'prediction'
        def format_stake_concisely(n_cents: int) -> str:
            return f'${n_cents//100}'
        prediction = get_prediction_resp.prediction
        stake_text = format_stake_concisely(prediction.maximum_stake_cents)

        if prediction.certainty.high == 1:
            confidence_text = f'{round(prediction.certainty.low*100)}%+'
        else:
            confidence_text = f'{round(prediction.certainty.low*100)}-{round(prediction.certainty.high*100)}%'

        if prediction.resolutions and prediction.resolutions[-1].resolution != mvp_pb2.RESOLUTION_NONE_YET:
            res = prediction.resolutions[-1].resolution
            res_text = "happened" if res == mvp_pb2.RESOLUTION_YES else "didn't happen" if res == mvp_pb2.RESOLUTION_NO  else "INVALID" if res == mvp_pb2.RESOLUTION_INVALID else "???"
            remaining_text = f" (result: {res_text})"
        elif prediction.closes_unixtime < self._clock().timestamp():
            remaining_text = " (closed)"
        elif not (prediction.remaining_stake_cents_vs_skeptics == prediction.remaining_stake_cents_vs_believers == prediction.maximum_stake_cents):
            remaining_text = (
                " ("
                + format_stake_concisely(prediction.remaining_stake_cents_vs_skeptics)
                + ("/" + format_stake_concisely(prediction.remaining_stake_cents_vs_believers) if prediction.remaining_stake_cents_vs_believers < prediction.maximum_stake_cents else "")
                + " remain)"
            )
        else:
            remaining_text = ""

        text = f'[bet: {stake_text} at {confidence_text}{remaining_text}]'
        style = Style.parse(req.match_info['style'])

        return web.Response(content_type='image/png', body=render_text(text=text, style=style, file_format='png'))

    async def get_my_stakes(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        if auth is None:
            return web.HTTPTemporaryRedirect('/login?dest=/my_stakes')
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
        username = Username(str(req.match_info['username']))
        auth_success = self._get_auth_success(auth, req=mvp_pb2.GetSettingsRequest(include_relationships_with_users=[username]))
        relationship = None if (auth_success is None) else auth_success.user_info.relationships.get(username)
        if (relationship is not None) and relationship.trusts_you:
            list_predictions_resp = self._servicer.ListPredictions(auth, mvp_pb2.ListPredictionsRequest(creator=username))
            predictions: Optional[mvp_pb2.PredictionsById] = list_predictions_resp.ok  # TODO: error handling
        else:
            predictions = None
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('ViewUserPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                who=username,
                predictions_pb_b64=pb_b64(predictions),
            ))

    async def get_settings(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        if auth is None:
            return web.HTTPTemporaryRedirect('/login?dest=/settings')
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('SettingsPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
            ))

    async def get_login(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('LoginPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
            ))

    async def accept_invitation(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        nonce = str(req.match_info['nonce'])
        check_invitation_resp = self._servicer.CheckInvitation(auth, mvp_pb2.CheckInvitationRequest(nonce=nonce))
        if check_invitation_resp.WhichOneof('check_invitation_result') == 'error':
            return web.HTTPBadRequest(reason=str(check_invitation_resp.error))
        assert check_invitation_resp.WhichOneof('check_invitation_result') == 'ok'
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('AcceptInvitationPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                recipient=check_invitation_resp.ok.recipient,
                inviter=check_invitation_resp.ok.inviter,
                nonce=nonce,
            ))

    async def verify_email(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        code = str(req.match_info['code'])
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('VerifyEmailPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                code=code,
            ))

    def add_to_app(self, app: web.Application) -> None:

        self._token_glue.add_to_app(app)

        app.router.add_get('/', self.get_index)
        app.router.add_get('/.well-known/{path:.*}', self.get_wellknown)
        app.router.add_get('/static/{filename}', self.get_static)
        app.router.add_get('/elm/{module}.js', self.get_elm_module)
        app.router.add_get('/fast', self.get_fast_bet)
        app.router.add_get('/welcome', self.get_welcome)
        app.router.add_get('/new', self.get_create_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}', self.get_view_prediction_page)
        app.router.add_get('/p/{prediction_id:[0-9]+}/embed{style}.png', self.get_prediction_img_embed)
        app.router.add_get('/my_stakes', self.get_my_stakes)
        app.router.add_get('/username/{username:[a-zA-Z0-9_-]+}', self.get_username)
        app.router.add_get('/settings', self.get_settings)
        app.router.add_get('/login', self.get_login)
        app.router.add_get('/invitation/{nonce}/accept', self.accept_invitation)
        app.router.add_get('/verify_email/{code}', self.verify_email)


def pb_b64(message: Optional[Message]) -> Optional[str]:
    if message is None:
        return None
    return base64.b64encode(message.SerializeToString()).decode('ascii')
