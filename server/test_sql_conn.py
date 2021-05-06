import pytest

from .core import UsernameAlreadyRegisteredError
from .sql_servicer import SqlConn
from .sql_schema import create_sqlite_engine

@pytest.fixture
def conn():
  return SqlConn(conn=create_sqlite_engine(':memory:'))


class TestRegisterUsername:
  def test_user_exists_after(self, conn: SqlConn):
    assert not conn.user_exists('alice')
    conn.register_username('alice', 'password', password_id='alicepwid')
    assert conn.user_exists('alice')

  def test_no_double_registration(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    with pytest.raises(UsernameAlreadyRegisteredError):
      conn.register_username('alice', 'password', password_id='alicepwid')


class TestTrust:
  def test_initially_no_trust_until_set_trust(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    conn.register_username('bob', 'password', password_id='bobpwid')
    assert not conn.trusts('alice', 'bob')

  def test_trust_follows_last_set_trust(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    conn.register_username('bob', 'password', password_id='bobpwid')
    conn.set_trusted('alice', 'bob', True)
    assert conn.trusts('alice', 'bob')
    conn.set_trusted('alice', 'bob', True)
    assert conn.trusts('alice', 'bob')
    conn.set_trusted('alice', 'bob', False)
    assert not conn.trusts('alice', 'bob')
    conn.set_trusted('alice', 'bob', False)
    assert not conn.trusts('alice', 'bob')
    conn.set_trusted('alice', 'bob', True)
    assert conn.trusts('alice', 'bob')

  def test_trust_is_only_one_way(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    conn.register_username('bob', 'password', password_id='bobpwid')
    conn.set_trusted('alice', 'bob', True)
    assert conn.trusts('alice', 'bob')
    assert not conn.trusts('bob', 'alice')

  def test_false_if_either_user_nonexistent(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    assert not conn.trusts('alice', 'bob')
    assert not conn.trusts('bob', 'alice')
    assert not conn.trusts('bob', 'charlie')
