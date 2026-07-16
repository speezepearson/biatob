"""Minimal FastAPI app exposing the LogInUsername slice.

Serves two purposes:
  - `python gen_openapi.py` emits openapi.json for the Elm generator.
  - running it for real produces genuine on-the-wire JSON, which the generated
    Elm decoders are then tested against (see elm-test/tests/RoundTripTest.elm).

The handler returns canned data; the point is the serialized shape, not the
business logic.
"""

from fastapi import FastAPI

from models import (
    AuthSuccess,
    AuthToken,
    GenericUserInfo,
    HashedPassword,
    Invitation,
    LogInUsernameError,
    LogInUsernameRequest,
    LogInUsernameResponse,
    LogInUsernameResultError,
    LogInUsernameResultOk,
    LoginTypePassword,
    Relationship,
)

app = FastAPI(title="biatob (LogInUsername spike)", version="0.0.1")


# operation_id matters: without it FastAPI derives one from the function name +
# path + method, and the Elm generator turns that into the function name
# `logInUsernameApiLogInUsernamePost`. Setting it explicitly gets `logInUsername`.
@app.post("/api/LogInUsername", response_model=LogInUsernameResponse, operation_id="logInUsername")
def log_in_username(request: LogInUsernameRequest) -> LogInUsernameResponse:
    if request.password != "hunter2":
        return LogInUsernameResultError(error=LogInUsernameError(catchall="bad password"))

    return LogInUsernameResultOk(
        ok=AuthSuccess(
            token=AuthToken(
                # Deliberately non-UTF8 bytes: this is what breaks plain `bytes`.
                hmac_of_rest=b"\x00\x01\xfe\xff\x80",
                owner=request.username,
                minted_unixtime=1600000000.0,
                expires_unixtime=1600086400.0,
            ),
            user_info=GenericUserInfo(
                email_address="spike@example.com",
                invitations={"some-nonce": Invitation()},
                relationships={"alice": Relationship(trusts_you=True, trusted_by_you=False)},
                login_type=LoginTypePassword(
                    login_password=HashedPassword(salt=b"\xde\xad\xbe\xef", scrypt=b"\x01\x02\x03"),
                ),
            ),
        ),
    )
