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

  def test_everyone_trusts_self(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    assert conn.trusts('alice', 'alice')


class TestInvitations:
  def test_invitation_is_open_between_create_and_accept(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    conn.register_username('bob', 'password', password_id='bobpwid')

    assert not conn.is_invitation_open(nonce='mynonce')
    conn.create_invitation(nonce='mynonce', inviter='alice', now=123, notes='')
    assert conn.is_invitation_open(nonce='mynonce')
    conn.accept_invitation(nonce='mynonce', accepter='bob', now=124)
    assert not conn.is_invitation_open(nonce='mynonce')

  def test_no_accepting_own_invitation(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')

    conn.create_invitation(nonce='mynonce', inviter='alice', now=123, notes='')
    with pytest.raises(Exception):  # TODO: specify
      conn.accept_invitation(nonce='mynonce', accepter='alice', now=124)

  def test_no_accepting_closed_invitation(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    conn.register_username('bob', 'password', password_id='bobpwid')

    with pytest.raises(Exception):  # TODO: specify
      conn.accept_invitation(nonce='mynonce', accepter='bob', now=124)

    conn.create_invitation(nonce='mynonce', inviter='alice', now=123, notes='')
    conn.accept_invitation(nonce='mynonce', accepter='bob', now=124)

    with pytest.raises(Exception):  # TODO: specify
      conn.accept_invitation(nonce='mynonce', accepter='bob', now=124)

class TestPredictions:
  def test_view_contains_all_creation_fields(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')

    conn.create_prediction(now=123, prediction_id=456, creator='alice', request=mvp_pb2.CreatePredictionRequest(
      prediction='a thing will happen',
      certainty=mvp_pb2.CertaintyRange(low=0.25, high=0.75),
      maximum_stake_cents=100,
      open_seconds=86400,
      special_rules='my rules',
      resolves_at_unixtime=100000,
    ))
    assert conn.view_prediction(viewer='alice', prediction_id=456) == mvp_pb2.UserPredictionView(
      prediction='a thing will happen',
      certainty=mvp_pb2.CertaintyRange(low=0.25, high=0.75),
      maximum_stake_cents=100,
      remaining_stake_cents_vs_believers=100,
      remaining_stake_cents_vs_skeptics=100,
      created_unixtime=123,
      closes_unixtime=86523,
      special_rules='my rules',
      creator=mvp_pb2.UserUserView(username='alice', is_trusted=True, trusts_you=True),
      resolves_at_unixtime=100000,
    )

  def test_stake_errors_on_nonexistent_prediction(self, conn: SqlConn):
    conn.register_username('alice', 'password', password_id='alicepwid')
    with pytest.raises(sqlalchemy.exc.IntegrityError):
      conn.stake(prediction_id=123, bettor='alice', bettor_is_a_skeptic=True, bettor_stake_cents=1, creator_stake_cents=1, now=123)
