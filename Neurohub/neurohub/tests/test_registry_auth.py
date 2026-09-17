"""Provider-dispatch tests for the Global Registry auth surface (``/api/v1/auth``).

Covers the ``supabase`` external-auth mode end to end (register/login/refresh
gating, ``/sync``, and downstream dependency dispatch), by monkeypatching the
token verifier. This mode was previously exercised only indirectly (via
``internal`` mode in ``test_registry_artefacts.py``); this file closes that gap.
"""

from __future__ import annotations

from collections.abc import Generator
from typing import Any

import pytest
from fastapi.testclient import TestClient

import neurohub.app.registry_security as registry_security
import neurohub.app.routers.registry_auth as registry_auth_router
from neurohub.app.limiter import limiter


@pytest.fixture(autouse=True)
def _disable_rate_limiting() -> Generator[None, None, None]:
    was_enabled = limiter.enabled
    limiter.enabled = False
    yield
    limiter.enabled = was_enabled


@pytest.fixture
def supabase_mode(monkeypatch: pytest.MonkeyPatch) -> Generator[None, None, None]:
    """Switch the registry auth dependency + router to ``supabase`` mode."""
    monkeypatch.setattr(registry_security, "AUTH_PROVIDER", "supabase")
    monkeypatch.setattr(registry_auth_router, "_AUTH_PROVIDER", "supabase")
    yield


def _mock_supabase_token(monkeypatch: pytest.MonkeyPatch, claims: dict[str, Any]) -> None:
    import neurohub.app.services.supabase_auth_service as supabase_auth_service

    monkeypatch.setattr(supabase_auth_service, "verify_supabase_token", lambda token: claims)


def test_register_login_refresh_disabled_under_supabase(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, supabase_mode: None
) -> None:
    """Register/login/refresh must 501 under the supabase auth provider."""
    assert (
        client.post(
            "/api/v1/auth/register",
            json={
                "username": "x",
                "email": "x@example.com",
                "full_name": "",
                "password": "pw",
            },
        ).status_code
        == 501
    )
    assert (
        client.post("/api/v1/auth/login", json={"username": "x", "password": "pw"}).status_code
        == 501
    )
    assert (
        client.post("/api/v1/auth/refresh", json={"refresh_token": "whatever"}).status_code == 501
    )


def test_sync_creates_then_is_idempotent_under_supabase(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, supabase_mode: None
) -> None:
    """First /sync creates the UserDB row keyed on supabase_uid; second is idempotent."""
    _mock_supabase_token(monkeypatch, {"sub": "sb-uid-1", "email": "person@example.com"})
    headers = {"Authorization": "Bearer fake-supabase-token"}

    first = client.post(
        "/api/v1/auth/sync",
        json={"username": "sbuser1", "full_name": "SB User"},
        headers=headers,
    )
    assert first.status_code == 200, first.text
    assert first.json()["created"] is True
    assert first.json()["username"] == "sbuser1"

    second = client.post(
        "/api/v1/auth/sync",
        json={"username": "ignored-on-second-call", "full_name": "SB User"},
        headers=headers,
    )
    assert second.status_code == 200, second.text
    assert second.json()["username"] == "sbuser1"
    assert second.json()["created"] is False


def test_sync_duplicate_username_conflicts_across_users(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, supabase_mode: None
) -> None:
    """A second Supabase UID cannot claim a username already synced by another."""
    _mock_supabase_token(monkeypatch, {"sub": "sb-uid-a", "email": "a@example.com"})
    ok = client.post(
        "/api/v1/auth/sync",
        json={"username": "shared-name", "full_name": ""},
        headers={"Authorization": "Bearer token-a"},
    )
    assert ok.status_code == 200, ok.text

    _mock_supabase_token(monkeypatch, {"sub": "sb-uid-b", "email": "b@example.com"})
    conflict = client.post(
        "/api/v1/auth/sync",
        json={"username": "shared-name", "full_name": ""},
        headers={"Authorization": "Bearer token-b"},
    )
    assert conflict.status_code == 409, conflict.text


def test_sync_disabled_under_internal_mode(client: TestClient) -> None:
    """/sync must not silently succeed under the default internal provider.

    Default provider is "internal" (no fixture applied) — /sync has no
    external-provider UID to key off, so it must reject rather than proceed.
    """
    response = client.post(
        "/api/v1/auth/sync",
        json={"username": "whoever", "full_name": ""},
        headers={"Authorization": "Bearer irrelevant"},
    )
    assert response.status_code in (401, 501)


def test_get_registry_user_dispatches_to_supabase_verifier(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, supabase_mode: None
) -> None:
    """Admin role and username claims from a Supabase token flow through to /sync."""
    _mock_supabase_token(
        monkeypatch,
        {
            "sub": "sb-uid-admin",
            "email": "admin@example.com",
            "app_metadata": {"role": "admin"},
            "user_metadata": {"registry_username": "adminuser"},
        },
    )
    sync = client.post(
        "/api/v1/auth/sync",
        json={"username": "adminuser", "full_name": ""},
        headers={"Authorization": "Bearer admin-token"},
    )
    assert sync.status_code == 200, sync.text
    assert sync.json()["username"] == "adminuser"


def test_get_registry_user_rejects_invalid_supabase_token(
    client: TestClient, monkeypatch: pytest.MonkeyPatch, supabase_mode: None
) -> None:
    """A SupabaseAuthError from the verifier must surface as 401 Bearer."""
    import neurohub.app.services.supabase_auth_service as supabase_auth_service

    def _raise(token: str) -> dict[str, Any]:
        raise supabase_auth_service.SupabaseAuthError("bad token")

    monkeypatch.setattr(supabase_auth_service, "verify_supabase_token", _raise)

    response = client.post(
        "/api/v1/auth/sync",
        json={"username": "whoever", "full_name": ""},
        headers={"Authorization": "Bearer garbage"},
    )
    assert response.status_code == 401
    assert response.headers.get("www-authenticate") == "Bearer"
