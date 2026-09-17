"""Tests for WorkspaceStore service."""

import pytest
import pytest_asyncio

from backend.app.services.workspace_store import WorkspaceStore


@pytest_asyncio.fixture
async def store(tmp_path):
    """Fixture to provide a WorkspaceStore with an isolated database."""
    db_path = tmp_path / "test_workspaces.db"
    store = WorkspaceStore(db_path=db_path)
    await store.initialize()
    return store


@pytest.mark.asyncio
async def test_upsert_and_get(store):
    """A saved workspace is retrievable with its full config."""
    await store.upsert("my-ws", "My WS", {"version": 1, "workspace": {"a": 1}})

    record = await store.get("my-ws")
    assert record["slug"] == "my-ws"
    assert record["name"] == "My WS"
    assert record["config"] == {"version": 1, "workspace": {"a": 1}}


@pytest.mark.asyncio
async def test_get_nonexistent_returns_none(store):
    """Fetching an unknown slug returns None rather than raising."""
    assert await store.get("does-not-exist") is None


@pytest.mark.asyncio
async def test_upsert_replaces_existing(store):
    """A second upsert for the same slug overwrites name and config."""
    await store.upsert("my-ws", "My WS", {"workspace": {"a": 1}})
    await store.upsert("my-ws", "My WS Renamed", {"workspace": {"a": 2}})

    record = await store.get("my-ws")
    assert record["name"] == "My WS Renamed"
    assert record["config"] == {"workspace": {"a": 2}}


@pytest.mark.asyncio
async def test_list_summaries_excludes_config(store):
    """The summary listing omits the (possibly large) config blob."""
    await store.upsert("ws-a", "Workspace A", {"workspace": {"big": "blob"}})
    await store.upsert("ws-b", "Workspace B", {"workspace": {}})

    summaries = await store.list_summaries()
    slugs = {s["slug"] for s in summaries}
    assert slugs == {"ws-a", "ws-b"}
    assert all("config" not in s for s in summaries)


@pytest.mark.asyncio
async def test_list_summaries_sorted_by_updated_at_descending(store):
    """The summary listing is ordered most-recently-updated first."""
    await store.upsert("ws-a", "Workspace A", {})
    await store.upsert("ws-b", "Workspace B", {})

    summaries = await store.list_summaries()
    timestamps = [s["updated_at"] for s in summaries]
    assert timestamps == sorted(timestamps, reverse=True)
