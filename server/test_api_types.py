"""Tests for the API's Pydantic models (server/api_types.py).

Covers the two things a migration can silently get wrong: the JSON *shape*
(camelCase keys, enum string values, that a recursive type round-trips) and the
*contract* (every endpoint present in the generated OpenAPI schema, with the
schema well-formed enough to hand to the Elm generator).
"""

import json

from fastapi import FastAPI

from . import api_types as T


# --- JSON shape --------------------------------------------------------------

def test_json_keys_are_camel_case():
    rel = T.Relationship(trusts_you=True, trusted_by_you=False)
    assert json.loads(rel.model_dump_json()) == {"trustsYou": True, "trustedByYou": False}


def test_enum_values_are_the_protobuf_names():
    # These strings are stored in the DB's CHECK-constrained columns; they must
    # not drift, or existing rows stop validating.
    assert T.Resolution.YES.value == "RESOLUTION_YES"
    assert T.TradeState.ACTIVE.value == "TRADE_STATE_ACTIVE"
    dumped = json.loads(T.ResolveRequest(prediction_id="p", resolution=T.Resolution.NO, notes="").model_dump_json())
    assert dumped["resolution"] == "RESOLUTION_NO"


def test_recursive_resolution_event_round_trips():
    ev = T.ResolutionEvent(
        unixtime=2.0, resolution=T.Resolution.YES, notes="corrected",
        prior_revision=T.ResolutionEvent(unixtime=1.0, resolution=T.Resolution.NO, notes="oops"),
    )
    back = T.ResolutionEvent.model_validate_json(ev.model_dump_json())
    assert back == ev
    assert back.prior_revision is not None
    assert back.prior_revision.prior_revision is None


def test_maps_and_nested_models_round_trip():
    view = T.UserPredictionView(
        prediction="a thing", certainty=T.CertaintyRange(low=0.4, high=0.6),
        maximum_stake_cents=100, remaining_stake_cents_vs_believers=100,
        remaining_stake_cents_vs_skeptics=100, created_unixtime=1.0, closes_unixtime=2.0,
        special_rules="", creator="alice",
        resolution=T.ResolutionEvent(unixtime=0.0, resolution=T.Resolution.NONE_YET, notes=""),
        your_trades=[], resolves_at_unixtime=3.0,
        your_following_status=T.PredictionFollowingStatus.NOT_FOLLOWING,
    )
    preds = T.PredictionsById(predictions={"pred1": view})
    assert T.PredictionsById.model_validate_json(preds.model_dump_json()) == preds


def test_populate_by_name_accepts_snake_case_from_python():
    # The server constructs these with snake_case kwargs; the alias only governs JSON.
    assert T.CertaintyRange(low=0.1, high=0.9).high == 0.9


# --- the OpenAPI contract ----------------------------------------------------

def _build_app() -> FastAPI:
    app = FastAPI(title="biatob", version="0.1.0")
    for name, req_model, resp_model in T.ENDPOINTS:
        def handler(body: req_model) -> resp_model:  # type: ignore
            raise NotImplementedError
        app.post(f"/api/{name}", response_model=resp_model, operation_id=name[0].lower() + name[1:])(handler)
    return app


def test_every_endpoint_is_in_the_openapi_schema():
    schema = _build_app().openapi()
    for name, _, _ in T.ENDPOINTS:
        assert f"/api/{name}" in schema["paths"], name
        assert "post" in schema["paths"][f"/api/{name}"]


def test_openapi_schema_carries_the_recursive_and_enum_types():
    schemas = _build_app().openapi()["components"]["schemas"]
    # recursion: ResolutionEvent references itself
    assert "ResolutionEvent" in schemas
    assert "ResolutionEvent" in json.dumps(schemas["ResolutionEvent"])
    # enums are emitted with their string values
    assert set(schemas["Resolution"]["enum"]) == {
        "RESOLUTION_NONE_YET", "RESOLUTION_YES", "RESOLUTION_NO", "RESOLUTION_INVALID"
    }
