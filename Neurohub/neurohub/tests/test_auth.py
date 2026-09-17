"""Tests for NeuroHub authentication and role-based access control."""

from unittest.mock import patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from neurohub.app.auth import get_current_user
from neurohub.app.main import app

ADMIN_KEY = "test-admin-key"
VIEWER_KEY = "test-viewer-key"


@pytest.fixture
def auth_client(client: TestClient) -> TestClient:
    """Provides a TestClient with authentication enabled."""
    # Remove the override from conftest.py to test actual auth logic
    if get_current_user in app.dependency_overrides:
        del app.dependency_overrides[get_current_user]

    with (
        patch("neurohub.app.auth.is_auth_enabled", return_value=True),
        patch("neurohub.app.auth.get_admin_api_key", return_value=ADMIN_KEY),
        patch("neurohub.app.auth.get_viewer_api_key", return_value=VIEWER_KEY),
    ):
        yield client


# --- Startup security guard tests ---

_KNOWN_BAD_KEY = "09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7"


def test_validate_startup_config_fails_with_known_bad_key(monkeypatch: pytest.MonkeyPatch) -> None:
    """Production startup must refuse to run with the publicly-known default SECRET_KEY."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("NEUROHUB_SECRET_KEY", _KNOWN_BAD_KEY)
    monkeypatch.setenv("JWT_SECRET", "some-jwt-secret")  # satisfy the existing check

    from neurohub.app.main import _validate_startup_config

    with pytest.raises(SystemExit) as exc_info:
        _validate_startup_config()
    assert exc_info.value.code == 1


def test_validate_startup_config_fails_without_secret_key_in_production(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Production startup must refuse to run when NEUROHUB_SECRET_KEY is missing."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.delenv("NEUROHUB_SECRET_KEY", raising=False)
    monkeypatch.setenv("JWT_SECRET", "some-jwt-secret")

    from neurohub.app.main import _validate_startup_config

    with pytest.raises(SystemExit) as exc_info:
        _validate_startup_config()
    assert exc_info.value.code == 1


def test_validate_startup_config_passes_with_valid_key(monkeypatch: pytest.MonkeyPatch) -> None:
    """Production startup must succeed when a strong unique key is provided."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("NEUROHUB_SECRET_KEY", "a" * 64)  # 64-char non-default key
    monkeypatch.setenv("JWT_SECRET", "some-jwt-secret")  # satisfy the existing check
    monkeypatch.setenv("NEUROHUB_AUTH_ENABLED", "true")  # satisfy the existing check

    from neurohub.app.main import _validate_startup_config

    _validate_startup_config()  # must not raise


def test_auth_disabled_by_default(client: TestClient) -> None:
    """Test that authentication is disabled by default (dev mode)."""
    # Remove the override from conftest.py to test actual auth logic
    if get_current_user in app.dependency_overrides:
        del app.dependency_overrides[get_current_user]

    with patch("neurohub.app.auth.is_auth_enabled", return_value=False):
        # Should be able to access health without API key
        response = client.get("/api/neurohub/health")
        assert response.status_code == 200


def test_unauthenticated_access_rejected(auth_client: TestClient) -> None:
    """Test that access is rejected when auth is enabled and no credentials provided."""
    response = auth_client.get("/api/neurohub/projects")
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid or missing credentials"


def test_invalid_api_key_rejected(auth_client: TestClient) -> None:
    """Test that access is rejected with an invalid API key."""
    response = auth_client.get("/api/neurohub/projects", headers={"X-API-Key": "invalid-key"})
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid or missing credentials"


def test_valid_admin_api_key_accepted(auth_client: TestClient) -> None:
    """Test that admin access is allowed with a valid admin API key."""
    response = auth_client.get("/api/neurohub/projects", headers={"X-API-Key": ADMIN_KEY})
    assert response.status_code == 200


def test_valid_viewer_api_key_accepted(auth_client: TestClient) -> None:
    """Test that viewer access is allowed with a valid viewer API key."""
    response = auth_client.get("/api/neurohub/projects", headers={"X-API-Key": VIEWER_KEY})
    assert response.status_code == 200


def test_viewer_cannot_delete_project(auth_client: TestClient) -> None:
    """Test that a user with viewer role cannot delete a project."""
    # First, create a project (with auth disabled)
    with patch("neurohub.app.auth.is_auth_enabled", return_value=False):
        auth_client.post(
            "/api/neurohub/projects",
            json={
                "id": "test-proj",
                "name": "Test",
                "description": "Test",
                "created_at": "2026-03-16T00:00:00Z",
                "updated_at": "2026-03-16T00:00:00Z",
                "owner": "alice",
                "members": [],
                "links": {},
                "tags": [],
            },
        )

    # Try to delete as viewer
    response = auth_client.delete(
        "/api/neurohub/projects/test-proj",
        headers={"X-API-Key": VIEWER_KEY},
    )
    assert response.status_code == 403
    assert "Not a project member" in response.json()["detail"]


def test_admin_can_delete_project(auth_client: TestClient) -> None:
    """Test that an admin can delete a project."""
    # First, create a project
    with patch("neurohub.app.auth.is_auth_enabled", return_value=False):
        auth_client.post(
            "/api/neurohub/projects",
            json={
                "id": "test-proj-2",
                "name": "Test",
                "description": "Test",
                "created_at": "2026-03-16T00:00:00Z",
                "updated_at": "2026-03-16T00:00:00Z",
                "owner": "alice",
                "members": [],
                "links": {},
                "tags": [],
            },
        )

    # Delete as admin
    response = auth_client.delete(
        "/api/neurohub/projects/test-proj-2",
        headers={"X-API-Key": ADMIN_KEY},
    )
    assert response.status_code == 204


def test_viewer_cannot_update_config(auth_client: TestClient) -> None:
    """Test that a viewer cannot update the suite configuration."""
    response = auth_client.put(
        "/api/neurohub/config",
        headers={"X-API-Key": VIEWER_KEY},
        json={"neurosim_url": "http://hacked:8001"},
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "Admin role required"


def test_admin_can_update_config(auth_client: TestClient) -> None:
    """Test that an admin can update the suite configuration."""
    response = auth_client.put(
        "/api/neurohub/config",
        headers={"X-API-Key": ADMIN_KEY},
        json={
            "neurosim_url": "http://new-url:8001",
            "neurochip_url": "http://localhost:8002",
            "neurobench_url": "http://localhost:8003",
            "neurosense_url": "http://localhost:8004",
            "neurocnl_url": "http://localhost:8000",
            "shared_storage_path": "./shared",
            "default_project_settings": {},
        },
    )
    assert response.status_code == 200


def test_viewer_cannot_create_project(auth_client: TestClient) -> None:
    """Test that a viewer cannot create a project."""
    response = auth_client.post(
        "/api/neurohub/projects",
        headers={"X-API-Key": VIEWER_KEY},
        json={
            "id": "viewer-proj",
            "name": "Viewer Project",
            "description": "Should fail",
            "created_at": "2026-03-16T00:00:00Z",
            "updated_at": "2026-03-16T00:00:00Z",
            "owner": "viewer",
            "members": [],
            "links": {},
            "tags": [],
        },
    )
    assert response.status_code == 403


# Service tests for auth_service


def _create_test_user(db_session, *, username: str, email: str, password: str):
    """Create a UserDB row directly.

    The legacy /api/neurohub/auth router that used to do this was retired;
    registry/Supabase auth own registration now.
    """
    import uuid

    from neurohub.app.services.auth_service import get_password_hash
    from neurohub.db.models import UserDB

    db_user = UserDB(
        id=str(uuid.uuid4()),
        username=username,
        email=email,
        full_name="",
        hashed_password=get_password_hash(password),
        is_active=True,
        is_admin=False,
    )
    db_session.add(db_user)
    db_session.commit()
    db_session.refresh(db_user)
    return db_user


@pytest.mark.asyncio
async def test_auth_service_flow(db_session):
    """Test the low-level auth service functions."""
    from neurohub.app.services.auth_service import (
        create_access_token,
        get_current_user,
        get_current_active_user,
        get_current_admin_user,
    )

    # 1. Register a user
    db_user = _create_test_user(
        db_session, username="svcuser", email="svc@example.com", password="pwd"
    )

    # 2. Create token
    token = create_access_token(data={"sub": db_user.username})

    # 3. Get current user from token
    current_user = await get_current_user(token=token, db=db_session)
    assert current_user.username == "svcuser"

    # 4. Active user check
    active_user = await get_current_active_user(current_user=current_user)
    assert active_user.id == db_user.id

    # 5. Admin check (should fail)
    with pytest.raises(HTTPException) as exc:
        await get_current_admin_user(current_user=current_user)
    assert exc.value.status_code == 403

    # 6. Promote to admin and check again
    db_user.is_admin = True
    db_session.commit()
    admin_user = await get_current_admin_user(current_user=db_user)
    assert admin_user.is_admin is True


@pytest.mark.asyncio
async def test_get_current_user_invalid_token(db_session):
    """Test get_current_user with an invalid token."""
    from neurohub.app.services.auth_service import get_current_user

    with pytest.raises(HTTPException) as exc:
        await get_current_user(token="invalidtoken", db=db_session)
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_user_no_sub(db_session):
    """Test get_current_user with a valid token but no sub."""
    from neurohub.app.services.auth_service import get_current_user
    from jose import jwt
    from neurohub.app.services.auth_service import SECRET_KEY, ALGORITHM

    token = jwt.encode({"exp": 9999999999}, SECRET_KEY, algorithm=ALGORITHM)

    with pytest.raises(HTTPException) as exc:
        await get_current_user(token=token, db=db_session)
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_user_user_not_found(db_session):
    """Test get_current_user with a user that doesn't exist."""
    from neurohub.app.services.auth_service import get_current_user
    from jose import jwt
    from neurohub.app.services.auth_service import SECRET_KEY, ALGORITHM

    token = jwt.encode({"sub": "nonexistent", "exp": 9999999999}, SECRET_KEY, algorithm=ALGORITHM)

    with pytest.raises(HTTPException) as exc:
        await get_current_user(token=token, db=db_session)
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_active_user_inactive(db_session):
    """Test get_current_active_user with an inactive user."""
    from neurohub.app.services.auth_service import get_current_active_user
    from neurohub.db.models import UserDB

    inactive_user = UserDB(id="1", username="i", email="i@e.com", is_active=False)
    with pytest.raises(HTTPException) as exc:
        await get_current_active_user(current_user=inactive_user)
    assert exc.value.status_code == 400
    assert "Inactive user" in exc.value.detail


def test_viewer_cannot_update_project(auth_client: TestClient) -> None:
    """Test that a viewer cannot update a project they do not administer."""
    with patch("neurohub.app.auth.is_auth_enabled", return_value=False):
        auth_client.post(
            "/api/neurohub/projects",
            json={
                "id": "m-proj",
                "name": "M",
                "description": "D",
                "created_at": "2026-03-16T00:00:00Z",
                "updated_at": "2026-03-16T00:00:00Z",
                "owner": "a",
                "members": [{"user_id": "viewer", "name": "Viewer", "role": "viewer"}],
                "links": {},
                "tags": [],
            },
        )

    response = auth_client.put(
        "/api/neurohub/projects/m-proj",
        headers={"X-API-Key": VIEWER_KEY},
        json={"description": "Viewer attempt"},
    )
    assert response.status_code == 403


def test_viewer_cannot_add_asset(auth_client: TestClient) -> None:
    """Test that a viewer cannot add an asset."""
    response = auth_client.post(
        "/api/neurohub/assets",
        headers={"X-API-Key": VIEWER_KEY},
        json={
            "id": "viewer-asset",
            "name": "A",
            "description": "D",
            "type": "encoding_preset",
            "version": 1,
            "author": "v",
            "tags": [],
            "created_at": "2026-03-16T00:00:00Z",
            "file_path": "/p",
            "file_size_bytes": 0,
            "metadata": {},
        },
    )
    assert response.status_code == 403


# Note: direct tests of /api/neurohub/auth/register|login|refresh were removed
# alongside the retired `app/routers/auth.py` (no remaining caller — the
# Flutter frontend never called it, and it duplicated the registry's own
# /api/v1/auth surface). Registration/login now happens via the Global
# Registry (`registry_auth.py`, `test_registry_auth.py`) or Supabase, per
# `NEUROHUB_AUTH_PROVIDER`.
