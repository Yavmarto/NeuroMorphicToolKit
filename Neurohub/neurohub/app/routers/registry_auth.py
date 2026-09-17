"""Registry authentication endpoints (``/api/v1/auth``).

Auth provider selection
-----------------------
``NEUROHUB_AUTH_PROVIDER`` controls which flow is active:

- ``internal`` (default): email/password registration and login via
  :mod:`neurohub.app.services.registry_auth_service`.
  ``POST /register``, ``POST /login``, ``POST /refresh`` are all available.

- ``supabase``: registration and login are handled client-side by the
  Supabase Auth SDK.  ``POST /register`` and ``POST /login`` return
  ``501 Not Implemented``.  ``POST /sync`` is available to create or update
  the local ``UserDB`` row from a valid Supabase bearer token (called by the
  Flutter app on first sign-in and on profile changes).
"""

from __future__ import annotations

import os
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import InstrumentedAttribute, Session

from neurohub.app.limiter import limiter
from neurohub.app.registry_security import RegistryUser, get_registry_user
from neurohub.app.services.registry_auth_service import (
    DuplicateUserError,
    InvalidCredentialsError,
    InvalidTokenError,
    issue_access_token,
    login_user,
    refresh_access_token,
    register_user,
    verify_token,
)
from neurohub.db.database import get_db
from neurohub.db.models import UserDB

router = APIRouter(prefix="/auth", tags=["Registry Auth"])

_AUTH_PROVIDER: str = os.environ.get("NEUROHUB_AUTH_PROVIDER", "internal").lower()

_EXTERNAL_AUTH_ONLY = HTTPException(
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    detail=(
        "This endpoint is disabled when NEUROHUB_AUTH_PROVIDER is not 'internal'. "
        "Registration and login are handled by your identity provider's own SDK."
    ),
)


# ---------------------------------------------------------------------------
# Internal-auth schemas
# ---------------------------------------------------------------------------


class RegisterRequest(BaseModel):
    """Body for ``POST /api/v1/auth/register``."""

    username: str
    email: EmailStr
    full_name: str = ""
    password: str


class RegisterResponse(BaseModel):
    """Response for a successful registration."""

    id: str
    username: str


class LoginRequest(BaseModel):
    """Body for ``POST /api/v1/auth/login``."""

    username: str
    password: str


class TokenResponse(BaseModel):
    """Access/refresh token pair issued at login."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    """Body for ``POST /api/v1/auth/refresh``."""

    refresh_token: str


class AccessTokenResponse(BaseModel):
    """A freshly minted access token."""

    access_token: str
    token_type: str = "bearer"


# ---------------------------------------------------------------------------
# External-auth (Supabase) schemas
# ---------------------------------------------------------------------------


class SyncRequest(BaseModel):
    """Body for ``POST /api/v1/auth/sync`` (external auth providers only).

    The provider's bearer token is passed in the ``Authorization: Bearer``
    header (handled by ``get_registry_user``); this body carries the desired
    Neurohub username for the first-time sync.  On subsequent calls the
    username is ignored if a ``UserDB`` row already exists for the provider's
    user id.
    """

    username: str
    full_name: str = ""


class SyncResponse(BaseModel):
    """Response for a successful external-auth user sync."""

    id: str
    username: str
    created: bool


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/register", response_model=RegisterResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("5/hour")
def register(
    request: Request, response: Response, body: RegisterRequest, db: Session = Depends(get_db)
) -> RegisterResponse:
    """Register a new publisher account (internal auth only).

    Args:
        request: The incoming request (required by the rate limiter).
        response: The outgoing response (required by the rate limiter).
        body: The registration payload.
        db: The database session.

    Returns:
        The new user's id and username.

    Raises:
        HTTPException: ``501`` when ``NEUROHUB_AUTH_PROVIDER`` is not ``internal``.
        HTTPException: ``409`` if the username or email already exists.
    """
    del response
    if _AUTH_PROVIDER != "internal":
        raise _EXTERNAL_AUTH_ONLY
    try:
        user = register_user(
            db,
            username=body.username,
            email=str(body.email),
            full_name=body.full_name,
            password=body.password,
        )
    except DuplicateUserError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    return RegisterResponse(id=user.id, username=user.username)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("10/minute")
def login(
    request: Request, response: Response, body: LoginRequest, db: Session = Depends(get_db)
) -> TokenResponse:
    """Authenticate and issue an access/refresh token pair (internal auth only).

    Args:
        request: The incoming request (required by the rate limiter).
        response: The outgoing response (required by the rate limiter).
        body: The login payload.
        db: The database session.

    Returns:
        The issued token pair.

    Raises:
        HTTPException: ``501`` when ``NEUROHUB_AUTH_PROVIDER`` is not ``internal``.
        HTTPException: ``401`` on invalid credentials.
    """
    del response
    if _AUTH_PROVIDER != "internal":
        raise _EXTERNAL_AUTH_ONLY
    try:
        access, refresh = login_user(db, username=body.username, password=body.password)
    except InvalidCredentialsError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    return TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/refresh", response_model=AccessTokenResponse)
@limiter.limit("60/minute")
def refresh(
    request: Request, response: Response, body: RefreshRequest, db: Session = Depends(get_db)
) -> AccessTokenResponse:
    """Exchange a refresh token for a new access token (internal auth only).

    Args:
        request: The incoming request (required by the rate limiter).
        response: The outgoing response (required by the rate limiter).
        body: The refresh payload.
        db: The database session.

    Returns:
        A new access token.

    Raises:
        HTTPException: ``501`` when ``NEUROHUB_AUTH_PROVIDER`` is not ``internal``.
        HTTPException: ``401`` if the refresh token is invalid or expired.
    """
    del response
    if _AUTH_PROVIDER != "internal":
        raise _EXTERNAL_AUTH_ONLY
    try:
        access = refresh_access_token(db, body.refresh_token)
    except InvalidTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    return AccessTokenResponse(access_token=access)


def _uid_column_for_provider() -> InstrumentedAttribute[str | None]:
    """Return the ``UserDB`` column keying users for the active auth provider.

    Returns:
        ``UserDB.supabase_uid`` under ``supabase`` mode.

    Raises:
        HTTPException: ``501`` if called while ``NEUROHUB_AUTH_PROVIDER=internal``
            (sync is meaningless there — there is no external provider UID).
    """
    if _AUTH_PROVIDER == "supabase":
        return UserDB.supabase_uid
    raise _EXTERNAL_AUTH_ONLY


def _placeholder_email_domain() -> str:
    """Return the placeholder email domain used when a provider username isn't an email."""
    return f"{_AUTH_PROVIDER}.local"


@router.post("/sync", response_model=SyncResponse, status_code=status.HTTP_200_OK)
@limiter.limit("30/minute")
def sync_user(
    request: Request,
    response: Response,
    body: SyncRequest,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> SyncResponse:
    """Create or update the local UserDB row from an external-auth bearer token.

    Called by the Flutter app immediately after a successful Supabase
    sign-in. On first call the row is created; subsequent calls are
    idempotent (the username is not changed after the initial sync to avoid
    breaking artefact ownership references).

    Args:
        request: The incoming request (required by the rate limiter).
        response: The outgoing response (required by the rate limiter).
        body: The sync payload with desired username and full name.
        user: The authenticated registry user (provider UID in ``user.id``).
        db: The database session.

    Returns:
        The Neurohub user id, resolved username, and whether the row was created.

    Raises:
        HTTPException: ``501`` if ``NEUROHUB_AUTH_PROVIDER=internal``.
        HTTPException: ``409`` if the desired username is already taken by
            a different provider UID.
    """
    del response
    uid_column = _uid_column_for_provider()

    existing = db.query(UserDB).filter(uid_column == user.id).first()
    if existing is not None:
        # Idempotent — row exists; update full_name if provided.
        if body.full_name and body.full_name != existing.full_name:
            existing.full_name = body.full_name
            db.commit()
        return SyncResponse(id=existing.id, username=existing.username, created=False)

    # First sync — check username uniqueness.
    username_taken = db.query(UserDB).filter(UserDB.username == body.username).first()
    if username_taken is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Username '{body.username}' is already taken. Choose a different username.",
        )

    new_user = UserDB(
        id=str(uuid.uuid4()),
        username=body.username,
        email=(
            user.username
            if "@" in user.username
            else f"{user.username}@{_placeholder_email_domain()}"
        ),
        full_name=body.full_name,
        hashed_password="",  # Not used in external auth modes.
        is_active=True,
        is_admin=False,
        supabase_uid=user.id,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return SyncResponse(id=new_user.id, username=new_user.username, created=True)


# Re-exported for tests that need to mint a token for a known user.
__all__ = ["router", "issue_access_token", "verify_token", "UserDB"]
