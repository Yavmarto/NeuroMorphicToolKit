"""Authentication service for the Global Registry (``/api/v1/auth``).

Reuses the password hashing and signing key from :mod:`neurohub.app.services.auth_service`
but issues registry-flavoured JWTs carrying ``user_id``, ``username``, ``roles`` and
``exp`` claims (correctness Property 22). Refresh tokens are persisted in the
Redis-compatible store at ``CACHE_URL`` when reachable, degrading gracefully to a
stateless check otherwise.
"""

from __future__ import annotations

import logging
import os
import uuid
from datetime import datetime, timedelta, UTC
from typing import Any, cast

from jose import JWTError, jwt
from sqlalchemy.orm import Session

from neurohub.app.services.auth_service import (
    ALGORITHM,
    SECRET_KEY,
    get_password_hash,
    verify_password,
)
from neurohub.db.models import UserDB

logger = logging.getLogger(__name__)


class RegistryAuthError(Exception):
    """Base error for registry authentication failures."""


class DuplicateUserError(RegistryAuthError):
    """Raised when a username or email is already registered (→ HTTP 409)."""


class InvalidCredentialsError(RegistryAuthError):
    """Raised when login credentials do not match (→ HTTP 401)."""


class InvalidTokenError(RegistryAuthError):
    """Raised when a JWT is missing, expired, malformed, or revoked (→ HTTP 401)."""


def _jwt_expiry_hours() -> int:
    """Read the access-token lifetime in hours from the environment (default 24)."""
    try:
        return int(os.environ.get("JWT_EXPIRY_HOURS", "24"))
    except ValueError:
        return 24


def _roles_for(user: UserDB) -> list[str]:
    """Derive the role list claim for a user."""
    return ["admin"] if user.is_admin else ["user"]


def _redis_client() -> Any | None:
    """Return a Redis client for ``CACHE_URL``, or ``None`` if unavailable."""
    cache_url = os.environ.get("CACHE_URL")
    if not cache_url:
        return None
    try:
        import redis

        client = redis.Redis.from_url(cache_url)
        client.ping()
        return client
    except Exception as exc:  # noqa: BLE001 - degrade gracefully on any Redis error
        logger.warning("Redis unavailable for refresh tokens (%s); using stateless mode", exc)
        return None


def issue_access_token(user: UserDB) -> str:
    """Issue a signed access JWT carrying the registry claim set.

    Args:
        user: The authenticated user.

    Returns:
        The encoded JWT string.
    """
    now = datetime.now(UTC)
    expire = now + timedelta(hours=_jwt_expiry_hours())
    payload = {
        "user_id": user.id,
        "username": user.username,
        "roles": _roles_for(user),
        "type": "access",
        "exp": expire,
    }
    return cast(str, jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM))


def issue_refresh_token(user: UserDB) -> str:
    """Issue a refresh token and persist it in the cache store when available.

    Args:
        user: The authenticated user.

    Returns:
        The opaque refresh-token string (a UUID v4).
    """
    token = str(uuid.uuid4())
    client = _redis_client()
    if client is not None:
        # 30-day refresh window.
        client.setex(f"refresh:{token}", 30 * 24 * 3600, user.username)
    return token


def register_user(
    db: Session,
    *,
    username: str,
    email: str,
    full_name: str,
    password: str,
) -> UserDB:
    """Create a new user with a bcrypt-hashed password.

    Args:
        db: The database session.
        username: The desired username.
        email: The user's email address.
        full_name: The user's display name.
        password: The plaintext password (never stored).

    Returns:
        The persisted :class:`UserDB`.

    Raises:
        DuplicateUserError: If the username or email is already taken.
    """
    existing = (
        db.query(UserDB).filter((UserDB.username == username) | (UserDB.email == email)).first()
    )
    if existing is not None:
        raise DuplicateUserError("username or email already registered")

    user = UserDB(
        id=str(uuid.uuid4()),
        username=username,
        email=email,
        full_name=full_name,
        hashed_password=get_password_hash(password),
        is_active=True,
        is_admin=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def login_user(db: Session, *, username: str, password: str) -> tuple[str, str]:
    """Validate credentials and issue an (access, refresh) token pair.

    Args:
        db: The database session.
        username: The submitted username.
        password: The submitted plaintext password.

    Returns:
        A ``(access_token, refresh_token)`` tuple.

    Raises:
        InvalidCredentialsError: If the user is unknown or the password is wrong.
    """
    user = db.query(UserDB).filter(UserDB.username == username).first()
    if user is None or not verify_password(password, user.hashed_password):
        raise InvalidCredentialsError("invalid username or password")
    return issue_access_token(user), issue_refresh_token(user)


def verify_token(token: str) -> dict[str, Any]:
    """Decode and validate an access JWT.

    Args:
        token: The bearer token.

    Returns:
        The decoded claim payload.

    Raises:
        InvalidTokenError: If the token is malformed, expired, or not an access token.
    """
    try:
        payload: dict[str, Any] = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        raise InvalidTokenError(str(exc)) from exc
    if payload.get("type") != "access":
        raise InvalidTokenError("not an access token")
    if "user_id" not in payload or "username" not in payload:
        raise InvalidTokenError("missing required claims")
    return payload


def refresh_access_token(db: Session, refresh_token: str) -> str:
    """Exchange a valid refresh token for a fresh access token.

    Args:
        db: The database session.
        refresh_token: The opaque refresh token issued at login.

    Returns:
        A new access JWT.

    Raises:
        InvalidTokenError: If the refresh token is unknown, expired, or its user
            no longer exists.
    """
    client = _redis_client()
    if client is None:
        # Stateless mode: no server-side store to validate against.
        raise InvalidTokenError("refresh tokens require a configured CACHE_URL")
    raw = client.get(f"refresh:{refresh_token}")
    if raw is None:
        raise InvalidTokenError("unknown or expired refresh token")
    username = raw.decode() if isinstance(raw, bytes) else str(raw)
    user = db.query(UserDB).filter(UserDB.username == username).first()
    if user is None:
        raise InvalidTokenError("user no longer exists")
    return issue_access_token(user)
