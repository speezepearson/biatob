# Error handling: raise a failure mode, translate it at the edge

## The convention

**Servicers raise. The web layer translates.**

A servicer signals failure by raising an `ApiError` subclass from `core.py` that
names the *failure mode*. The transport decides how to present it:
`api_server` turns it into an HTTP status plus an `ErrorResponse` body;
`web_server` turns it into an error page. Elm reads the status and the body.

```python
# sql_servicer.py -- names the failure, says nothing about HTTP
raise NotLoggedInError('must log in to bet')

# api_server.py -- @translates_api_errors turns it into 401 + ErrorResponse
```

```elm
-- API.elm
postStake : (Result Error Pb.UserPredictionView -> msg) -> Pb.StakeRequest -> Cmd msg
```

A success response body *is* the payload. There is no wrapper.

## The exception hierarchy

Defined in `core.py`. The class names the failure mode; `http_status` is a
presentation detail hanging off it.

| class | status | means |
| --- | --- | --- |
| `ApiError` | 400 | base; an expected, client-facing failure |
| `InvalidRequestError` | 400 | malformed or self-contradictory request |
| `NotLoggedInError` | 401 | needs an actor, didn't get one |
| `BadCredentialsError` | 401 | credentials didn't check out |
| `AlreadyLoggedInError` | 400 | endpoint requires anonymity |
| `ForbiddenError` | 403 | authenticated, but not allowed |
| `NotFoundError` | 404 | base for the lookup failures |
| ├ `NoSuchPredictionError` | 404 | absent *or* not visible to the actor |
| ├ `NoSuchUserError` | 404 | |
| └ `NoSuchInvitationError` | 404 | |
| `ConflictError` | 409 | base; well-formed and permitted, but conflicts with state |
| ├ `AlreadyRegisteredError` | 409 | username taken / email registered |
| ├ `PredictionClosedError` | 409 | betting closed, or already resolved |
| ├ `StakeCapExceededError` | 409 | over the creator's tolerance or the per-prediction cap |
| └ `InvitationAlreadySentError` | 409 | |
| `InternalError` | 500 | our fault, but we have a message worth showing |

Anything that is **not** an `ApiError` is a bug, and surfaces as an opaque 500.

## Two rules that are easy to get wrong

### 1. Servicers raise *domain* errors, never HTTP ones

`core.py` imports no HTTP library, on purpose. `web_server.py` calls servicers
**directly** to render pages — they are not only reached over HTTP. Raising
`aiohttp.web.HTTPNotFound` from a servicer would couple the domain layer to a
web framework and break server-side rendering.

`@translates_api_errors` is applied per-handler rather than as app middleware
for the same reason: the API and the rendered pages share one aiohttp
`Application`, and an `ApiError` raised while rendering a page must become HTML,
not a protobuf body.

### 2. `elm/http` throws the error body away

The one that bites. `Http.expectBytes`/`expectJson` discard the body on a
non-2xx:

```elm
-- elm/http 2.0.0, Http.elm:520
BadStatus_ metadata _ -> Err (BadStatus metadata.statusCode)
--                  ^ the body, dropped
```

So reading the server's explanation is impossible through the normal `expect`
helpers — you'd get `"HTTP error code 401"` instead of `"bad password"`.
`API.call` hand-rolls `Http.expectBytesResponse` and handles the `BadStatus_`
branch itself. elm/http's own docs recommend exactly this.

`API.Error` distinguishes the two kinds of failure:

```elm
type Error
  = ApiError { status : Int, catchall : String }  -- the server explained itself
  | TransportError Http.Error                     -- nobody to quote
```

## What this replaced

Every endpoint used to answer with a discriminated union, and report failure as
**HTTP 200** with an `error` arm set:

```proto
message StakeResponse {
  oneof stake_result {
    UserPredictionView ok = 1;
    Error error = 2;
  }
  message Error { string catchall = 1; }
}
```

Why it had to go:

- **200 for a failure is a lie.** Monitoring, proxies, logs, and devtools all
  believed every request succeeded.
- **The union bought nothing.** 16 of 18 error types were nothing but
  `{catchall: string}`. Of the two structured variants, `no_such_prediction` was
  never read by a single line of Elm.
- **`oneof` is optional in proto3**, so every response modelled "neither ok nor
  error" — an impossible state that HTTP cannot even express, but which forced a
  dead arm into all 18 `simplify*Response` helpers and a `Debug.todo` into
  `Utils.must*Result`.
- **It hid real bugs.** See below.

## Bugs this surfaced

Kept here because they're the argument for the change:

- **`set_cookie` on a failed login.** It sat inside
  `if WhichOneof(...) == 'ok'`. Correct, but only by inspection. Now failure
  leaves via an exception, so the cookie line is *unreachable* on the failure
  path.
- **A broken test fixture, hidden for who knows how long.**
  `test_web_server` POSTed `RegisterUsername` with no `proof_of_email`. That
  fails the HMAC check — but came back 200 with an error arm, so
  `assert status == 200` passed, no cookie was set, and every `logged_in=True`
  case silently ran **logged out**.
- **`ViewUser` never checked for an error at all**, and read `.ok` off the
  response regardless — silently rendering an empty prediction list.
- **`view_prediction()` returns `Optional`,** and protobuf accepts `None` for a
  message field by leaving it unset. So `StakeResponse(ok=None)` would have
  produced a response with *neither* arm — the impossible state above. mypy
  caught this the moment the signatures said `-> UserPredictionView`.

## Open question: multiple failures sharing a status

The status is currently the machine-readable code, and `catchall` is human
prose. If an endpoint ever needs two distinct failures that share a status, add
a flat `string code` to `ErrorResponse` — not a `oneof`. A flat enum-ish string
survives the OpenAPI→Elm trip cleanly (see `spike/openapi-elm/FINDINGS.md`),
which is much of why the union is gone.
