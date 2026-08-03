"""Emit the API's OpenAPI schema -- the input to the elm-open-api generator that
produces elm/generated/Api/{Types,Json,Api}.elm (and OpenApi/Common.elm).

This replaces the old protoc-gen-elm step: instead of generating Elm from
mvp.proto, we generate it from the OpenAPI schema that FastAPI derives from the
api_types Pydantic models -- the single source of truth for the wire format.

Regenerate the committed Elm bindings with (see dodo.py task `genapi`):

    python -m server.openapi_spec > elm/generated/openapi.json
    cd elm && npx --yes elm-open-api generated/openapi.json \\
        --output-dir generated --module-name Api
"""

import json

from fastapi import FastAPI

from . import api_types as T


def build_app() -> FastAPI:
    """A throwaway app whose only purpose is to have FastAPI derive the OpenAPI
    schema from the api_types models. The handlers never run."""
    app = FastAPI(title="biatob", version="0.1.0")
    for name, req_model, resp_model in T.ENDPOINTS:
        def handler(body: req_model) -> resp_model:  # type: ignore
            raise NotImplementedError
        app.post(f"/api/{name}", response_model=resp_model, operation_id=name[0].lower() + name[1:])(handler)

    # SavedCreatedPredictionFormState is client-only (it lives in localStorage,
    # not on any endpoint), so expose it on a throwaway route -- otherwise the
    # generator has no reason to emit its encoder/decoder.
    def form_state() -> T.SavedCreatedPredictionFormState:  # type: ignore
        raise NotImplementedError
    app.post("/_formstate", response_model=T.SavedCreatedPredictionFormState, operation_id="_formstate")(form_state)

    return app


def build_openapi() -> dict:
    return build_app().openapi()


if __name__ == "__main__":
    print(json.dumps(build_openapi(), indent=2, sort_keys=True))
