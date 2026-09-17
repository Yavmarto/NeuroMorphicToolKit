"""Contract tests for the private-worker proxy boundary."""

from __future__ import annotations

import httpx
import pytest
from fastapi import FastAPI, Request, Response
from fastapi.testclient import TestClient

from suite_api.middleware import attach_middleware
from suite_api.proxy import proxy_to_worker


def _client() -> TestClient:
    app = FastAPI()
    attach_middleware(app)

    @app.get("/proxy")
    async def proxy(request: Request) -> Response:
        return await proxy_to_worker(request, "http://private-worker:8123")

    return TestClient(app)


def test_unavailable_worker_returns_safe_correlated_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fail_request(*_args: object, **_kwargs: object) -> httpx.Response:
        raise httpx.ConnectError("secret internal address")

    monkeypatch.setattr(httpx.AsyncClient, "request", fail_request)
    response = _client().get("/proxy", headers={"X-Request-ID": "trace-123"})

    assert response.status_code == 503
    assert response.json() == {
        "detail": {
            "code": "worker_unavailable",
            "message": "The requested service is temporarily unavailable.",
            "request_id": "trace-123",
            "retryable": True,
        }
    }
    assert "private-worker" not in response.text


def test_proxy_forwards_generated_request_id(monkeypatch: pytest.MonkeyPatch) -> None:
    observed_headers: dict[str, str] = {}

    async def successful_request(*_args: object, **kwargs: object) -> httpx.Response:
        headers = kwargs["headers"]
        assert isinstance(headers, dict)
        observed_headers.update(headers)
        return httpx.Response(200, json={"ok": True})

    monkeypatch.setattr(httpx.AsyncClient, "request", successful_request)
    response = _client().get("/proxy")

    assert response.status_code == 200
    assert observed_headers["X-Request-ID"] == response.headers["X-Request-Id"]
