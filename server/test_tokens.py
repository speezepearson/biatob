import pytest

from . import tokens
from .core import TokenMint
from .test_utils import MockClock

KEY = b'secret for testing'


def test_seal_unseal_roundtrips():
    t = tokens.AuthToken(owner='alice', minted_unixtime=1000, expires_unixtime=2000)
    sealed = tokens.seal(KEY, t)
    assert tokens.unseal(KEY, sealed, tokens.AuthToken) == t


def test_unseal_rejects_wrong_key():
    sealed = tokens.seal(KEY, tokens.AuthToken(owner='alice', minted_unixtime=1000, expires_unixtime=2000))
    assert tokens.unseal(b'other key', sealed, tokens.AuthToken) is None


def test_unseal_rejects_tampered_payload():
    t = tokens.AuthToken(owner='alice', minted_unixtime=1000, expires_unixtime=2000)
    payload_b64, mac_b64 = tokens.seal(KEY, t).split('.', 1)
    # forge a different owner but keep the original MAC
    forged_payload = tokens._b64(
        tokens.AuthToken(owner='mallory', minted_unixtime=1000, expires_unixtime=2000)
        .model_dump_json().encode()
    )
    assert tokens.unseal(KEY, f'{forged_payload}.{mac_b64}', tokens.AuthToken) is None


@pytest.mark.parametrize('garbage', ['', 'nodot', 'not.base64!!', '.', 'YQ.YQ'])
def test_unseal_rejects_garbage(garbage):
    assert tokens.unseal(KEY, garbage, tokens.AuthToken) is None


# --- TokenMint policy: minting and the expiry window ---

def test_mint_and_check_token_within_window():
    clock = MockClock()
    mint = TokenMint(KEY, clock=clock.now)
    token = mint.mint_token('alice', ttl_seconds=100)
    assert mint.check_token(token) == 'alice'
    clock.tick(99)
    assert mint.check_token(token) == 'alice'
    clock.tick(2)  # now past expiry
    assert mint.check_token(token) is None


def test_check_token_rejects_none():
    assert TokenMint(KEY).check_token(None) is None


def test_sealed_token_survives_a_fresh_mint_with_the_same_key():
    # Different TokenMint instance, same secret -> a cookie sealed by one is
    # accepted by another (this is what makes stateless cookies work).
    clock = MockClock()
    sealed = TokenMint(KEY, clock=clock.now).seal_token(
        TokenMint(KEY, clock=clock.now).mint_token('alice', ttl_seconds=100)
    )
    other = TokenMint(KEY, clock=clock.now)
    assert other.check_token(other.unseal_token(sealed)) == 'alice'
