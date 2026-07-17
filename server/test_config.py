import json

import pytest
from pydantic import ValidationError

from .config import CredentialsConfig, MysqlDatabase, SqliteDatabase
from .sql_schema import get_db_url

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
    # These exact strings are the connection URLs existing databases expect;
    # changing them makes those databases unreachable.
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
