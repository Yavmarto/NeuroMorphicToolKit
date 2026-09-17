"""Tests for POST /api/datasets/import-local."""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.services.dataset_cache import (
    DatasetCache,
    DatasetDownloadStatus,
    LocalDatasetImportError,
)
from backend.app.services.dataset_catalog import (
    is_importable_dataset_filename,
    reload_dataset_catalog_for_tests,
)


@pytest.fixture
def isolated_cache(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> DatasetCache:
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path))
    reload_dataset_catalog_for_tests()
    return DatasetCache(
        db_path=tmp_path / "datasets.db",
        cache_root=tmp_path / "datasets",
    )


def test_is_importable_dataset_filename_accepts_archives() -> None:
    assert is_importable_dataset_filename("recording.aedat")
    assert is_importable_dataset_filename("shd.h5")
    assert is_importable_dataset_filename("bundle.tar.gz")
    assert not is_importable_dataset_filename("notes.txt")


def test_register_local_dataset_from_bytes(isolated_cache: DatasetCache) -> None:
    async def _run() -> None:
        await isolated_cache.initialize()
        item = await isolated_cache.register_local_dataset(
            filename="main.aedat",
            file_bytes=b"dvs-bytes",
        )
        assert item["status"] == DatasetDownloadStatus.ready.value
        assert item["folder_path"] == "local/"
        assert item["source"] == "local"
        assert Path(item["local_path"]).read_bytes() == b"dvs-bytes"

        entries = await isolated_cache.list_entries()
        local_entries = [entry for entry in entries if entry.get("source") == "local"]
        assert len(local_entries) == 1
        assert local_entries[0]["label"] == "main.aedat"

    asyncio.run(_run())


def test_register_local_dataset_server_path_fast_path(
    isolated_cache: DatasetCache,
    tmp_path: Path,
) -> None:
    async def _run() -> None:
        await isolated_cache.initialize()
        source = tmp_path / "shd.h5"
        source.write_bytes(b"h5-bytes")

        item = await isolated_cache.register_local_dataset(
            filename="shd.h5",
            server_path=str(source),
        )
        assert item["local_path"] == str(source.resolve())
        status = await isolated_cache.get_status(item["id"])
        assert status == DatasetDownloadStatus.ready

    asyncio.run(_run())


def test_register_local_dataset_rejects_unsupported(
    isolated_cache: DatasetCache,
) -> None:
    async def _run() -> None:
        await isolated_cache.initialize()
        with pytest.raises(LocalDatasetImportError, match="Supported formats"):
            await isolated_cache.register_local_dataset(
                filename="notes.txt",
                file_bytes=b"hello",
            )

    asyncio.run(_run())


def test_import_local_multipart_endpoint(
    isolated_cache: DatasetCache,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _init() -> None:
        await isolated_cache.initialize()

    asyncio.run(_init())
    monkeypatch.setattr(
        "backend.app.routers.datasets.dataset_cache",
        isolated_cache,
    )

    client = TestClient(app)
    response = client.post(
        "/api/datasets/import-local",
        files={"file": ("events.aedat", b"event-stream", "application/octet-stream")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ready"
    assert body["source"] == "local"
    assert body["label"] == "events.aedat"


def test_import_local_json_server_path(
    isolated_cache: DatasetCache,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _init() -> None:
        await isolated_cache.initialize()

    asyncio.run(_init())
    source = tmp_path / "nmnist.h5"
    source.write_bytes(b"h5")

    monkeypatch.setattr(
        "backend.app.routers.datasets.dataset_cache",
        isolated_cache,
    )

    client = TestClient(app)
    response = client.post(
        "/api/datasets/import-local",
        json={"server_path": str(source)},
    )
    assert response.status_code == 200
    assert response.json()["local_path"] == str(source.resolve())


def test_import_local_unsupported_extension_returns_422(
    isolated_cache: DatasetCache,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _init() -> None:
        await isolated_cache.initialize()

    asyncio.run(_init())
    monkeypatch.setattr(
        "backend.app.routers.datasets.dataset_cache",
        isolated_cache,
    )

    client = TestClient(app)
    response = client.post(
        "/api/datasets/import-local",
        files={"file": ("notes.txt", b"hello", "text/plain")},
    )
    assert response.status_code == 422
    assert "Supported formats" in response.json()["detail"]
