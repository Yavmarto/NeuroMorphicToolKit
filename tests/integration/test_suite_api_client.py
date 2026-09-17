from __future__ import annotations

import httpx
import pytest

from .suite_api_client import request_suite_api


@pytest.mark.asyncio
async def test_request_suite_api_adds_app_provisioned_token(monkeypatch):
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "test-token")

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["X-NMTK-Admin-Token"] == "test-token"
        return httpx.Response(200, json={"status": "ok"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        response = await request_suite_api(
            client, "GET", "http://suite/api/suite/health"
        )

    assert response.status_code == 200


@pytest.mark.asyncio
async def test_request_suite_api_rejects_wrong_local_service(monkeypatch):
    monkeypatch.delenv("NMTK_ADMIN_TOKEN", raising=False)
    monkeypatch.delenv("NMTK_ADMIN_TOKEN_FILE", raising=False)
    transport = httpx.MockTransport(
        lambda request: httpx.Response(403, headers={"server": "MinIO"})
    )

    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(pytest.fail.Exception, match="points to MinIO"):
            await request_suite_api(
                client, "GET", "http://localhost:9000/api/suite/health"
            )


@pytest.mark.asyncio
async def test_request_suite_api_explains_missing_authentication(monkeypatch):
    monkeypatch.delenv("NMTK_ADMIN_TOKEN", raising=False)
    monkeypatch.delenv("NMTK_ADMIN_TOKEN_FILE", raising=False)
    transport = httpx.MockTransport(lambda request: httpx.Response(401))

    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(pytest.fail.Exception, match="administrator authentication"):
            await request_suite_api(client, "POST", "http://suite/api/neurocnl/parse")
