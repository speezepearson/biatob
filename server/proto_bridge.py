"""Generic conversion between protobuf messages and the Pydantic api_types.

Phase 3b keeps the servicer on protobuf while the wire is JSON, so the FastAPI
layer converts at the edge: JSON request -> Pydantic -> proto (into the
servicer), and proto (out) -> Pydantic -> JSON response. Both directions are one
call each -- protobuf's json_format does the structural work, and the field
names/enum values line up because api_types was defined to match.

This whole module goes away in the final phase, when the servicer itself
returns Pydantic and there's no protobuf left to bridge.
"""

from typing import Type, TypeVar

from google.protobuf import json_format
from google.protobuf.message import Message
from pydantic import BaseModel

_Model = TypeVar("_Model", bound=BaseModel)


def pydantic_to_proto(model: BaseModel, proto_cls: Type[Message]) -> Message:
    # model_dump(mode='json') gives camelCase keys (serialize_by_alias) and enum
    # string values -- exactly proto3's canonical JSON, which ParseDict reads.
    return json_format.ParseDict(model.model_dump(mode="json"), proto_cls())


def proto_to_pydantic(proto: Message, model_cls: Type[_Model]) -> _Model:
    # including_default_value_fields: proto3 omits zero-valued fields from JSON,
    # but the api_types require them (bool=False, ""=notes, zero-enums), so ask
    # for them explicitly. preserving_proto_field_name: snake_case, which
    # model_validate accepts via populate_by_name.
    return model_cls.model_validate(
        # including_default_value_fields is valid at runtime (protobuf 3.14) but
        # missing from the type stubs.
        json_format.MessageToDict(proto, preserving_proto_field_name=True, including_default_value_fields=True)  # type: ignore[call-arg]
    )
