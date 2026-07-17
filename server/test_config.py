import json

import pytest
from pydantic import ValidationError

from .config import CredentialsConfig, MysqlDatabase, SqliteDatabase
from .sql_schema import get_db_url
from .scripts.convert_credentials import convert

SQLITE_JSON = json.dumps({
    'smtp': {'hostname': 'h', 'port': 587, 'username': 'u', 'password': 'p', 'from_addr': 'f@x.com'},
    'token_signing_secret': 'sekrit',
    'database': {'kind': 'sqlite', 'path': '/tmp/x.db'},
})

MYSQL_JSON = json.dumps({
    'smtp': {'hostname': 'h', 'port': 25, 'username': 'u', 'password': 'p', 'from_addr': 'f@x.com'},
    'token_signing_secret': 'sekrit',
    'database': {'kind': 'mysql', 'hostname': 'db', 'username': 'mu', 'password': 'mp', 'dbname': 'biatob'},
})


def test_parses_sqlite():
    c = CredentialsConfig.from_json(SQLITE_JSON)
    assert isinstance(c.database, SqliteDatabase)
    assert c.database.path == '/tmp/x.db'
    assert c.smtp.port == 587
    assert c.token_signing_secret_bytes == b'sekrit'


def test_parses_mysql():
    c = CredentialsConfig.from_json(MYSQL_JSON)
    assert isinstance(c.database, MysqlDatabase)
    assert c.database.dbname == 'biatob'


def test_db_url_matches_legacy_format():
    # These must exactly match what the old protobuf-based get_db_url produced,
    # or existing databases become unreachable.
    assert get_db_url(CredentialsConfig.from_json(SQLITE_JSON).database) == 'sqlite+pysqlite:////tmp/x.db'
    assert get_db_url(CredentialsConfig.from_json(MYSQL_JSON).database) == 'mysql+pymysql://mu:mp@db/biatob'


def test_rejects_unknown_database_kind():
    bad = json.dumps({
        'smtp': {'hostname': 'h', 'port': 25, 'username': 'u', 'password': 'p', 'from_addr': 'f@x.com'},
        'token_signing_secret': 's',
        'database': {'kind': 'postgres', 'path': '/tmp/x'},
    })
    with pytest.raises(ValidationError):
        CredentialsConfig.from_json(bad)


def test_rejects_missing_smtp():
    with pytest.raises(ValidationError):
        CredentialsConfig.from_json(json.dumps({
            'token_signing_secret': 's',
            'database': {'kind': 'sqlite', 'path': '/tmp/x'},
        }))


# --- the one-shot converter from the old text-format ---

OLD_SQLITE = '''
smtp {
  hostname: "smtp.example.com"
  port: 587
  username: "mailer@example.com"
  password: "s3cr3t p@ss"
  from_addr: "biatob@example.com"
}
token_signing_secret: "my-signing-key-123"
database_info { sqlite: "/home/protected/server.WorldState.db" }
'''

OLD_MYSQL = '''
smtp {
  hostname: "smtp.example.com"
  port: 25
  username: "u"
  password: "p"
  from_addr: "f@example.com"
}
token_signing_secret: "key"
database_info {
  mysql {
    hostname: "db.internal"
    username: "biatob_user"
    password: "dbpass"
    dbname: "biatob"
  }
}
'''


def test_converter_sqlite_roundtrips_and_validates():
    c = CredentialsConfig.model_validate(convert(OLD_SQLITE))
    assert isinstance(c.database, SqliteDatabase)
    assert c.database.path == '/home/protected/server.WorldState.db'
    assert c.smtp.password == 's3cr3t p@ss'  # spaces and punctuation survive
    assert c.token_signing_secret == 'my-signing-key-123'


def test_converter_mysql_roundtrips_and_validates():
    c = CredentialsConfig.model_validate(convert(OLD_MYSQL))
    assert isinstance(c.database, MysqlDatabase)
    assert c.database.hostname == 'db.internal'
    assert c.database.dbname == 'biatob'
