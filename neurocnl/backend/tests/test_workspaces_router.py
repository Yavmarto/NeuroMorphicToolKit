"""Tests for the /api/workspaces endpoints."""

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.services.workspace_store import WorkspaceStore, workspace_store

client = TestClient(app)


@pytest.mark.asyncio(loop_scope="function")
async def test_sync_then_get_roundtrip():
    """POSTing a workspace makes it fetchable with the same config."""
    resp = client.post(
        "/api/workspaces/router-test-ws",
        json={
            "name": "Router Test WS",
            "config": {"version": 1, "workspace": {"a": 1}},
        },
    )
    assert resp.status_code == 200
    assert resp.json() == {"slug": "router-test-ws"}

    resp = client.get("/api/workspaces/router-test-ws")
    assert resp.status_code == 200
    data = resp.json()
    assert data["slug"] == "router-test-ws"
    assert data["name"] == "Router Test WS"
    assert data["config"] == {"version": 1, "workspace": {"a": 1}}


@pytest.mark.asyncio(loop_scope="function")
async def test_get_unknown_slug_404():
    """GET for a slug that was never synced returns 404."""
    resp = client.get("/api/workspaces/does-not-exist-router")
    assert resp.status_code == 404


@pytest.mark.asyncio(loop_scope="function")
async def test_list_includes_synced_workspace():
    """A synced workspace shows up in the summary listing."""
    await workspace_store.upsert("router-list-test-ws", "Router List Test", {"a": 1})

    resp = client.get("/api/workspaces")
    assert resp.status_code == 200
    slugs = {item["slug"] for item in resp.json()["items"]}
    assert "router-list-test-ws" in slugs


@pytest.mark.asyncio(loop_scope="function")
async def test_persistence():
    """Workspaces survive 'server restart' (re-initialization of store)."""
    await workspace_store.upsert("router-persist-test-ws", "Persist Test", {"status": "persisted"})

    new_store = WorkspaceStore(db_path=workspace_store.db_path)
    record = await new_store.get("router-persist-test-ws")

    assert record is not None
    assert record["config"] == {"status": "persisted"}
