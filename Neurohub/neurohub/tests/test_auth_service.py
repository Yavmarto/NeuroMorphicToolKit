"""Unit tests for the Auth Service."""

from datetime import timedelta
import pytest
from jose import jwt
from sqlalchemy.orm import Session

from neurohub.app.services.auth_service import (
    get_password_hash,
    verify_password,
    create_access_token,
    get_current_user,
    SECRET_KEY,
    ALGORITHM,
)
from neurohub.db.models import UserDB


def test_password_hashing():
    """Test password hashing and verification."""
    password = "secret_password"
    hashed = get_password_hash(password)
    assert hashed != password
    assert verify_password(password, hashed)
    assert not verify_password("wrong_password", hashed)


def test_create_access_token():
    """Test JWT access token creation and payload."""
    data = {"sub": "testuser"}
    token = create_access_token(data)

    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert payload["sub"] == "testuser"
    assert "exp" in payload


def test_create_access_token_with_delta():
    """Test JWT access token creation with a custom expiration delta."""
    data = {"sub": "testuser"}
    expires_delta = timedelta(minutes=5)
    token = create_access_token(data, expires_delta=expires_delta)

    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert payload["sub"] == "testuser"
    assert "exp" in payload


@pytest.mark.asyncio
async def test_get_current_user_success(db_session: Session):
    """Test retrieving the current user from a valid JWT."""
    # Create a user in the database
    user = UserDB(
        id="user123",
        username="jwtuser",
        email="jwt@example.com",
        full_name="JWT User",
        hashed_password="hashed",
        is_active=True,
        is_admin=False,
    )
    db_session.add(user)
    db_session.commit()

    # Generate token
    token = create_access_token(data={"sub": "jwtuser"})

    # Retrieve user
    retrieved_user = await get_current_user(token=token, db=db_session)
    assert retrieved_user.id == "user123"
    assert retrieved_user.username == "jwtuser"


@pytest.mark.asyncio
async def test_get_current_user_invalid_token(db_session: Session):
    """Test error when an invalid JWT is provided."""
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as excinfo:
        await get_current_user(token="invalid_token", db=db_session)
    assert excinfo.value.status_code == 401
    assert "could not validate credentials" in excinfo.value.detail.lower()


@pytest.mark.asyncio
async def test_get_current_user_missing_sub(db_session: Session):
    """Test error when the JWT is missing the 'sub' claim."""
    from fastapi import HTTPException

    token = jwt.encode({"not_sub": "value"}, SECRET_KEY, algorithm=ALGORITHM)
    with pytest.raises(HTTPException) as excinfo:
        await get_current_user(token=token, db=db_session)
    assert excinfo.value.status_code == 401
    assert "could not validate credentials" in excinfo.value.detail.lower()


@pytest.mark.asyncio
async def test_get_current_user_nonexistent(db_session: Session):
    """Test error when the user in the JWT does not exist in the DB."""
    from fastapi import HTTPException

    token = create_access_token(data={"sub": "nonexistent"})
    with pytest.raises(HTTPException) as excinfo:
        await get_current_user(token=token, db=db_session)
    assert excinfo.value.status_code == 401
    assert "could not validate credentials" in excinfo.value.detail.lower()
