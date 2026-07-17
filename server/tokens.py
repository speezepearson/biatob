"""Signed tokens the server issues and later verifies: the auth cookie, and
(soon) the email-verification proof.

A token is a Pydantic model serialized to JSON and stamped with an HMAC, so the
server can hand it out and trust it when it comes back. `seal`/`unseal` are the
generic mechanism; `AuthToken` is the first model to use it.

The sealed form is tamper-evident, NOT secret: the payload is plain readable
JSON. Never put anything in a token that the bearer shouldn't see.
"""

import base64
import hmac
from typing import Optional, Type, TypeVar

from pydantic import BaseModel


class AuthToken(BaseModel):
    owner: str
    minted_unixtime: float
    expires_unixtime: float


_Model = TypeVar("_Model", bound=BaseModel)


def _mac(secret_key: bytes, payload: bytes) -> bytes:
    return hmac.digest(secret_key, payload, "sha256")


def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode("ascii")


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s)


def seal(secret_key: bytes, model: BaseModel) -> str:
    """`<payload>.<hmac>`, both url-safe base64. Verify with `unseal`."""
    payload = model.model_dump_json().encode("utf-8")
    return _b64(payload) + "." + _b64(_mac(secret_key, payload))


def unseal(secret_key: bytes, sealed: str, cls: Type[_Model]) -> Optional[_Model]:
    """Inverse of `seal`. None if the shape is wrong, the HMAC doesn't verify,
    or the payload isn't valid for `cls`."""
    try:
        payload_b64, mac_b64 = sealed.split(".", 1)
        payload = _unb64(payload_b64)
        mac = _unb64(mac_b64)
    except Exception:
        return None
    if not hmac.compare_digest(mac, _mac(secret_key, payload)):
        return None
    try:
        return cls.model_validate_json(payload)
    except Exception:
        return None
