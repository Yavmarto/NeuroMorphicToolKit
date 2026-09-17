"""Tests for suite_api CORS middleware security defaults."""

from typing import Any

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import suite_api.middleware as middleware
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
    async def probe() -> dict[str, bool]:
        return {"ok": True}

    @app.get("/api/private")
    async def private_probe() -> dict[str, bool]:
        return {"ok": True}

    @app.get("/api/suite/health")
    async def health() -> dict[str, str]:
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


def _patch_introspect_client(
    monkeypatch: pytest.MonkeyPatch,
    status_code: int,
) -> dict[str, str]:
    """Return a dict that records introspect URL and Authorization header."""
    seen: dict[str, str] = {}

    class FakeClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "FakeClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            seen["url"] = url
            seen.update(headers or {})
            return httpx.Response(status_code)

    monkeypatch.setattr(middleware.httpx, "AsyncClient", FakeClient)
    return seen


def test_connect_session_bearer_accepted_when_introspect_ok(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Connect-session bearer passes when launcher-control introspect is 200."""
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "static-admin-token")
    monkeypatch.setenv("NMTK_LAUNCHER_CONTROL_URL", "http://launcher-control:8091")
    seen = _patch_introspect_client(monkeypatch, status_code=200)

    response = client.get(
        "/api/private",
        headers={"Authorization": "Bearer connect-session-token"},
    )

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert seen["url"] == "http://launcher-control:8091/api/launcher/auth/introspect"
    assert seen["Authorization"] == "Bearer connect-session-token"
    assert "nmtk_admin_session=" not in response.headers.get("set-cookie", "")


def test_connect_session_bearer_rejected_when_introspect_unauthorized(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Connect-session bearer fails when launcher-control introspect is 401."""
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "static-admin-token")
    monkeypatch.setenv("NMTK_LAUNCHER_CONTROL_URL", "http://launcher-control:8091")
    seen = _patch_introspect_client(monkeypatch, status_code=401)

    response = client.get(
        "/api/private",
        headers={"Authorization": "Bearer stale-session-token"},
    )

    assert response.status_code == 401
    detail = response.json()["detail"]
    assert detail["code"] == "unauthorized"
    assert seen["url"] == "http://launcher-control:8091/api/launcher/auth/introspect"
    assert seen["Authorization"] == "Bearer stale-session-token"


def test_session_token_introspect_is_cached_for_repeated_requests(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Repeated bearer checks must not hammer launcher-control on every request."""
    middleware.clear_session_token_cache()
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "static-admin-token")
    monkeypatch.setenv("NMTK_LAUNCHER_CONTROL_URL", "http://launcher-control:8091")
    monkeypatch.setenv("NMTK_SESSION_TOKEN_CACHE_TTL_S", "30")
    call_count = 0

    class CountingClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "CountingClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            nonlocal call_count
            call_count += 1
            return httpx.Response(401)

    monkeypatch.setattr(middleware.httpx, "AsyncClient", CountingClient)

    for _ in range(5):
        response = client.get(
            "/api/private",
            headers={"Authorization": "Bearer garbage-token"},
        )
        assert response.status_code == 401

    assert call_count == 1


def test_session_token_cache_expires_and_reintrospects(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Cached invalid tokens must be re-checked after the TTL elapses."""
    middleware.clear_session_token_cache()
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "static-admin-token")
    monkeypatch.setenv("NMTK_LAUNCHER_CONTROL_URL", "http://launcher-control:8091")
    monkeypatch.setattr(middleware, "_SESSION_TOKEN_CACHE_TTL_S", 0.05)
    call_count = 0

    class CountingClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "CountingClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            nonlocal call_count
            call_count += 1
            return httpx.Response(401)

    monkeypatch.setattr(middleware.httpx, "AsyncClient", CountingClient)

    assert client.get(
        "/api/private",
        headers={"Authorization": "Bearer garbage-token"},
    ).status_code == 401
    assert call_count == 1

    import time

    time.sleep(0.06)

    assert client.get(
        "/api/private",
        headers={"Authorization": "Bearer garbage-token"},
    ).status_code == 401
    assert call_count == 2


def test_session_token_introspect_transport_error_not_negative_cached(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Transport failures are not cached; each request retries introspect."""
    middleware.clear_session_token_cache()
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "static-admin-token")
    monkeypatch.setenv("NMTK_LAUNCHER_CONTROL_URL", "http://launcher-control:8091")
    call_count = 0

    class FlakyClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "FlakyClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            nonlocal call_count
            call_count += 1
            raise httpx.ConnectError("launcher-control unreachable")

    monkeypatch.setattr(middleware.httpx, "AsyncClient", FlakyClient)

    for _ in range(3):
        response = client.get(
            "/api/private",
            headers={"Authorization": "Bearer live-session-token"},
        )
        assert response.status_code == 401

    assert call_count == 3


def test_session_token_introspect_recovery_after_transport_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Valid bearer must succeed on the next request when introspect recovers."""
    middleware.clear_session_token_cache()
    client = _make_client(monkeypatch, origins_env=None)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "static-admin-token")
    monkeypatch.setenv("NMTK_LAUNCHER_CONTROL_URL", "http://launcher-control:8091")
    call_count = 0

    class RecoveringClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "RecoveringClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise httpx.ConnectError("launcher-control unreachable")
            return httpx.Response(200)

    monkeypatch.setattr(middleware.httpx, "AsyncClient", RecoveringClient)

    denied = client.get(
        "/api/private",
        headers={"Authorization": "Bearer live-session-token"},
    )
    assert denied.status_code == 401
    assert call_count == 1

    allowed = client.get(
        "/api/private",
        headers={"Authorization": "Bearer live-session-token"},
    )
    assert allowed.status_code == 200
    assert allowed.json() == {"ok": True}
    assert call_count == 2
