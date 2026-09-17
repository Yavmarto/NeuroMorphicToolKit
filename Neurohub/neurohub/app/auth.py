"""Authentication and authorization dependencies for NeuroHub."""

import os
from typing import Annotated

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import APIKeyHeader, OAuth2PasswordBearer
from jose import JWTError, jwt
from pydantic import AliasChoices, BaseModel, Field

API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)
OAUTH2_SCHEME = OAuth2PasswordBearer(tokenUrl="/api/neurohub/auth/login", auto_error=False)


def is_auth_enabled() -> bool:
    """Check if authentication is enabled via environment variable."""
    return os.getenv("NEUROHUB_AUTH_ENABLED", "false").lower() == "true"


def get_admin_api_key() -> str | None:
    """Get the admin API key from environment variable."""
    return os.getenv("NEUROHUB_ADMIN_API_KEY")


def get_viewer_api_key() -> str | None:
    """Get the viewer API key from environment variable."""
    return os.getenv("NEUROHUB_VIEWER_API_KEY")


class User(BaseModel):
    """User representation with role."""

    id: str = Field(validation_alias=AliasChoices("id", "user_id"))
    username: str = "unknown"
    role: str = "viewer"
    is_active: bool = True

    @property
    def user_id(self) -> str:
        """Alias for id to maintain backward compatibility."""
        return self.id

    @property
    def is_admin(self) -> bool:
        """Check if the user is an admin."""
        return self.role == "admin"


async def get_current_user(
    api_key: Annotated[str | None, Security(API_KEY_HEADER)] = None,
    token: Annotated[str | None, Depends(OAUTH2_SCHEME)] = None,
) -> User:
    """Dependency to get the current user based on API key or JWT token.

    Args:
        api_key: The API key from the X-API-Key header.
        token: The JWT token from the Authorization header.

    Returns:
        The User object if authentication is successful or disabled.

    Raises:
        HTTPException: If authentication is enabled and credentials are invalid.
    """
    if not is_auth_enabled():
        # In dev mode with auth disabled, we return a default admin user
        return User(id="testuser", username="testuser", role="admin")

    # Priority 1: JWT Token
    if token:
        from neurohub.app.services.auth_service import ALGORITHM, SECRET_KEY
        from neurohub.db.database import SessionLocal
        from neurohub.db.models import UserDB

        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
            username: str | None = payload.get("sub")
            if username:
                with SessionLocal() as db:
                    user_db = db.query(UserDB).filter(UserDB.username == username).first()
                    if user_db:
                        return User(
                            id=user_db.id,
                            username=user_db.username,
                            role="admin" if user_db.is_admin else "viewer",
                            is_active=user_db.is_active,
                        )
        except JWTError:
            pass

    # Priority 2: API Key
    if api_key:
        admin_api_key = get_admin_api_key()
        viewer_api_key = get_viewer_api_key()

        if admin_api_key and api_key == admin_api_key:
            return User(id="admin", username="admin", role="admin")
        if viewer_api_key and api_key == viewer_api_key:
            return User(id="viewer", username="viewer", role="viewer")

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or missing credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def require_admin(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    """Dependency to require admin role.

    Args:
        current_user: The current authenticated user.

    Returns:
        The user if they have the admin role.

    Raises:
        HTTPException: If the user does not have the admin role.
    """
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )
    return current_user
