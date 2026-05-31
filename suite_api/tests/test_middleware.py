"""Tests for suite_api CORS middleware security defaults."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from suite_api.middleware import attach_middleware


def _make_client(monkeypatch: pytest.MonkeyPatch, origins_env: str | None) -> TestClient:
    """Return a TestClient with middleware attached under a controlled ALLOWED_ORIGINS env."""
    monkeypatch.delenv("ALLOWED_ORIGINS", raising=False)
    if origins_env is not None:
        monkeypatch.setenv("ALLOWED_ORIGINS", origins_env)

    app = FastAPI()

    @app.get("/probe")
    async def probe() -> dict:
        return {"ok": True}

    attach_middleware(app)
    return TestClient(app, raise_server_exceptions=True)


def test_cors_default_does_not_reflect_arbitrary_origin(monkeypatch: pytest.MonkeyPatch) -> None:
    """When ALLOWED_ORIGINS is unset the default must NOT echo back a random external origin."""
    client = _make_client(monkeypatch, origins_env=None)
    response = client.get("/probe", headers={"Origin": "https://attacker.example.com"})
    assert response.status_code == 200  # CORS is a browser contract; server still responds
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
    assert response.headers.get("access-control-allow-origin") == "https://app.example.com"
