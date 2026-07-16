"""Pydantic translation of the LogInUsername slice of protobuf/mvp.proto.

This slice was chosen because it transitively exercises every proto feature that
the rest of the API depends on:

  - `oneof log_in_username_result` -> the Ok/Error result union that EVERY
    endpoint in mvp.proto is built on. This is the crux of the spike.
  - nested `message Error` inside the response
  - `bytes` fields (AuthToken.hmac_of_rest, HashedPassword.salt/.scrypt)
  - `map<string, X>` (GenericUserInfo.invitations, .relationships)
  - a second, single-armed `oneof login_type`
  - an empty message (GenericUserInfo.Invitation)

If the generated Elm is good for this slice, it will be good for the whole API.
"""

import base64
from typing import Annotated, Any, Dict, Literal, Union

from pydantic import BaseModel, BeforeValidator, Field, PlainSerializer, WithJsonSchema


# --- bytes handling ----------------------------------------------------------
#
# DO NOT use pydantic's `Base64Bytes` here. Its semantics are inverted from what
# you want: it base64-DECODES on validation, so constructing a model with raw
# bytes from Python silently mangles them --
#
#     class M(BaseModel): b: Base64Bytes
#     M(b=b'\xde\xad\xbe\xef').b  ==  b''      # no error raised!
#
# ...which is exactly what core.new_hashed_password() does with
# secrets.token_bytes(4). It corrupts to empty for some inputs and raises for
# others, depending on whether the raw bytes happen to be valid base64.
#
# Instead: keep `bytes` as the Python-side type and base64 only at the JSON
# boundary. `format: byte` (not `base64`) is the format elm-open-api recognises.

def _decode_bytes(v: Any) -> Any:
    if isinstance(v, str):      # came off the wire as base64
        return base64.b64decode(v, validate=True)
    return v                    # already raw bytes from Python

ProtoBytes = Annotated[
    bytes,
    BeforeValidator(_decode_bytes),
    PlainSerializer(
        lambda b: base64.b64encode(b).decode("ascii"),
        return_type=str,
        when_used="json",
    ),
    WithJsonSchema({"type": "string", "format": "byte"}),
]


# --- leaves ------------------------------------------------------------------

class HashedPassword(BaseModel):
    # proto: bytes salt = 1; bytes scrypt = 2;
    salt: ProtoBytes
    scrypt: ProtoBytes


class AuthToken(BaseModel):
    # proto: bytes hmac_of_rest = 1; string owner = 7;
    #        double minted_unixtime = 5; double expires_unixtime = 6;
    hmac_of_rest: ProtoBytes
    owner: str
    minted_unixtime: float
    expires_unixtime: float


class Relationship(BaseModel):
    # proto: bool trusts_you = 1; bool trusted_by_you = 2;
    trusts_you: bool
    trusted_by_you: bool


class Invitation(BaseModel):
    # proto: message Invitation {}  -- deliberately empty
    pass


# --- login_type oneof --------------------------------------------------------

class LoginTypePassword(BaseModel):
    login_type_kind: Literal["login_password"] = "login_password"
    login_password: HashedPassword


LoginType = Annotated[
    Union[LoginTypePassword],
    Field(discriminator="login_type_kind"),
]


class GenericUserInfo(BaseModel):
    # NOTE: these are deliberately *required* (no defaults) even though a default
    # of {} would be more natural in Python. A field with a default is omitted
    # from OpenAPI's `required`, and the Elm generator then wraps it in a Maybe:
    #     invitations : Maybe (Dict.Dict String Invitation)   -- default present
    #     invitations : Dict.Dict String Invitation           -- required
    # Same for login_type: required-but-nullable gives `Nullable LoginTypePassword`,
    # whereas defaulted-and-nullable gives a `Maybe (Nullable ...)` double-option.
    # Requiring them costs the server an explicit `invitations={}` and buys the
    # Elm side a pile of removed Maybe-unwrapping.
    email_address: str
    invitations: Dict[str, Invitation]
    relationships: Dict[str, Relationship]
    login_type: LoginType | None


class AuthSuccess(BaseModel):
    token: AuthToken
    user_info: GenericUserInfo


# --- the endpoint ------------------------------------------------------------

class LogInUsernameRequest(BaseModel):
    username: str
    password: str


class LogInUsernameError(BaseModel):
    # proto: message Error { string catchall = 1; }
    catchall: str


class LogInUsernameResultOk(BaseModel):
    log_in_username_result: Literal["ok"] = "ok"
    ok: AuthSuccess


class LogInUsernameResultError(BaseModel):
    log_in_username_result: Literal["error"] = "error"
    error: LogInUsernameError


LogInUsernameResponse = Annotated[
    Union[LogInUsernameResultOk, LogInUsernameResultError],
    Field(discriminator="log_in_username_result"),
]
