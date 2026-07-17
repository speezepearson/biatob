#! /usr/bin/env python3
"""One-shot migration: old protobuf-text-format credentials file -> JSON.

The server now reads its credentials as JSON (server/config.py). Run this once
against your existing `*.CredentialsConfig.textproto` to produce the JSON the
new `--credentials-path` expects:

    python -m server.scripts.convert_credentials old.textproto > credentials.json

Then validate the result actually parses:

    python -c "import sys, json; from server.config import CredentialsConfig; \
               CredentialsConfig.parse_file(open(sys.argv[1]).read())" credentials.json

The old format is a small fixed grammar (an `smtp {...}` block, a
`token_signing_secret` string, and a `database_info {...}` block), so this
parses it directly rather than depending on the now-deleted proto messages.
Assumes the string values contain no protobuf escape sequences, which is true
of every field here in practice (hostnames, usernames, an ASCII secret).
"""

import json
import re
import sys
from typing import Any, Dict


def _field(text: str, key: str) -> str:
    m = re.search(rf'\b{re.escape(key)}\s*:\s*"((?:[^"\\]|\\.)*)"', text)
    if m is None:
        raise ValueError(f'could not find field {key!r}')
    return m.group(1)


def _int_field(text: str, key: str) -> int:
    m = re.search(rf'\b{re.escape(key)}\s*:\s*(\d+)', text)
    if m is None:
        raise ValueError(f'could not find int field {key!r}')
    return int(m.group(1))


def _block(text: str, name: str) -> str:
    """Return the body between the braces of `name { ... }`."""
    m = re.search(rf'\b{re.escape(name)}\s*\{{', text)
    if m is None:
        raise ValueError(f'could not find block {name!r}')
    i = m.end()
    depth = 1
    while i < len(text) and depth > 0:
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
    return text[m.end():i - 1]


def convert(text: str) -> Dict[str, Any]:
    smtp = _block(text, 'smtp')
    db = _block(text, 'database_info')

    if re.search(r'\bmysql\s*\{', db):
        mysql = _block(db, 'mysql')
        database: Dict[str, Any] = {
            'kind': 'mysql',
            'hostname': _field(mysql, 'hostname'),
            'username': _field(mysql, 'username'),
            'password': _field(mysql, 'password'),
            'dbname': _field(mysql, 'dbname'),
        }
    else:
        database = {'kind': 'sqlite', 'path': _field(db, 'sqlite')}

    return {
        'smtp': {
            'hostname': _field(smtp, 'hostname'),
            'port': _int_field(smtp, 'port'),
            'username': _field(smtp, 'username'),
            'password': _field(smtp, 'password'),
            'from_addr': _field(smtp, 'from_addr'),
        },
        'token_signing_secret': _field(text, 'token_signing_secret'),
        'database': database,
    }


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    text = open(sys.argv[1]).read()
    print(json.dumps(convert(text), indent=2))


if __name__ == '__main__':
    main()
