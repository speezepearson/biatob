# Error handling: HTTP status codes, not `oneof` result arms

## The old pattern

Every endpoint in `mvp.proto` used to answer with a discriminated union:

```proto
message GetPredictionResponse {
  oneof get_prediction_result {
    UserPredictionView prediction = 1;
    Error error = 2;
  }
  message Error { string catchall = 1; }
}
```

Failures were reported as **HTTP 200** with an `error` arm set. Two endpoints
(`LogInUsername`, `GetPrediction`) have been migrated off this; the other 16
still use it.

## The new pattern

The 200 body is the payload itself. Failures are an HTTP status code plus an
`ErrorResponse` body:

```proto
message ErrorResponse { string catchall = 1; }
```

**Server:** servicers `raise` an `ApiError` subclass from `core.py`. Each
subclass carries an `http_status`.

```python
class ApiError(Exception):          # 400
class AuthenticationError(ApiError) # 401
class NoSuchPredictionError(ApiError)  # 404
```

**Elm:** call the endpoint via `API.call` rather than `API.hit`, and get back
`Result API.Error payload`.

## Why it's better here

- **HTTP 200 for a failure is a lie.** Monitoring, proxies, logs, and browser
  devtools all believed every request succeeded.
- **The union bought almost nothing.** 16 of the 18 error types were nothing but
  `{catchall: string}`. Only two had a real variant, and one of those
  (`GetPredictionResponse.Error.no_such_prediction`) was never read by a single
  line of Elm.
- **It deletes an impossible state.** `oneof` is optional in proto3, so every
  response modelled "neither ok nor error", forcing a dead
  `Nothing -> Err "neither Ok nor Error in protobuf"` arm into all 18
  `simplify*Response` helpers.
- **The cookie bug class goes away.** `set_cookie` used to sit inside
  `if WhichOneof(...) == 'ok'`. Now failure leaves via an exception, so the
  cookie line is simply unreachable on the failure path.
- **It de-risks the OpenAPI migration.** `oneof` is the single hardest thing to
  carry through an OpenAPI→Elm generator (see `spike/openapi-elm/FINDINGS.md`).
  Every endpoint migrated here is one fewer discriminated union to translate.

## Gotchas worth knowing

### Servicers must raise *domain* errors, not HTTP ones

`web_server.py` calls the servicer **directly** to render pages server-side --
the servicer is not only reached over HTTP. So `ApiError` carries an
`http_status` but imports no HTTP library, and each transport translates:
`api_server` into a status + protobuf body, `web_server` into an error page.

Raising `aiohttp.web.HTTPNotFound` from a servicer would couple the domain layer
to a web framework and break the SSR path.

### `elm/http` throws the error body away

This is the one that bites. `Http.expectBytes`/`expectJson` discard the response
body on a non-2xx:

```elm
-- elm/http 2.0.0, Http.elm
BadStatus_ metadata _ -> Err (BadStatus metadata.statusCode)
--                  ^ the body, dropped
```

So "read the payload to find out what went wrong" is impossible through the
normal `expect` helpers. `API.call` hand-rolls `Http.expectBytesResponse` and
handles the `BadStatus_` branch itself. elm/http's own docs recommend exactly
this.

### Partial migration needs shims

`RegisterUsername` (still on `oneof`) calls `LogInUsername` (migrated)
internally, so it has to catch `ApiError` and translate back into its own error
arm. Expect one of these at every boundary between the two conventions; they
delete themselves as the migration completes.

## Migrating the remaining 16

1. Delete the `FooResponse` message from `mvp.proto`; the endpoint now returns
   its payload type directly.
2. In `sql_servicer.py`, replace `return FooResponse(error=...)` with a raise.
   Add an `ApiError` subclass if no existing status fits.
3. Add `@translates_api_errors` to the handler in `api_server.py`.
4. If `web_server.py` calls it for SSR, wrap in `try/except ApiError`.
5. In `test_utils.py`, `FooOk` just calls; `FooErr` becomes `pytest.raises`.
6. In `API.elm`, switch `hit` to `call` and point the decoder at the payload.
7. Update the `Result Http.Error Pb.FooResponse` type in each caller's `Msg`.
8. Delete `simplifyFooResponse` if the caller can use `errorToString` directly.

## Open question: multiple failures sharing a status

Right now the HTTP status *is* the machine-readable error code, and `catchall`
is human-readable prose. If an endpoint ever needs two distinct failures that
share a status, add a machine-readable `string code` field to `ErrorResponse` --
not a `oneof`. A flat enum-ish string survives the OpenAPI→Elm trip cleanly,
which is the whole point of having left the union behind.
