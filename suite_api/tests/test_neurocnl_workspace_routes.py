from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.services.workspace_store import workspace_store
from suite_api.domains.neurocnl.lifespan import neurocnl_shutdown, neurocnl_startup
from suite_api.domains.neurocnl.router import router


def test_suite_api_initializes_and_serves_neurocnl_workspaces(
    tmp_path, monkeypatch
) -> None:
    monkeypatch.setattr(workspace_store, "db_path", tmp_path / "workspaces.db")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await neurocnl_startup(app)
        try:
            yield
        finally:
            await neurocnl_shutdown()

    app = FastAPI(lifespan=lifespan)
    app.include_router(router)

    with TestClient(app) as client:
        openapi = client.get("/openapi.json")
        assert openapi.status_code == 200
        assert "/api/neurocnl/workspaces/{slug}" in openapi.json()["paths"]

        response = client.post(
            "/api/neurocnl/workspaces/passive-notebook-test",
            json={
                "name": "Passive Notebook Test",
                "config": {"version": 1, "workspace": {"active": "run"}},
            },
        )
        assert response.status_code == 200

        response = client.get("/api/neurocnl/workspaces/passive-notebook-test")
        assert response.status_code == 200
        assert response.json()["config"]["workspace"]["active"] == "run"
