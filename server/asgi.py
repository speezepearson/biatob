"""The biatob server as a single FastAPI/uvicorn app: the JSON... no -- for now,
the *protobuf* API, the server-rendered pages, the embed images, static files,
cookie auth, and the background email jobs. This replaces the old aiohttp trio
(api_server / web_server / http_glue).

Phase 3a of the protobuf->pydantic migration deliberately keeps the wire
protobuf: endpoints still read and write serialized mvp_pb2 messages, and the
Elm client is untouched. Phase B swaps the wire to JSON.
"""

import base64
import datetime
import contextlib
from pathlib import Path
from typing import AbstractSet, Awaitable, Callable, Optional, Sequence

from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from google.protobuf.message import Message
import jinja2
import structlog

from .core import ApiError, AuthorizingUsername, ForgottenTokenError, Servicer, TokenMint, Username, token_owner
from .rendering import Style, render_text
from .tokens import AuthToken
from .protobuf import mvp_pb2

logger = structlog.get_logger()

_HERE = Path(__file__).parent
_AUTH_COOKIE_NAME = 'auth'
_OCTET_STREAM = 'application/octet-stream'

# The 16 endpoints the API exposes over HTTP. (ListMyStakes / ListPredictions /
# CheckInvitation are servicer methods too, but the server-rendered pages call
# them directly -- they were never HTTP endpoints.)
_API_METHODS = [
    'Whoami', 'SignOut', 'SendVerificationEmail', 'RegisterUsername', 'LogInUsername',
    'CreatePrediction', 'GetPrediction', 'Stake', 'Follow', 'Resolve', 'SetTrusted',
    'GetUser', 'ChangePassword', 'GetSettings', 'SendInvitation', 'AcceptInvitation',
]


def pb_b64(message: Optional[Message]) -> Optional[str]:
    if message is None:
        return None
    return base64.b64encode(message.SerializeToString()).decode('ascii')


def build_app(
    servicer: Servicer,
    token_mint: TokenMint,
    elm_dist: Path,
    clock: Callable[[], datetime.datetime] = datetime.datetime.now,
    on_startup: Optional[Callable[[], None]] = None,
) -> FastAPI:

    jinja = jinja2.Environment(
        loader=jinja2.FileSystemLoader(searchpath=[_HERE / 'templates'], encoding='utf-8'),
        autoescape=jinja2.select_autoescape(['html', 'xml']),
    )
    jinja.undefined = jinja2.StrictUndefined

    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI):
        if on_startup is not None:
            on_startup()
        yield

    # No auto-docs routes: they'd shadow username paths and expose internals.
    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    # --- auth cookie ---------------------------------------------------------

    def auth_token(request: Request) -> Optional[AuthToken]:
        cookie = request.cookies.get(_AUTH_COOKIE_NAME)
        if cookie is None:
            return None
        token = token_mint.unseal_token(cookie)
        return None if (token_mint.check_token(token) is None) else token

    def set_auth_cookie(response: Response, owner: Username) -> None:
        response.set_cookie(_AUTH_COOKIE_NAME, token_mint.seal_token(token_mint.mint_token(owner)))

    def get_auth_success(auth: Optional[AuthToken], req: mvp_pb2.GetSettingsRequest = mvp_pb2.GetSettingsRequest()) -> Optional[mvp_pb2.AuthSuccess]:
        if auth is None:
            return None
        try:
            user_info = servicer.GetSettings(token_owner(auth), req)
        except ApiError as e:
            logger.error('failed to get settings for valid-looking user', data_loss=True, auth=auth, error=e.catchall)
            return None
        return mvp_pb2.AuthSuccess(token=mvp_pb2.AuthToken(owner=auth.owner), user_info=user_info)

    def render(template: str, **kwargs) -> HTMLResponse:
        return HTMLResponse(jinja.get_template(template).render(**kwargs))

    @app.exception_handler(ForgottenTokenError)
    async def _forgotten_token(request: Request, exc: ForgottenTokenError) -> Response:
        logger.exception(exc)
        resp = Response(status_code=500, content="I, uh, may have accidentally obliterated your entire account. Crap. I'm sorry. Refresh the page to try again?")
        resp.delete_cookie(_AUTH_COOKIE_NAME)
        return resp

    # --- API (protobuf wire) -------------------------------------------------

    def make_api_route(method_name: str) -> Callable[[Request], Awaitable[Response]]:
        request_cls = getattr(mvp_pb2, f'{method_name}Request')

        async def route(http_req: Request) -> Response:
            req = request_cls()
            req.ParseFromString(await http_req.body())
            actor = token_owner(auth_token(http_req))
            try:
                resp = getattr(servicer, method_name)(actor, req)
            except ApiError as e:
                logger.info('api error', path=http_req.url.path, status=e.http_status, catchall=e.catchall)
                return Response(status_code=e.http_status, media_type=_OCTET_STREAM,
                                content=mvp_pb2.ErrorResponse(catchall=e.catchall).SerializeToString())
            http_resp = Response(media_type=_OCTET_STREAM, content=resp.SerializeToString())
            if method_name in ('LogInUsername', 'RegisterUsername'):
                set_auth_cookie(http_resp, Username(resp.token.owner))
            elif method_name == 'SignOut':
                http_resp.delete_cookie(_AUTH_COOKIE_NAME)
            return http_resp

        return route

    for name in _API_METHODS:
        app.post(f'/api/{name}')(make_api_route(name))

    # --- server-rendered pages ----------------------------------------------

    @app.get('/', response_class=HTMLResponse)
    async def index(request: Request):
        if auth_token(request) is None:
            return RedirectResponse('/welcome')
        return await my_stakes(request)

    @app.get('/welcome', response_class=HTMLResponse)
    async def welcome(request: Request):
        return render('Welcome.html', auth_success_pb_b64=pb_b64(get_auth_success(auth_token(request))))

    @app.get('/fast', response_class=HTMLResponse)
    async def fast_bet(request: Request):
        return render('FastBetPage.html')

    @app.get('/new', response_class=HTMLResponse)
    async def create_prediction_page(request: Request):
        return render('CreatePredictionPage.html', auth_success_pb_b64=pb_b64(get_auth_success(auth_token(request))))

    @app.get('/my_stakes', response_class=HTMLResponse)
    async def my_stakes(request: Request):
        auth = auth_token(request)
        if auth is None:
            return RedirectResponse('/login?dest=/my_stakes')
        try:
            predictions = servicer.ListMyStakes(token_owner(auth), mvp_pb2.ListMyStakesRequest())
        except ApiError as e:
            return Response(status_code=e.http_status, content=e.catchall)
        return render('MyStakesPage.html',
                      auth_success_pb_b64=pb_b64(get_auth_success(auth)),
                      predictions_pb_b64=pb_b64(predictions))

    @app.get('/settings', response_class=HTMLResponse)
    async def settings(request: Request):
        auth = auth_token(request)
        if auth is None:
            return RedirectResponse('/login?dest=/settings')
        return render('SettingsPage.html', auth_success_pb_b64=pb_b64(get_auth_success(auth)))

    @app.get('/login', response_class=HTMLResponse)
    async def login(request: Request):
        return render('LoginPage.html', auth_success_pb_b64=pb_b64(get_auth_success(auth_token(request))))

    @app.get('/signup', response_class=HTMLResponse)
    async def signup(request: Request):
        return render('SignupPage.html', auth_success_pb_b64=pb_b64(get_auth_success(auth_token(request))))

    @app.get('/p/{prediction_id}', response_class=HTMLResponse)
    async def view_prediction_page(prediction_id: str, request: Request):
        if not prediction_id.isdigit():
            return Response(status_code=404, content='no such prediction')
        auth = auth_token(request)
        try:
            prediction = servicer.GetPrediction(token_owner(auth), mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        except ApiError as e:
            return Response(status_code=e.http_status, content=e.catchall)
        auth_success = get_auth_success(auth, mvp_pb2.GetSettingsRequest(include_relationships_with_users=[prediction.creator]))
        return render('ViewPredictionPage.html',
                      title=f'Prediction: by {datetime.datetime.fromtimestamp(prediction.resolves_at_unixtime).strftime("%Y-%m-%d")}, {prediction.prediction}',
                      auth_success_pb_b64=pb_b64(auth_success),
                      predictions_pb_b64=pb_b64(mvp_pb2.PredictionsById(predictions={prediction_id: prediction})),
                      prediction_id=prediction_id)

    @app.get('/p/{prediction_id}/embed{style}.png')
    async def prediction_img_embed(prediction_id: str, style: str, request: Request):
        if not prediction_id.isdigit():
            return Response(status_code=404, content='no such prediction')
        auth = auth_token(request)
        try:
            prediction = servicer.GetPrediction(token_owner(auth), mvp_pb2.GetPredictionRequest(prediction_id=prediction_id))
        except ApiError as e:
            return Response(status_code=e.http_status, content=e.catchall)

        def format_stake_concisely(n_cents: int) -> str:
            return f'${n_cents//100}'
        stake_text = format_stake_concisely(prediction.maximum_stake_cents)

        if prediction.certainty.high == 1:
            confidence_text = f'{round(prediction.certainty.low*100)}%+'
        else:
            confidence_text = f'{round(prediction.certainty.low*100)}-{round(prediction.certainty.high*100)}%'

        if prediction.resolution and prediction.resolution.resolution != mvp_pb2.RESOLUTION_NONE_YET:
            res = prediction.resolution.resolution
            res_text = "correct" if res == mvp_pb2.RESOLUTION_YES else "incorrect" if res == mvp_pb2.RESOLUTION_NO else "n/a" if res == mvp_pb2.RESOLUTION_INVALID else "???"
            remaining_text = f" (resolved: {res_text})"
        elif prediction.closes_unixtime < clock().timestamp():
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
        return Response(media_type='image/png', content=render_text(text=text, style=Style.parse(style), file_format='png'))

    @app.get('/invitation/{nonce}/accept', response_class=HTMLResponse)
    async def accept_invitation(nonce: str, request: Request):
        auth = auth_token(request)
        try:
            invitation = servicer.CheckInvitation(token_owner(auth), mvp_pb2.CheckInvitationRequest(nonce=nonce))
        except ApiError as e:
            return Response(status_code=e.http_status, content=e.catchall)
        return render('AcceptInvitationPage.html',
                      auth_success_pb_b64=pb_b64(get_auth_success(auth)),
                      recipient=invitation.recipient, inviter=invitation.inviter, nonce=nonce)

    @app.get('/verify_email/{code}', response_class=HTMLResponse)
    async def init_user(code: str, request: Request):
        email = token_mint.check_proof_of_email(code)
        if email is None:
            return Response(status_code=400, content='This email-verification link is invalid or has expired.')
        return render('InitUserPage.html',
                      auth_success_pb_b64=pb_b64(get_auth_success(auth_token(request))),
                      email=email, proof_of_email_token=code)

    # --- static-ish ----------------------------------------------------------

    @app.get('/static/{filename}')
    async def static(filename: str):
        return _file_response(_HERE / 'static', filename)

    @app.get('/elm/{module}.js')
    async def elm_module(module: str):
        return _file_response(elm_dist, f'{module}.js')

    @app.get('/.well-known/{path:path}')
    async def wellknown(path: str):
        return _file_response(Path('/home/public/.well-known'), path)

    def render_user_page(username: str, request: Request) -> Response:
        auth = auth_token(request)
        auth_success = get_auth_success(auth, mvp_pb2.GetSettingsRequest(include_relationships_with_users=[Username(username)]))
        try:
            predictions = servicer.ListPredictions(token_owner(auth), mvp_pb2.ListPredictionsRequest(creator=username))
        except ApiError as e:
            return Response(status_code=e.http_status, content=e.catchall)
        return render('ViewUserPage.html',
                      auth_success_pb_b64=pb_b64(auth_success),
                      who=username, predictions_pb_b64=pb_b64(predictions))

    @app.get('/username/{username}', response_class=HTMLResponse)
    async def username_page_explicit(username: str, request: Request):
        return render_user_page(username, request)

    @app.get('/u/{username}', response_class=HTMLResponse)
    async def username_page_short(username: str, request: Request):
        return render_user_page(username, request)

    # The bare-username catch-all must be registered LAST -- it matches any
    # single top-level segment, so every fixed route above has to win first.
    @app.get('/{username}', response_class=HTMLResponse)
    async def username_page(username: str, request: Request):
        return render_user_page(username, request)

    return app


def _file_response(root: Path, relpath: str) -> Response:
    try:
        path = (root / relpath).resolve()
        path.relative_to(root.resolve())  # reject traversal outside root
        return Response(content=path.read_bytes(), media_type=_guess_media_type(path))
    except (ValueError, FileNotFoundError, IsADirectoryError):
        return Response(status_code=404, content='not found')


def _guess_media_type(path: Path) -> str:
    import mimetypes
    return mimetypes.guess_type(str(path))[0] or 'application/octet-stream'


def _reserved_toplevel_path_segments() -> AbstractSet[str]:
    app = build_app(servicer=None, token_mint=None, elm_dist=Path('.'))  # type: ignore[arg-type]
    reserved = set()
    for route in app.routes:
        path = getattr(route, 'path', '')
        first = path.lstrip('/').split('/')[0]
        if first and not first.startswith('{'):
            reserved.add(first)
    return reserved


RESERVED_TOPLEVEL_PATH_SEGMENTS = _reserved_toplevel_path_segments()
