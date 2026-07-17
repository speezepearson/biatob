"""Pydantic models for the HTTP API: the request/response bodies and the domain
types they carry. These are the successors to the protobuf messages in
mvp.proto -- the JSON wire format the Elm client will speak once phase 3 cuts
over.

Design notes (from the spike, biatob PR #34):
  - `alias_generator=to_camel` so the JSON is camelCase and matches the field
    names the Elm app already uses -- minimizing churn at cutover.
  - map/list/scalar fields are required (no defaults), so the generated Elm has
    plain `Dict`/`List`/value types rather than `Maybe`-wrapped ones.
  - enum values are the protobuf enum *names*, so they match the strings already
    stored in the database's CHECK-constrained columns (no data migration).
"""

import enum
from typing import Dict, List, Optional

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class _Base(BaseModel):
    # alias_generator -> JSON is camelCase (matches the Elm field names).
    # populate_by_name -> the server can still construct with snake_case kwargs.
    # serialize_by_alias -> model_dump_json() is camelCase without by_alias=True,
    #   so direct serialization (the SSR bootstrap, localStorage) matches the wire.
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, serialize_by_alias=True)


# --- enums -------------------------------------------------------------------

class Resolution(str, enum.Enum):
    NONE_YET = "RESOLUTION_NONE_YET"
    YES = "RESOLUTION_YES"
    NO = "RESOLUTION_NO"
    INVALID = "RESOLUTION_INVALID"


class TradeState(str, enum.Enum):
    ACTIVE = "TRADE_STATE_ACTIVE"
    QUEUED = "TRADE_STATE_QUEUED"
    DISAVOWED = "TRADE_STATE_DISAVOWED"
    DEQUEUE_FAILED = "TRADE_STATE_DEQUEUE_FAILED"


class PredictionViewPrivacy(str, enum.Enum):
    ANYBODY = "PREDICTION_VIEW_PRIVACY_ANYBODY"
    ANYBODY_WITH_THE_LINK = "PREDICTION_VIEW_PRIVACY_ANYBODY_WITH_THE_LINK"


class PredictionFollowingStatus(str, enum.Enum):
    NOT_FOLLOWING = "PREDICTION_FOLLOWING_NOT_FOLLOWING"
    FOLLOWING = "PREDICTION_FOLLOWING_FOLLOWING"
    MANDATORY_BECAUSE_STAKED = "PREDICTION_FOLLOWING_MANDATORY_BECAUSE_STAKED"


# --- domain types ------------------------------------------------------------

class CertaintyRange(_Base):
    low: float
    high: float


class Relationship(_Base):
    trusts_you: bool
    trusted_by_you: bool


class Invitation(_Base):
    """Deliberately empty -- presence in the map is the whole signal."""


class GenericUserInfo(_Base):
    email_address: str
    invitations: Dict[str, Invitation]
    relationships: Dict[str, Relationship]


class ResolutionEvent(_Base):
    unixtime: float
    resolution: Resolution
    notes: str
    # Recursive: the previous revision of this resolution, if any. Pydantic
    # handles the self-reference; the field is optional to end the chain.
    prior_revision: Optional["ResolutionEvent"] = None


class Trade(_Base):
    bettor: str
    bettor_is_a_skeptic: bool
    bettor_stake_cents: int
    creator_stake_cents: int
    transacted_unixtime: float
    updated_unixtime: float
    notes: str
    state: TradeState


class UserPredictionView(_Base):
    prediction: str
    certainty: CertaintyRange
    maximum_stake_cents: int
    remaining_stake_cents_vs_believers: int
    remaining_stake_cents_vs_skeptics: int
    created_unixtime: float
    closes_unixtime: float
    special_rules: str
    creator: str
    resolution: ResolutionEvent
    your_trades: List[Trade]
    resolves_at_unixtime: float
    your_following_status: PredictionFollowingStatus


class PredictionsById(_Base):
    predictions: Dict[str, UserPredictionView]


class AuthSuccess(_Base):
    # The protobuf AuthSuccess carried a whole AuthToken; all the client ever
    # needs is who it's now logged in as. The signed session token lives in the
    # cookie (server/tokens.py), not here.
    owner: str
    user_info: GenericUserInfo


class WhoamiResponse(_Base):
    username: str


class CreatePredictionResponse(_Base):
    new_prediction_id: str


class CheckInvitationResponse(_Base):
    inviter: str
    recipient: str


class Empty(_Base):
    """The body of an endpoint whose only output is 'it worked'."""


class ErrorResponse(_Base):
    """The body of any non-2xx response. See docs/error-handling.md."""
    catchall: str


# --- request bodies ----------------------------------------------------------

class WhoamiRequest(_Base):
    pass


class SignOutRequest(_Base):
    pass


class SendVerificationEmailRequest(_Base):
    email_address: str


class RegisterUsernameRequest(_Base):
    username: str
    password: str
    proof_of_email_token: str


class LogInUsernameRequest(_Base):
    username: str
    password: str


class CreatePredictionRequest(_Base):
    prediction: str
    view_privacy: PredictionViewPrivacy
    certainty: CertaintyRange
    maximum_stake_cents: int
    open_seconds: int
    special_rules: str
    resolves_at_unixtime: float


class GetPredictionRequest(_Base):
    prediction_id: str


class ListMyStakesRequest(_Base):
    pass


class ListPredictionsRequest(_Base):
    creator: str


class FollowRequest(_Base):
    prediction_id: str
    follow: bool


class StakeRequest(_Base):
    prediction_id: str
    bettor_is_a_skeptic: bool
    bettor_stake_cents: int


class ResolveRequest(_Base):
    prediction_id: str
    resolution: Resolution
    notes: str


class SetTrustedRequest(_Base):
    who: str
    trusted: bool


class GetUserRequest(_Base):
    who: str


class ChangePasswordRequest(_Base):
    old_password: str
    new_password: str


class GetSettingsRequest(_Base):
    include_relationships_with_users: List[str]


class SendInvitationRequest(_Base):
    recipient: str


class CheckInvitationRequest(_Base):
    nonce: str


class AcceptInvitationRequest(_Base):
    nonce: str


# --- the endpoint contract ---------------------------------------------------
#
# (operation name, request body, response body). The canonical list of API
# endpoints, mirroring api_server.py's routes. The FastAPI app (phase 3b) builds
# its routes from this; test_api_types builds a throwaway app from it to check
# the OpenAPI schema. Every response body is the success payload -- failures are
# an HTTP status + ErrorResponse (docs/error-handling.md).

ENDPOINTS = [
    ("Whoami", WhoamiRequest, WhoamiResponse),
    ("SignOut", SignOutRequest, Empty),
    ("SendVerificationEmail", SendVerificationEmailRequest, Empty),
    ("RegisterUsername", RegisterUsernameRequest, AuthSuccess),
    ("LogInUsername", LogInUsernameRequest, AuthSuccess),
    ("CreatePrediction", CreatePredictionRequest, CreatePredictionResponse),
    ("GetPrediction", GetPredictionRequest, UserPredictionView),
    ("ListMyStakes", ListMyStakesRequest, PredictionsById),
    ("ListPredictions", ListPredictionsRequest, PredictionsById),
    ("Follow", FollowRequest, UserPredictionView),
    ("Stake", StakeRequest, UserPredictionView),
    ("Resolve", ResolveRequest, UserPredictionView),
    ("SetTrusted", SetTrustedRequest, GenericUserInfo),
    ("GetUser", GetUserRequest, Relationship),
    ("ChangePassword", ChangePasswordRequest, Empty),
    ("GetSettings", GetSettingsRequest, GenericUserInfo),
    ("SendInvitation", SendInvitationRequest, GenericUserInfo),
    ("CheckInvitation", CheckInvitationRequest, CheckInvitationResponse),
    ("AcceptInvitation", AcceptInvitationRequest, GenericUserInfo),
]


# --- client-side only (localStorage), not an API body ------------------------

class SavedCreatedPredictionFormState(_Base):
    prediction_field: str
    resolves_at_field: str
    stake_field: str
    low_p_field: str
    high_p_field: str
    open_for_unit_field: str
    open_for_seconds_field: str
    view_privacy_field: str
    special_rules_field: str
