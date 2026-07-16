# Spike: is Protobuf -> Pydantic + FastAPI + OpenAPI->Elm viable?

**Verdict: yes, the Elm generator is good enough. Phase 3 is viable.**

This spike exists to answer one question before any migration work starts: when
we throw away `protoc-gen-elm`, is what we get back at least as good? The whole
API in `protobuf/mvp.proto` is built on `oneof` Ok/Error result types, and
`oneof` is the thing OpenAPI generators historically handle worst. If the
generated Elm couldn't express that as a real custom type, the migration would
be a downgrade and should not happen.

It can. Everything below is reproducible with `./run.sh`.

## What was tested

The `LogInUsername` slice, chosen because it transitively exercises every proto
feature the rest of the API relies on:

| proto feature | where |
| --- | --- |
| `oneof` Ok/Error result | `LogInUsernameResponse` — the crux |
| nested `message Error` | `LogInUsernameResponse.Error` |
| `bytes` | `AuthToken.hmac_of_rest`, `HashedPassword.salt`/`.scrypt` |
| `map<string, X>` | `GenericUserInfo.invitations`, `.relationships` |
| second `oneof` | `GenericUserInfo.login_type` |
| empty message | `GenericUserInfo.Invitation` |

Tooling: pydantic 2.13, FastAPI 0.139, [`elm-open-api`](https://github.com/wolfadex/elm-open-api)
(**not** `openapi-generator`'s dated Elm target), elm 0.19.1 — the version the
repo pins.

The test is genuinely end-to-end, not a schema inspection: `app.py` is a real
FastAPI app, its real HTTP responses are captured verbatim into
`sample_ok.json` / `sample_err.json`, and `elm-check/tests/RoundTripTest.elm`
feeds exactly those bytes to the generated decoders. **4/4 passing**, compiled
with elm 0.19.1.

## The good news

The `oneof` comes out as a real Elm custom type you can `case` on:

```elm
type LogInUsernameResultError_Or_LogInUsernameResultOk
    = LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultError LogInUsernameResultError
    | LogInUsernameResultError_Or_LogInUsernameResultOk__LogInUsernameResultOk   LogInUsernameResultOk
```

Dispatch is correct, and not by accident. The generator emits
`Json.Decode.oneOf [try Error, try Ok]` — try-in-order rather than a
discriminator lookup, which looks alarming — but each arm's decoder independently
validates its own discriminator literal (`if andThenUnpack == "ok" then ... else
Json.Decode.fail`). So it is genuinely discriminated, just implemented by
backtracking. It does not rely on the arms happening to have disjoint fields.

**One real improvement over the status quo.** Today's protobuf Elm is:

```elm
type alias LogInUsernameResponse =
    { logInUsernameResult : Maybe LogInUsernameResult }   -- Maybe!
```

That `Maybe` is why all 18 `simplify*Response` helpers in `elm/src/API.elm` carry
a dead arm: `Nothing -> Err "Invalid server response (neither Ok nor Error in
protobuf)"`. Under OpenAPI the response *is* the union — no `Maybe`, no
impossible state, and those 18 dead arms delete themselves.

## The cost

**Constructor names are ugly and can't be fixed by the generator.** Wrapping the
union in a pydantic `RootModel` gets you `type alias LogInUsernameResponse =
LogInUsernameResultError_Or_LogInUsernameResultOk`, which fixes the *type* name —
but the *constructors* keep the long form, and you `case` on constructors, so the
noise lands at every use site. Mitigation: a thin hand-written adapter mapping
the generated union to a clean local type. That is precisely what `API.elm`'s
`simplify*Response` functions already do today, so this is a rewrite of an
existing layer, not a new one.

**One extra field hop.** Protobuf attaches the payload straight to the
constructor (`LogInUsernameResultOk AuthSuccess`); OpenAPI attaches the wrapper
record, so it's `r.ok` rather than `r`. Minor, but it touches every call site.

**FastAPI's 422 machinery leaks into the generated Elm** as `HTTPValidationError`,
`ValidationError`, and an `Int_Or_String` union. Cosmetic noise, but it's in the
public API of the generated module.

## Landmines found (these change the Phase 1 advice)

### 1. `pydantic.Base64Bytes` silently corrupts data. Do not use it.

This is the big one, and it directly contradicts the "just use `Base64Bytes`"
advice from the original writeup. Its semantics are **inverted**: it base64-
*decodes* on validation, so handing it raw bytes from Python mangles them:

```python
class M(BaseModel): b: Base64Bytes
M(b=b'\xde\xad\xbe\xef').b   # == b''   -- no error raised
M(b=b'abc!')                 # ValidationError  -- inconsistent!
```

Whether you get silent corruption or a loud error depends on whether your random
bytes happen to be valid base64. `core.new_hashed_password()` does exactly this
with `secrets.token_bytes(4)`, so a naive port would silently store empty salts
for a fraction of users — an auth bug that no test would catch unless it asserted
on the salt.

The working pattern is in `models.py` as `ProtoBytes`: keep `bytes` as the
Python-side type, base64 only at the JSON boundary via
`BeforeValidator`/`PlainSerializer`. Verified to round-trip
`b'\x00\x01\xfe\xff\x80'` intact.

### 2. Use `format: byte`, not `format: base64`.

`Base64Bytes` advertises `format: base64`, which `elm-open-api` doesn't recognise —
it warns and degrades the field to `String`. Declaring `format: byte` (via
`WithJsonSchema`) gets real `Bytes.Bytes` in Elm, matching today's protobuf types
exactly, with zero warnings. `ProtoBytes` does this.

Note this needs `danfishgold/base64-bytes` in `elm.json` — which the repo
**already** depends on. No new Elm dependency.

### 3. Defaults become `Maybe`s. Make wire fields required.

A pydantic field with a default is omitted from OpenAPI `required`, and the
generator wraps it in `Maybe`. A defaulted *and* nullable field gets you a
`Maybe (Nullable ...)` double-option. Dropping the defaults:

```elm
-- with `= Field(default_factory=dict)` / `= None`
{ invitations : Maybe (Dict.Dict String Invitation)
, login_type  : Maybe (OpenApi.Common.Nullable LoginTypePassword) }

-- required (no default)
{ invitations : Dict.Dict String Invitation
, login_type  : OpenApi.Common.Nullable LoginTypePassword }
```

Costs the server an explicit `invitations={}`; buys the Elm side a pile of
deleted `Maybe`-unwrapping. Today's protobuf Elm is *worse* here — it generates
`Dict String (Maybe GenericUserInfoInvitation)`, with a pointless `Maybe` inside
the dict.

### 4. `alias_generator=to_camel` avoids renaming every field in 5,253 lines of Elm.

By default the generated Elm keeps snake_case field names (`email_address`), but
today's protobuf Elm is camelCase (`emailAddress`). That diff would touch every
field access in the entire Elm codebase for no benefit. Setting
`ConfigDict(alias_generator=to_camel, populate_by_name=True)` emits camelCase JSON
while keeping snake_case on the Python side, so today's Elm field names survive
untouched and the JSON is idiomatic. Verified; not yet applied to `models.py`
(it would obscure the plain-mapping demo).

### 5. Set `operation_id` explicitly.

Without it, FastAPI derives one from function name + path + method and the
generator produces `logInUsernameApiLogInUsernamePost`. With
`operation_id="logInUsername"` you get `logInUsername`.

## Recommendation

Phase 3 is viable — proceed with the phased plan. The generator clears the bar,
and on the `Maybe`-wrapped-union and `Maybe`-inside-`Dict` points it beats
`protoc-gen-elm`. The residual cost is ugly constructor names, addressed by an
adapter layer that already exists in spirit.

The `Base64Bytes` landmine is the most valuable thing here, and it is a **Phase 1**
concern — it bites the moment `HashedPassword` and `AuthToken` become Pydantic
models, long before any Elm is regenerated. Whoever does Phase 1 should read
finding #1 first.

## Layout

| path | what |
| --- | --- |
| `models.py` | hand-written Pydantic translation of the proto slice |
| `app.py` | the FastAPI app (canned handler; the point is the wire shape) |
| `gen_openapi.py` | dumps `openapi.json` |
| `openapi.json` | **generated** — committed so the oneOf/discriminator is reviewable |
| `sample_ok.json`, `sample_err.json` | **generated** — real captured HTTP responses |
| `elm-check/src/` | **generated** by `elm-open-api` — committed so the output is reviewable in the diff |
| `elm-check/tests/RoundTripTest.elm` | hand-written; the actual test |
| `run.sh` | reproduces all of the above from scratch |

Nothing here is wired into `dodo.py` or the real build. The whole directory is
throwaway and should be deleted once the migration decision is acted on.

## Not covered

- The recursive `ResolutionEvent.prior_revision` — pydantic handles self-reference,
  but the Elm generator's output for it is unverified. Worth a follow-up probe.
- `SavedCreatedPredictionFormState` in localStorage (`CreatePrediction.elm:290`).
- The SSR bootstrap path (`web_server.pb_b64` -> Elm flags).
- Token/cookie signing and `ProofOfEmail` — deliberately out of scope; these are
  Phase 1 concerns and don't depend on the generator.
