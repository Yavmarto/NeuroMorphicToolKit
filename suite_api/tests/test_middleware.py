"""Tests for suite_api CORS middleware security defaults."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from suite_api.middleware import attach_middleware


def _make_client(
    monkeypatch: pytest.MonkeyPatch, origins_env: str | None
) -> TestClient:
    """Return a TestClient with middleware under controlled ALLOWED_ORIGINS env."""
    monkeypatch.delenv("ALLOWED_ORIGINS", raising=False)
    monkeypatch.delenv("NMTK_AUTH_REQUIRED", raising=False)
    monkeypatch.delenv("NMTK_ADMIN_TOKEN", raising=False)
    if origins_env is not None:
        monkeypatch.setenv("ALLOWED_ORIGINS", origins_env)

    app = FastAPI()

    @app.get("/probe")
    async def probe() -> dict:
        return {"ok": True}

    @app.get("/api/private")
    async def private_probe() -> dict:
        return {"ok": True}

    @app.get("/api/suite/health")
    async def health() -> dict:
        return {"status": "ok"}

    attach_middleware(app)
    return TestClient(app, raise_server_exceptions=True)


def test_cors_default_does_not_reflect_arbitrary_origin(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """When ALLOWED_ORIGINS is unset the default must NOT echo an external origin."""
    client = _make_client(monkeypatch, origins_env=None)
    response = client.get("/probe", headers={"Origin": "https://attacker.example.com"})
    assert (
        response.status_code == 200
    )  # CORS is a browser contract; server still responds
    allow_origin = response.headers.get("access-control-allow-origin", "")
    assert allow_origin != "https://attacker.example.com", (
        "CORS default must not allow arbitrary origins"
    )
    assert allow_origin != "*", "CORS default must not be wildcard"


def test_cors_wildcard_override_works(monkeypatch: pytest.MonkeyPatch) -> None:
    """Developers can explicitly re-enable open CORS via ALLOWED_ORIGINS=*."""
    client = _make_client(monkeypatch, origins_env="*")
    response = client.get("/probe", headers={"Origin": "https://attacker.example.com"})
    assert response.headers.get("access-control-allow-origin") == "*"


def test_cors_explicit_origin_is_reflected(monkeypatch: pytest.MonkeyPatch) -> None:
    """An explicitly allowed origin is reflected correctly."""
    client = _make_client(monkeypatch, origins_env="https://app.example.com")
    response = client.get("/probe", headers={"Origin": "https://app.example.com"})
    assert (
        response.headers.get("access-control-allow-origin") == "https://app.example.com"
    )


def test_admin_token_protects_api_routes(monkeypatch: pytest.MonkeyPatch) -> None:
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "correct-token")

    unauthorized = client.get("/api/private")
    assert unauthorized.status_code == 401
    detail = unauthorized.json()["detail"]
    assert detail == {
        "code": "unauthorized",
        "message": "Administrator authentication required.",
        "request_id": unauthorized.headers["X-Request-Id"],
        "retryable": False,
    }
    assert client.get("/probe").status_code == 401

    authorized = client.get(
        "/api/private",
        headers={"X-NMTK-Admin-Token": "correct-token"},
    )
    assert authorized.status_code == 200
    assert authorized.json() == {"ok": True}
    assert "nmtk_admin_session=" in authorized.headers["set-cookie"]

    cookie_authenticated = client.get("/api/private")
    assert cookie_authenticated.status_code == 200


def test_admin_auth_accepts_standard_bearer_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = _make_client(monkeypatch, origins_env="https://app.example.com")
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "correct-token")

    authorized = client.get(
        "/api/private",
        headers={"Authorization": "Bearer correct-token"},
    )

    assert authorized.status_code == 200
    assert "nmtk_admin_session=" in authorized.headers["set-cookie"]
    preflight = client.options(
        "/api/private",
        headers={
            "Origin": "https://app.example.com",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    assert "Authorization" in preflight.headers["access-control-allow-headers"]


def test_health_remains_available_without_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "correct-token")

    response = client.get("/api/suite/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
