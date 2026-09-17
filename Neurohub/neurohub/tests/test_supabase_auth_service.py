"""Unit tests for Supabase JWT verification (:mod:`neurohub.app.services.supabase_auth_service`)."""

from __future__ import annotations

import time
from collections.abc import Generator
from typing import Any

import httpx
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from jose import jwk, jwt

import neurohub.app.services.supabase_auth_service as supabase_auth_service
from neurohub.app.services.supabase_auth_service import (
    SupabaseAuthError,
    verify_supabase_token,
)

_SUPABASE_URL = "https://test-project.supabase.co"
_KID = "test-key-id"


@pytest.fixture(autouse=True)
def _reset_state(monkeypatch: pytest.MonkeyPatch) -> Generator[None, None, None]:
    """Point the service at a fake project and reset its module-level JWKS cache."""
    monkeypatch.setenv("SUPABASE_URL", _SUPABASE_URL)
    monkeypatch.delenv("SUPABASE_JWT_SECRET", raising=False)
    supabase_auth_service._jwks_cache = None
    supabase_auth_service._jwks_fetched_at = 0.0
    yield
    supabase_auth_service._jwks_cache = None
    supabase_auth_service._jwks_fetched_at = 0.0


def _es256_keypair() -> tuple[Any, dict[str, Any]]:
    """Generate an ES256 keypair and its public JWK representation.

    Returns:
        A ``(private_key, public_jwk)`` tuple.
    """
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_jwk = jwk.construct(private_key.public_key(), algorithm="ES256").to_dict()
    public_jwk["kid"] = _KID
    public_jwk["alg"] = "ES256"
    public_jwk["use"] = "sig"
    return private_key, public_jwk


def _sign(private_key: Any, *, claims: dict[str, Any] | None = None, kid: str = _KID) -> str:
    """Sign a test token with the given private key.

    Args:
        private_key: The EC private key to sign with.
        claims: Override claims; merged over sensible defaults.
        kid: The ``kid`` header to stamp on the token.

    Returns:
        The encoded JWT string.
    """
    payload = {
        "sub": "user-uuid-123",
        "email": "person@example.com",
        "aud": "authenticated",
        "iss": f"{_SUPABASE_URL}/auth/v1",
        "exp": int(time.time()) + 3600,
        "app_metadata": {},
        "user_metadata": {},
    }
    payload.update(claims or {})
    token: str = jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": kid},
    )
    return token


def _mock_jwks(monkeypatch: pytest.MonkeyPatch, public_jwk: dict[str, Any]) -> None:
    """Monkeypatch ``httpx.get`` to return a JWKS document with the given key."""

    def _fake_get(url: str, timeout: float = 10.0) -> httpx.Response:
        assert url == f"{_SUPABASE_URL}/auth/v1/.well-known/jwks.json"
        return httpx.Response(200, json={"keys": [public_jwk]}, request=httpx.Request("GET", url))

    monkeypatch.setattr(supabase_auth_service.httpx, "get", _fake_get)


def test_valid_jwks_token_is_verified(monkeypatch: pytest.MonkeyPatch) -> None:
    """A correctly-signed, current token verifies via the JWKS path."""
    private_key, public_jwk = _es256_keypair()
    _mock_jwks(monkeypatch, public_jwk)
    token = _sign(private_key)

    claims = verify_supabase_token(token)

    assert claims["sub"] == "user-uuid-123"
    assert claims["email"] == "person@example.com"


def test_expired_token_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """A token whose exp claim is in the past must be rejected."""
    private_key, public_jwk = _es256_keypair()
    _mock_jwks(monkeypatch, public_jwk)
    token = _sign(private_key, claims={"exp": int(time.time()) - 60})

    with pytest.raises(SupabaseAuthError):
        verify_supabase_token(token)


def test_wrong_audience_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """A token with an aud other than 'authenticated' must be rejected."""
    private_key, public_jwk = _es256_keypair()
    _mock_jwks(monkeypatch, public_jwk)
    token = _sign(private_key, claims={"aud": "not-authenticated"})

    with pytest.raises(SupabaseAuthError):
        verify_supabase_token(token)


def test_wrong_issuer_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """A token issued for a different Supabase project must be rejected."""
    private_key, public_jwk = _es256_keypair()
    _mock_jwks(monkeypatch, public_jwk)
    token = _sign(private_key, claims={"iss": "https://not-this-project.supabase.co/auth/v1"})

    with pytest.raises(SupabaseAuthError):
        verify_supabase_token(token)


def test_unknown_kid_triggers_refetch_then_fails(monkeypatch: pytest.MonkeyPatch) -> None:
    """An unrecognised kid forces one JWKS refetch before failing (key rotation)."""
    private_key, public_jwk = _es256_keypair()
    calls = {"count": 0}

    def _fake_get(url: str, timeout: float = 10.0) -> httpx.Response:
        calls["count"] += 1
        return httpx.Response(200, json={"keys": [public_jwk]}, request=httpx.Request("GET", url))

    monkeypatch.setattr(supabase_auth_service.httpx, "get", _fake_get)
    token = _sign(private_key, kid="a-kid-not-in-the-jwks")

    with pytest.raises(SupabaseAuthError):
        verify_supabase_token(token)

    # Initial fetch (cache miss) + one forced refetch on unknown kid.
    assert calls["count"] == 2


def test_hs256_fallback_path_when_secret_is_set(monkeypatch: pytest.MonkeyPatch) -> None:
    """When SUPABASE_JWT_SECRET is set, verification uses it instead of JWKS."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "unit-test-shared-secret")
    payload = {
        "sub": "user-uuid-456",
        "email": "hs256@example.com",
        "aud": "authenticated",
        "exp": int(time.time()) + 3600,
    }
    token = jwt.encode(payload, "unit-test-shared-secret", algorithm="HS256")

    claims = verify_supabase_token(token)

    assert claims["sub"] == "user-uuid-456"


def test_hs256_wrong_secret_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """A token signed with a different HS256 secret must be rejected."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "unit-test-shared-secret")
    payload = {
        "sub": "user-uuid-789",
        "aud": "authenticated",
        "exp": int(time.time()) + 3600,
    }
    token = jwt.encode(payload, "a-different-secret", algorithm="HS256")

    with pytest.raises(SupabaseAuthError):
        verify_supabase_token(token)
