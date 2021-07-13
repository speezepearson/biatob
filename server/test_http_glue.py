from unittest.mock import Mock

from .core import TokenMint
from .http_glue import HttpTokenGlue
from .test_utils import *

SECRET_KEY = b'secret for testing'

class TestParseCookie:

  def test_returns_token_owner_if_valid_token(self, clock: MockClock):
    mint = TokenMint(SECRET_KEY, clock=clock.now)
    glue = HttpTokenGlue(mint)

    resp = Mock()
    token = mint.mint_token(u('owner'), ttl_seconds=100)
    glue.set_cookie(token, resp)
    resp.set_cookie.assert_called_once()
    (cookie_name, encoded) = resp.set_cookie.call_args[0]

    assert glue.parse_cookie(Mock(cookies={cookie_name: encoded})) == token

  def test_returns_token_owner_if_valid_token_but_different_mint_instance(self, clock: MockClock):
    mint = TokenMint(SECRET_KEY, clock=clock.now)
    glue = HttpTokenGlue(mint)

    resp = Mock()
    token = mint.mint_token(u('owner'), ttl_seconds=100)
    glue.set_cookie(token, resp)
    resp.set_cookie.assert_called_once()
    (cookie_name, encoded) = resp.set_cookie.call_args[0]

    new_glue = HttpTokenGlue(TokenMint(SECRET_KEY, clock=clock.now))
    req = Mock(cookies={cookie_name: encoded})
    assert new_glue.parse_cookie(req) == token

  def test_returns_none_if_bad_signature(self, clock: MockClock):
    mint = TokenMint(SECRET_KEY, clock=clock.now)
    glue = HttpTokenGlue(mint)

    resp = Mock()
    token = mint.mint_token(u('owner'), ttl_seconds=100)
    glue.set_cookie(token, resp)
    resp.set_cookie.assert_called_once()
    (cookie_name, encoded) = resp.set_cookie.call_args[0]

    bad_key_glue = HttpTokenGlue(TokenMint(b'not ' + SECRET_KEY))
    assert bad_key_glue.parse_cookie(Mock(cookies={cookie_name: encoded})) is None

  def test_returns_none_if_expired(self, clock: MockClock):
    mint = TokenMint(SECRET_KEY, clock=clock.now)
    glue = HttpTokenGlue(mint)

    resp = Mock()
    token = mint.mint_token(u('owner'), ttl_seconds=100)
    glue.set_cookie(token, resp)
    resp.set_cookie.assert_called_once()
    (cookie_name, encoded) = resp.set_cookie.call_args[0]

    clock.tick(99)
    assert glue.parse_cookie(Mock(cookies={cookie_name: encoded})) == token
    clock.tick(2)
    assert glue.parse_cookie(Mock(cookies={cookie_name: encoded})) is None

  def test_returns_none_if_issued_in_future(self, clock: MockClock):
    clock = MockClock()
    mint = TokenMint(SECRET_KEY, clock=clock.now)
    glue = HttpTokenGlue(mint)

    resp = Mock()
    token = mint.mint_token(u('owner'), ttl_seconds=100)
    glue.set_cookie(token, resp)
    resp.set_cookie.assert_called_once()
    (cookie_name, encoded) = resp.set_cookie.call_args[0]

    past_clock = MockClock()
    past_clock.tick(-1)
    past_glue = HttpTokenGlue(TokenMint(SECRET_KEY, clock=past_clock.now))
    assert past_glue.parse_cookie(Mock(cookies={cookie_name: encoded})) is None
