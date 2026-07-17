import base64
import datetime
import functools
import io
from pathlib import Path
import re
from typing import AbstractSet, Callable, Optional, Tuple

from aiohttp import web
from attr import dataclass
from google.protobuf.message import Message
import jinja2
from PIL import Image, ImageDraw, ImageFont  # type: ignore
import structlog

from .core import ApiError, AuthorizingUsername, Servicer, TokenMint, Username, token_owner
from .tokens import AuthToken
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
    _,_,w, h = font.getbbox(text)
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
    def __init__(self, servicer: Servicer, elm_dist: Path, token_glue: HttpTokenGlue, token_mint: TokenMint, clock: Callable[[], datetime.datetime] = datetime.datetime.now) -> None:
        self._servicer = servicer
        self._elm_dist = elm_dist
        self._token_glue = token_glue
        self._token_mint = token_mint
        self._clock = clock

        self._jinja = jinja2.Environment( # adapted from https://jinja.palletsprojects.com/en/2.11.x/api/#basics
            loader=jinja2.FileSystemLoader(searchpath=[_HERE/'templates'], encoding='utf-8'),
            autoescape=jinja2.select_autoescape(['html', 'xml']),
        )
        self._jinja.undefined = jinja2.StrictUndefined  # raise exception if a template uses an undefined variable; adapted from https://stackoverflow.com/a/39127941/8877656

    def _get_auth_success(self, auth: Optional[AuthToken], req: mvp_pb2.GetSettingsRequest = mvp_pb2.GetSettingsRequest()) -> Optional[mvp_pb2.AuthSuccess]:
        if auth is None:
            return None
        try:
            user_info = self._servicer.GetSettings(token_owner(auth), req)
        except ApiError as e:
            logger.error('failed to get settings for valid-looking user', data_loss=True, auth=auth, error=e.catchall)
            return None
        return mvp_pb2.AuthSuccess(token=mvp_pb2.AuthToken(owner=auth.owner), user_info=user_info)

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
        try:
            prediction = self._servicer.GetPrediction(token_owner(auth), mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        except ApiError as e:
            return web.Response(status=e.http_status, body=e.catchall)

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
        prediction_id = str(req.match_info['prediction_id'])
        try:
            prediction = self._servicer.GetPrediction(token_owner(auth), mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        except ApiError as e:
            return web.Response(status=e.http_status, body=e.catchall)

        def format_stake_concisely(n_cents: int) -> str:
            return f'${n_cents//100}'
        stake_text = format_stake_concisely(prediction.maximum_stake_cents)

        if prediction.certainty.high == 1:
            confidence_text = f'{round(prediction.certainty.low*100)}%+'
        else:
            confidence_text = f'{round(prediction.certainty.low*100)}-{round(prediction.certainty.high*100)}%'

        if prediction.resolution and prediction.resolution.resolution != mvp_pb2.RESOLUTION_NONE_YET:
            res = prediction.resolution.resolution
            res_text = "correct" if res == mvp_pb2.RESOLUTION_YES else "incorrect" if res == mvp_pb2.RESOLUTION_NO  else "n/a" if res == mvp_pb2.RESOLUTION_INVALID else "???"
            remaining_text = f" (resolved: {res_text})"
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
        try:
            predictions = self._servicer.ListMyStakes(token_owner(auth), mvp_pb2.ListMyStakesRequest())
        except ApiError as e:
            return web.Response(status=e.http_status, body=e.catchall)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('MyStakesPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                predictions_pb_b64=pb_b64(predictions),
            ))

    async def get_username(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        username = Username(str(req.match_info['username']))
        auth_success = self._get_auth_success(auth, req=mvp_pb2.GetSettingsRequest(include_relationships_with_users=[username]))
        try:
            predictions = self._servicer.ListPredictions(token_owner(auth), mvp_pb2.ListPredictionsRequest(creator=username))
        except ApiError as e:
            return web.Response(status=e.http_status, body=e.catchall)
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
        try:
            invitation = self._servicer.CheckInvitation(token_owner(auth), mvp_pb2.CheckInvitationRequest(nonce=nonce))
        except ApiError as e:
            return web.Response(status=e.http_status, body=e.catchall)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('AcceptInvitationPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                recipient=invitation.recipient,
                inviter=invitation.inviter,
                nonce=nonce,
            ))

    async def signup(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('SignupPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
            ))

    async def init_user(self, req: web.Request) -> web.Response:
        auth = self._token_glue.parse_cookie(req)
        auth_success = self._get_auth_success(auth)
        proof_token = str(req.match_info['code'])
        email = self._token_mint.check_proof_of_email(proof_token)
        if email is None:
            return web.Response(status=400, body='This email-verification link is invalid or has expired.')
        return web.Response(
            content_type='text/html',
            body=self._jinja.get_template('InitUserPage.html').render(
                auth_success_pb_b64=pb_b64(auth_success),
                email=email,
                proof_of_email_token=proof_token,
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
        app.router.add_get('/settings', self.get_settings)
        app.router.add_get('/login', self.get_login)
        app.router.add_get('/invitation/{nonce}/accept', self.accept_invitation)
        app.router.add_get('/verify_email/{code}', self.init_user)
        app.router.add_get('/signup', self.signup)
        app.router.add_get('/username/{username:[a-zA-Z0-9_-]+}', self.get_username)
        app.router.add_get('/u/{username:[a-zA-Z0-9_-]+}', self.get_username)
        app.router.add_get('/{username:[a-zA-Z0-9_-]+}', self.get_username)

def _reserved_toplevel_path_segments() -> AbstractSet[str]:
    server = WebServer(servicer=None, elm_dist=None, token_glue=HttpTokenGlue(token_mint=TokenMint(secret_key=b'')), token_mint=TokenMint(secret_key=b''))  # type: ignore
    app = web.Application()
    server.add_to_app(app)
    return {
        path.lstrip('/').split('/')[0]
        for path in (r.get_info().get('path') for r in app.router.routes())
        if path
    }
RESERVED_TOPLEVEL_PATH_SEGMENTS = _reserved_toplevel_path_segments()


def pb_b64(message: Optional[Message]) -> Optional[str]:
    if message is None:
        return None
    return base64.b64encode(message.SerializeToString()).decode('ascii')
