"""Supabase-issued JWT verification for the Global Registry.

This module is only imported when ``NEUROHUB_AUTH_PROVIDER=supabase``. Supabase
Auth mints its own JWTs; unlike Firebase there is no ``firebase-admin``-style SDK
that verifies tokens for us, so this module fetches and caches Supabase's JWKS
document itself using ``httpx`` and ``python-jose`` (both already base
dependencies — no new dependency is required).

Two verification modes are supported, since Supabase projects may be on either:

- JWKS / asymmetric signing (current default for new projects): the token's
  ``kid`` header is matched against a key fetched from
  ``{SUPABASE_URL}/auth/v1/.well-known/jwks.json`` and cached for
  :data:`_JWKS_CACHE_TTL_SECONDS`.
- Legacy HS256 shared-secret signing (older projects): set
  ``SUPABASE_JWT_SECRET`` and tokens are verified against it directly, no
  network call needed.

If ``SUPABASE_JWT_SECRET`` is set, it takes precedence (no network dependency,
so prefer it when available). Otherwise ``SUPABASE_URL`` is required for the
JWKS path.
"""

from __future__ import annotations

import os
import time
from typing import Any

import httpx
from jose import jwk, jwt
from jose.exceptions import JOSEError

_JWKS_CACHE_TTL_SECONDS = 3600

_jwks_cache: dict[str, Any] | None = None
_jwks_fetched_at: float = 0.0


class SupabaseAuthError(Exception):
    """Raised when a Supabase JWT is invalid or cannot be verified (→ HTTP 401)."""


def _supabase_url() -> str:
    """Return the configured Supabase project URL.

    Returns:
        The ``SUPABASE_URL`` environment value, with any trailing slash stripped.

    Raises:
        SupabaseAuthError: If ``SUPABASE_URL`` is not configured.
    """
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    if not url:
        raise SupabaseAuthError("SUPABASE_URL must be set to verify Supabase JWTs via JWKS")
    return url


def _fetch_jwks(*, force: bool = False) -> dict[str, Any]:
    """Fetch (or return the cached) Supabase JWKS document.

    Args:
        force: When ``True``, bypass the cache and refetch unconditionally
            (used to handle key rotation on a ``kid`` cache miss).

    Returns:
        The decoded JWKS document (a dict with a ``keys`` list).

    Raises:
        SupabaseAuthError: On a network failure or a non-200 response.
    """
    global _jwks_cache, _jwks_fetched_at

    now = time.monotonic()
    if not force and _jwks_cache is not None and (now - _jwks_fetched_at) < _JWKS_CACHE_TTL_SECONDS:
        return _jwks_cache

    url = f"{_supabase_url()}/auth/v1/.well-known/jwks.json"
    try:
        response = httpx.get(url, timeout=10.0)
        response.raise_for_status()
        jwks: dict[str, Any] = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise SupabaseAuthError(f"Failed to fetch Supabase JWKS from {url}: {exc}") from exc

    _jwks_cache = jwks
    _jwks_fetched_at = now
    return jwks


def _get_signing_key(kid: str) -> dict[str, Any]:
    """Resolve a JWK by key id, refetching once on a cache miss.

    Args:
        kid: The key id from the token's ``kid`` header.

    Returns:
        The matching JWK as a dict.

    Raises:
        SupabaseAuthError: If no key with this ``kid`` exists even after a
            forced refetch (handles key rotation).
    """
    jwks = _fetch_jwks()
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return dict(key)

    # Key rotation: refetch once before giving up.
    jwks = _fetch_jwks(force=True)
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return dict(key)

    raise SupabaseAuthError(f"Unknown Supabase signing key id: {kid}")


def verify_supabase_token(token: str) -> dict[str, Any]:
    """Verify a Supabase-issued JWT and return its decoded claims.

    Args:
        token: The raw bearer token from the ``Authorization`` header.

    Returns:
        The decoded claim payload (``sub``, ``email``, ``app_metadata``,
        ``user_metadata``, ``aud``, ``exp``, ``iss``, ...).

    Raises:
        SupabaseAuthError: If the token is invalid, expired, from the wrong
            audience/issuer, or its signing key cannot be resolved.
    """
    shared_secret = os.environ.get("SUPABASE_JWT_SECRET")
    try:
        if shared_secret:
            claims: dict[str, Any] = jwt.decode(
                token,
                shared_secret,
                algorithms=["HS256"],
                audience="authenticated",
            )
            return claims

        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        if not kid:
            raise SupabaseAuthError("Supabase token header is missing 'kid'")
        jwk_dict = _get_signing_key(kid)
        signing_key = jwk.construct(jwk_dict, algorithm=jwk_dict.get("alg", "ES256"))
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=[jwk_dict.get("alg", "ES256")],
            audience="authenticated",
            issuer=f"{_supabase_url()}/auth/v1",
        )
        return claims
    except SupabaseAuthError:
        raise
    except JOSEError as exc:
        raise SupabaseAuthError(f"Invalid Supabase token: {exc}") from exc
