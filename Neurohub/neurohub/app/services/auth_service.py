"""Service for authentication and authorization in NeuroHub."""

import os
from datetime import datetime, timedelta, UTC
from typing import Any, cast

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from neurohub.app.schemas.users import TokenData
from neurohub.db.database import get_db
from neurohub.db.models import UserDB

# Configuration
SECRET_KEY = os.environ.get("NEUROHUB_SECRET_KEY", "")
# Empty string means JWT operations fail loudly when the key is missing.
# The startup guard in main._validate_startup_config() provides the user-facing message.
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
REFRESH_TOKEN_EXPIRE_DAYS = 7

_BCRYPT_MAX_PASSWORD_BYTES = 72

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/neurohub/auth/login")


def _password_bytes(password: str) -> bytes:
    encoded = password.encode("utf-8")
    if len(encoded) > _BCRYPT_MAX_PASSWORD_BYTES:
        raise ValueError("password cannot be longer than 72 bytes")
    return encoded


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plain password against its hash."""
    return bcrypt.checkpw(
        _password_bytes(plain_password),
        hashed_password.encode("utf-8"),
    )


def get_password_hash(password: str) -> str:
    """Generate a hash for a given password."""
    digest = bcrypt.hashpw(_password_bytes(password), bcrypt.gensalt())
    return digest.decode("utf-8")


def create_access_token(data: dict[str, Any], expires_delta: timedelta | None = None) -> str:
    """Create a new JWT access token."""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(UTC) + expires_delta
    else:
        expire = datetime.now(UTC) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire, "type": "access"})
    encoded_jwt = cast(str, jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM))
    return encoded_jwt


def create_refresh_token(data: dict[str, Any], expires_delta: timedelta | None = None) -> str:
    """Create a new JWT refresh token."""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(UTC) + expires_delta
    else:
        expire = datetime.now(UTC) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire, "type": "refresh"})
    encoded_jwt = cast(str, jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM))
    return encoded_jwt


async def get_current_user(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> UserDB:
    """Dependency to retrieve the current authenticated user."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str | None = payload.get("sub")
        token_type: str | None = payload.get("type")
        if username is None or token_type != "access":
            raise credentials_exception
        token_data = TokenData(username=username)
    except JWTError as err:
        raise credentials_exception from err
    user = db.query(UserDB).filter(UserDB.username == token_data.username).first()
    if user is None:
        raise credentials_exception
    return user


async def get_current_active_user(
    current_user: UserDB = Depends(get_current_user),
) -> UserDB:
    """Dependency to retrieve the current active user."""
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


async def get_current_admin_user(
    current_user: UserDB = Depends(get_current_active_user),
) -> UserDB:
    """Dependency to retrieve the current admin user."""
    if not current_user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not enough permissions")
    return current_user
