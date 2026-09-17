"""Security dependencies for the Global Registry (``/api/v1``) surface.

Unlike :func:`neurohub.app.auth.get_current_user`, the registry dependency always
enforces a valid bearer JWT (it has no auth-disabled bypass) so mutating endpoints
reliably return ``401`` with a ``WWW-Authenticate: Bearer`` header (Property 21).

Auth provider selection
-----------------------
Set ``NEUROHUB_AUTH_PROVIDER`` to control which token format is accepted:

- ``internal`` (default): HMAC JWTs issued by :mod:`neurohub.app.services.registry_auth_service`.
  Used for local development and self-hosted deployments without Supabase.
- ``supabase``: Supabase Auth-issued JWTs verified via
  :mod:`neurohub.app.services.supabase_auth_service` (JWKS or a shared
  ``SUPABASE_JWT_SECRET``). Used for the public deployment, where Supabase
  hosts identity + Postgres + storage for the registry.

Both modes resolve to a :class:`RegistryUser` so downstream endpoints are
provider-agnostic.
"""

from __future__ import annotations

import os
from typing import Annotated, Any

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from neurohub.app.services.registry_auth_service import InvalidTokenError, verify_token

_bearer = HTTPBearer(auto_error=False)

_UNAUTHENTICATED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated",
    headers={"WWW-Authenticate": "Bearer"},
)

# Read once at import time so the provider is stable across the process lifetime.
AUTH_PROVIDER: str = os.environ.get("NEUROHUB_AUTH_PROVIDER", "internal").lower()


class RegistryUser(BaseModel):
    """The authenticated publisher derived from a registry JWT."""

    id: str
    username: str
    roles: list[str] = []

    @property
    def is_admin(self) -> bool:
        """Whether the user holds the admin role."""
        return "admin" in self.roles


def _user_from_internal_token(token: str) -> RegistryUser:
    """Verify an internal HMAC JWT and return the registry user.

    Args:
        token: The bearer token string.

    Returns:
        The authenticated :class:`RegistryUser`.

    Raises:
        HTTPException: ``401`` on invalid or expired token.
    """
    try:
        claims = verify_token(token)
    except InvalidTokenError as exc:
        raise _UNAUTHENTICATED from exc
    return RegistryUser(
        id=str(claims["user_id"]),
        username=str(claims["username"]),
        roles=list(claims.get("roles", [])),
    )


def _user_from_supabase_token(token: str) -> RegistryUser:
    """Verify a Supabase-issued JWT and return the registry user.

    The ``username`` claim is taken from a ``registry_username`` key stored in
    ``user_metadata`` when present (set via POST /api/v1/auth/sync), falling
    back to the email local-part so the user is always identifiable.

    Args:
        token: The Supabase access token string.

    Returns:
        The authenticated :class:`RegistryUser`.

    Raises:
        HTTPException: ``401`` on invalid or expired token.
    """
    from neurohub.app.services.supabase_auth_service import (
        SupabaseAuthError,
        verify_supabase_token,
    )

    try:
        claims = verify_supabase_token(token)
    except SupabaseAuthError as exc:
        raise _UNAUTHENTICATED from exc

    uid: str = claims["sub"]
    email: str = claims.get("email", "")
    user_metadata: dict[str, Any] = claims.get("user_metadata", {}) or {}
    app_metadata: dict[str, Any] = claims.get("app_metadata", {}) or {}
    username: str = user_metadata.get("registry_username") or email.split("@")[0] or uid
    roles: list[str] = ["admin"] if app_metadata.get("role") == "admin" else []

    return RegistryUser(id=uid, username=username, roles=roles)


def get_registry_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> RegistryUser:
    """Validate the bearer token and return the current registry user.

    Dispatches to the internal or Supabase verifier based on
    ``NEUROHUB_AUTH_PROVIDER``.

    Args:
        credentials: The parsed ``Authorization: Bearer`` credentials, if any.

    Returns:
        The authenticated :class:`RegistryUser`.

    Raises:
        HTTPException: ``401`` (with ``WWW-Authenticate: Bearer``) if the token is
            absent, malformed, expired, or missing required claims.
    """
    if credentials is None or not credentials.credentials:
        raise _UNAUTHENTICATED

    token = credentials.credentials
    if AUTH_PROVIDER == "supabase":
        return _user_from_supabase_token(token)
    return _user_from_internal_token(token)


def user_or_ip_key(request: Request) -> str:
    """Rate-limit key: the JWT ``user_id`` when present, else the client IP.

    Args:
        request: The incoming request.

    Returns:
        A stable key string for the rate limiter.
    """
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        token = auth_header.split(" ", 1)[1]
        if AUTH_PROVIDER == "supabase":
            try:
                from neurohub.app.services.supabase_auth_service import (
                    SupabaseAuthError,
                    verify_supabase_token,
                )

                claims = verify_supabase_token(token)
                return f"user:{claims['sub']}"
            except (SupabaseAuthError, KeyError):
                pass
        else:
            try:
                claims = verify_token(token)
                return f"user:{claims['user_id']}"
            except (InvalidTokenError, KeyError, IndexError):
                pass
    client = request.client
    return f"ip:{client.host}" if client else "ip:unknown"


def ensure_owner_or_admin(user: RegistryUser, owner: str) -> None:
    """Authorise a mutation: the caller must own the artefact or be an admin.

    Args:
        user: The authenticated user.
        owner: The artefact's owner field.

    Raises:
        HTTPException: ``403`` if the caller is neither the owner nor an admin.
    """
    owner_username = owner.split("/")[-1]
    if user.is_admin or user.username == owner or user.username == owner_username:
        return
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not the artefact owner")
