"""Server configuration, loaded from a JSON credentials file at startup.

Replaces the old `CredentialsConfig` protobuf message (parsed from a text-format
file via `google.protobuf.text_format`). See scripts/convert_credentials.py to
migrate an existing text-format credentials file, and README for the schema.
"""

from typing import Annotated, Literal, Union

from pydantic import BaseModel, Field


class SmtpCredentials(BaseModel):
    hostname: str
    port: int
    username: str
    password: str
    from_addr: str


class SqliteDatabase(BaseModel):
    kind: Literal["sqlite"] = "sqlite"
    path: str


class MysqlDatabase(BaseModel):
    kind: Literal["mysql"] = "mysql"
    hostname: str
    username: str
    password: str
    dbname: str


# Discriminated on `kind`, so exactly one shape is valid and the error messages
# point at the right fields -- the Pydantic analogue of the old
# `oneof database_kind`.
DatabaseInfo = Annotated[
    Union[SqliteDatabase, MysqlDatabase],
    Field(discriminator="kind"),
]


class CredentialsConfig(BaseModel):
    smtp: SmtpCredentials
    # A str, not bytes: JSON has no byte type, and a signing secret is
    # human-set. Encoded to bytes (utf-8) where a key is needed.
    token_signing_secret: str
    database: DatabaseInfo

    @property
    def token_signing_secret_bytes(self) -> bytes:
        return self.token_signing_secret.encode("utf-8")

    @staticmethod
    def from_json(text: str) -> "CredentialsConfig":
        return CredentialsConfig.model_validate_json(text)
