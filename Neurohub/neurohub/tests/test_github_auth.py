"""Tests for GitHub OAuth Device Flow discovery, start/poll, and preflight."""

from __future__ import annotations

import httpx
import pytest
from fastapi.testclient import TestClient

from neurohub.app.routers import github_auth


def test_oauth_config_requires_operator_configuration(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Missing provider settings produce an actionable setup error."""
    monkeypatch.delenv("GITHUB_OAUTH_CLIENT_ID", raising=False)
    response = client.get("/api/neurohub/oauth/config")
    assert response.status_code == 503
    assert "GITHUB_OAUTH_CLIENT_ID" in response.json()["detail"]


def test_oauth_config_exposes_device_flow_without_secret(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Clients receive only the values safe for Device Flow — no secret, no redirect URI."""
    monkeypatch.setenv("GITHUB_OAUTH_CLIENT_ID", "public-client")
    response = client.get("/api/neurohub/oauth/config")
    assert response.status_code == 200
    body = response.json()
    assert body["client_id"] == "public-client"
    assert body["scopes"] == ["repo", "read:user"]
    assert "client_secret" not in body
    assert "redirect_uri" not in body


def test_device_start_returns_user_code_and_keeps_device_code_server_side(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The client only ever sees the user-facing code, never the device_code."""
    monkeypatch.setenv("GITHUB_OAUTH_CLIENT_ID", "public-client")
    github_auth._pending_sessions.clear()

    def fake_post(
        url: str, *, data: dict[str, str], headers: dict[str, str], timeout: float
    ) -> httpx.Response:
        del headers, timeout
        assert url == github_auth._DEVICE_AUTHORIZATION_URL
        assert data["client_id"] == "public-client"
        return httpx.Response(
            200,
            json={
                "device_code": "server-only-secret",
                "user_code": "ABCD-1234",
                "verification_uri": "https://github.com/login/device",
                "expires_in": 900,
                "interval": 5,
            },
        )

    monkeypatch.setattr(github_auth.httpx, "post", fake_post)
    response = client.post("/api/neurohub/oauth/device/start")
    assert response.status_code == 200
    body = response.json()
    assert body["user_code"] == "ABCD-1234"
    assert body["verification_uri"] == "https://github.com/login/device"
    assert "device_code" not in body
    session_id = body["session_id"]
    assert github_auth._pending_sessions[session_id].device_code == "server-only-secret"


def test_device_poll_maps_pending_success_and_denied(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Each GitHub device-flow error maps to a stable client-facing status."""
    monkeypatch.setenv("GITHUB_OAUTH_CLIENT_ID", "public-client")
    github_auth._pending_sessions.clear()
    github_auth._pending_sessions["sess-1"] = github_auth._PendingDevice(
        device_code="dc-1", interval=5, expires_at=github_auth.time.time() + 900
    )

    def pending(
        url: str, *, data: dict[str, str], headers: dict[str, str], timeout: float
    ) -> httpx.Response:
        del url, data, headers, timeout
        return httpx.Response(200, json={"error": "authorization_pending"})

    monkeypatch.setattr(github_auth.httpx, "post", pending)
    response = client.post("/api/neurohub/oauth/device/poll", json={"session_id": "sess-1"})
    assert response.json()["status"] == "pending"

    def denied(
        url: str, *, data: dict[str, str], headers: dict[str, str], timeout: float
    ) -> httpx.Response:
        del url, data, headers, timeout
        return httpx.Response(200, json={"error": "access_denied"})

    monkeypatch.setattr(github_auth.httpx, "post", denied)
    response = client.post("/api/neurohub/oauth/device/poll", json={"session_id": "sess-1"})
    assert response.json()["status"] == "denied"
    assert "sess-1" not in github_auth._pending_sessions


def test_device_poll_unknown_session_is_expired(client: TestClient) -> None:
    """A session that was never started or already completed is reported expired."""
    response = client.post("/api/neurohub/oauth/device/poll", json={"session_id": "never-existed"})
    assert response.json()["status"] == "expired"


def test_health_reports_degraded_when_github_unreachable(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Transport failures are reported as a stable degraded status, not a 500."""

    def unavailable(url: str, timeout: float) -> httpx.Response:
        del url, timeout
        raise httpx.ConnectError("offline")

    monkeypatch.setattr(github_auth.httpx, "get", unavailable)
    response = client.get("/api/neurohub/oauth/health")
    assert response.status_code == 200
    assert response.json()["status"] == "degraded"
