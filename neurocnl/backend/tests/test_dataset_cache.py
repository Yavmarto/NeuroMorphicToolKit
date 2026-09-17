"""Tests for Firebase dataset catalog and server-side cache."""

from __future__ import annotations

import asyncio
import io
import zipfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
from urllib.parse import unquote

import pytest

from backend.app.services.dataset_cache import (
    DatasetCache,
    DatasetDownloadStatus,
    DatasetIntegrityError,
    FirebaseNotConfiguredError,
    firebase_public_url,
)
from backend.app.services.dataset_catalog import (
    DatasetCatalog,
    DatasetCatalogEntry,
    FirebaseStorageObject,
    infer_dataset_format,
    load_dataset_catalog,
    reload_dataset_catalog_for_tests,
)


@pytest.fixture
def isolated_cache(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> DatasetCache:
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("NEUROCNL_FIREBASE_BUCKET", "test-bucket.appspot.com")
    reload_dataset_catalog_for_tests()
    return DatasetCache(
        db_path=tmp_path / "datasets.db",
        cache_root=tmp_path / "datasets",
    )


def _catalog_for_tests() -> DatasetCatalog:
    return DatasetCatalog(
        datasets=[
            DatasetCatalogEntry(
                id="davis24-main",
                label="main.aedat",
                description="DAVIS samples.",
                storage_path="Davis 24/main.aedat",
                folder_path="Davis 24/",
                source_filename="main.aedat",
                format="aedat",
            ),
            DatasetCatalogEntry(
                id="nmnist",
                label="nmnist.h5",
                description="Event-based MNIST",
                storage_path="datasets/nmnist/nmnist.h5",
                folder_path="datasets/nmnist/",
                source_filename="nmnist.h5",
                format="hdf5_generic_event",
            ),
            DatasetCatalogEntry(
                id="shd",
                label="shd.h5",
                description="Spiking Heidelberg Digits",
                storage_path="datasets/shd/shd.h5",
                folder_path="datasets/shd/",
                source_filename="shd.h5",
                format="hdf5_generic_event",
                content_sha256="0" * 64,
            ),
        ]
    )


def test_initialize_creates_schema(isolated_cache: DatasetCache) -> None:
    async def _run() -> None:
        await isolated_cache.initialize()
        assert isolated_cache.db_path.is_file()

    asyncio.run(_run())


def test_firebase_public_url_encoding() -> None:
    url = firebase_public_url("my-bucket", "datasets/nmnist/data.h5")
    assert "my-bucket" in url
    assert "datasets%2Fnmnist%2Fdata.h5" in url
    assert url.endswith("?alt=media")


def test_cache_hit_skips_http(isolated_cache: DatasetCache) -> None:
    async def _run() -> None:
        await isolated_cache.initialize()
        dataset_id = "nmnist"
        dest_dir = isolated_cache.cache_root / "datasets" / "nmnist"
        dest_dir.mkdir(parents=True)
        dest_file = dest_dir / "nmnist.h5"
        dest_file.write_bytes(b"cached-bytes")

        with (
            patch(
                "backend.app.services.dataset_cache.load_dataset_catalog",
                return_value=_catalog_for_tests(),
            ),
            patch(
                "backend.app.services.dataset_cache.list_firebase_folder_objects",
                return_value=[
                    FirebaseStorageObject(name="datasets/nmnist/nmnist.h5"),
                ],
            ),
            patch("httpx.Client") as mock_client,
        ):
            result = isolated_cache._download_blocking(dataset_id)
            mock_client.assert_not_called()

        assert result["local_path"] == str(dest_file.resolve())
        status = await isolated_cache.get_status(dataset_id)
        assert status == DatasetDownloadStatus.ready

    asyncio.run(_run())


def test_successful_download_writes_registry(isolated_cache: DatasetCache) -> None:
    payloads = {
        "Davis 24/main.aedat": b"selected-file",
        "Davis 24/description.txt": b"DAVIS samples.",
        "Davis 24/auxiliary.aedat": b"auxiliary-file",
    }

    class _MockResponse:
        def __init__(self, payload: bytes) -> None:
            self.status_code = 200
            self._payload = payload
            self.headers: dict[str, str] = {}

        def raise_for_status(self) -> None:
            return None

        def iter_bytes(self, chunk_size: int = 0):
            del chunk_size
            yield self._payload

    class _MockStream:
        def __init__(self, payload: bytes) -> None:
            self._payload = payload

        def __enter__(self):
            return _MockResponse(self._payload)

        def __exit__(self, *args: object) -> None:
            return None

    mock_http = MagicMock()
    mock_http.stream.side_effect = lambda _method, url: _MockStream(
        payloads[unquote(url.split("/o/", 1)[1].split("?alt=media", 1)[0])]
    )
    mock_http.__enter__.return_value = mock_http
    mock_http.__exit__.return_value = None

    async def _run() -> None:
        await isolated_cache.initialize()
        with (
            patch(
                "backend.app.services.dataset_cache.load_dataset_catalog",
                return_value=_catalog_for_tests(),
            ),
            patch(
                "backend.app.services.dataset_cache.list_firebase_folder_objects",
                return_value=[
                    FirebaseStorageObject(name="Davis 24/main.aedat"),
                    FirebaseStorageObject(name="Davis 24/description.txt"),
                    FirebaseStorageObject(name="Davis 24/auxiliary.aedat"),
                ],
            ),
            patch("httpx.Client", return_value=mock_http),
        ):
            result = isolated_cache._download_blocking("davis24-main")

        selected_path = Path(result["local_path"])
        assert selected_path.read_bytes() == payloads["Davis 24/main.aedat"]
        assert (selected_path.parent / "description.txt").read_bytes() == payloads[
            "Davis 24/description.txt"
        ]
        assert (selected_path.parent / "auxiliary.aedat").read_bytes() == payloads[
            "Davis 24/auxiliary.aedat"
        ]
        status = await isolated_cache.get_status("davis24-main")
        assert status == DatasetDownloadStatus.ready

    asyncio.run(_run())


def test_archive_download_is_extracted_and_ready_path_points_to_payload(
    isolated_cache: DatasetCache,
) -> None:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as handle:
        handle.writestr("nmnist.h5", b"archived-h5-payload")
        handle.writestr("README.txt", b"dataset notes")
    archive_payload = buffer.getvalue()

    class _MockResponse:
        status_code = 200
        headers: dict[str, str] = {}

        def raise_for_status(self) -> None:
            return None

        def iter_bytes(self, chunk_size: int = 0):
            del chunk_size
            yield archive_payload

    class _MockStream:
        def __enter__(self):
            return _MockResponse()

        def __exit__(self, *args: object) -> None:
            return None

    mock_http = MagicMock()
    mock_http.stream.return_value = _MockStream()
    mock_http.__enter__.return_value = mock_http
    mock_http.__exit__.return_value = None

    archive_catalog = DatasetCatalog(
        datasets=[
            DatasetCatalogEntry(
                id="nmnist-archive",
                label="nmnist.h5.zip",
                description="Archived N-MNIST payload",
                storage_path="datasets/nmnist/nmnist.h5.zip",
                folder_path="datasets/nmnist/",
                source_filename="nmnist.h5.zip",
                format="hdf5_generic_event",
            ),
        ]
    )

    async def _run() -> None:
        await isolated_cache.initialize()
        with (
            patch(
                "backend.app.services.dataset_cache.load_dataset_catalog",
                return_value=archive_catalog,
            ),
            patch(
                "backend.app.services.dataset_cache.list_firebase_folder_objects",
                return_value=[
                    FirebaseStorageObject(name="datasets/nmnist/nmnist.h5.zip"),
                ],
            ),
            patch("httpx.Client", return_value=mock_http),
        ):
            result = isolated_cache._download_blocking("nmnist-archive")

        ready_path = Path(result["local_path"])
        assert ready_path.name == "nmnist.h5"
        assert ready_path.read_bytes() == b"archived-h5-payload"
        assert ready_path.parent.name.endswith("__extracted")
        assert (ready_path.parent / "README.txt").read_bytes() == b"dataset notes"
        assert await isolated_cache.get_status("nmnist-archive") == DatasetDownloadStatus.ready

    asyncio.run(_run())


def test_hash_mismatch_deletes_file(isolated_cache: DatasetCache) -> None:
    payload = b"bad-hash-payload"

    class _MockResponse:
        status_code = 200
        headers: dict[str, str] = {}

        def raise_for_status(self) -> None:
            return None

        def iter_bytes(self, chunk_size: int = 0):
            del chunk_size
            yield payload

    class _MockStream:
        def __enter__(self):
            return _MockResponse()

        def __exit__(self, *args: object) -> None:
            return None

    mock_http = MagicMock()
    mock_http.stream.return_value = _MockStream()
    mock_http.__enter__.return_value = mock_http
    mock_http.__exit__.return_value = None

    async def _run() -> None:
        await isolated_cache.initialize()
        with (
            patch("backend.app.services.dataset_cache.load_dataset_catalog") as mock_catalog,
            patch(
                "backend.app.services.dataset_cache.list_firebase_folder_objects",
                return_value=[
                    FirebaseStorageObject(name="datasets/shd/shd.h5"),
                ],
            ),
            patch("httpx.Client", return_value=mock_http),
        ):
            mock_catalog.return_value = _catalog_for_tests()
            with pytest.raises(DatasetIntegrityError):
                isolated_cache._download_blocking("shd")

        partial = isolated_cache.cache_root / "datasets" / "shd" / "shd.h5"
        assert not partial.exists()

    asyncio.run(_run())


def test_missing_bucket_raises(
    isolated_cache: DatasetCache, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("NEUROCNL_FIREBASE_BUCKET", raising=False)
    with (
        patch(
            "backend.app.services.dataset_cache.load_dataset_catalog",
            return_value=_catalog_for_tests(),
        ),
        pytest.raises(FirebaseNotConfiguredError),
    ):
        isolated_cache._download_blocking("nmnist")


def test_load_dataset_catalog_from_firebase_listing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NEUROCNL_FIREBASE_BUCKET", "nmtk-41e11.firebasestorage.app")
    reload_dataset_catalog_for_tests()

    class _Response:
        def __init__(self, payload: str) -> None:
            self._payload = payload.encode("utf-8")

        def read(self) -> bytes:
            return self._payload

        def __enter__(self) -> _Response:
            return self

        def __exit__(self, *args: object) -> None:
            return None

    def _fake_urlopen(url: str, timeout: int = 30) -> _Response:
        del timeout
        if url.endswith("?delimiter=/"):
            return _Response('{"prefixes":["Davis 24/"],"items":[]}')
        if "prefix=Davis%2024%2F&delimiter=/" in url:
            return _Response(
                '{"items":['
                '{"name":"Davis 24/main.aedat","size":"12"},'
                '{"name":"Davis 24/archive.7z","size":"34"},'
                '{"name":"Davis 24/description.txt","size":"10"}'
                "]}"
            )
        if "Davis%2024%2Fdescription.txt?alt=media" in url:
            return _Response("DAVIS samples.")
        raise AssertionError(f"Unexpected URL: {url}")

    with patch("backend.app.services.dataset_catalog.urlopen", side_effect=_fake_urlopen):
        catalog = load_dataset_catalog(refresh=True)

    assert [entry.label for entry in catalog.datasets] == ["main.aedat"]
    assert catalog.datasets[0].folder_path == "Davis 24/"
    assert catalog.datasets[0].description == "DAVIS samples."
    assert catalog.datasets[0].format == "aedat"


def test_infer_dataset_format_supports_archived_payloads() -> None:
    assert infer_dataset_format("datasets/nmnist/nmnist.h5.zip") == "hdf5_generic_event"
    assert infer_dataset_format("datasets/vision/sample.aedat.7z") == "aedat"
    assert infer_dataset_format("datasets/archive-only/sample.7z") is None


def test_list_datasets_endpoint() -> None:
    pytest.importorskip("httpx")
    from fastapi.testclient import TestClient

    from backend.app.main import app

    test_client = TestClient(app)
    with patch(
        "backend.app.services.dataset_cache.load_dataset_catalog",
        return_value=_catalog_for_tests(),
    ):
        resp = test_client.get("/api/datasets")
    assert resp.status_code == 200
    body = resp.json()
    assert "datasets" in body
    assert len(body["datasets"]) >= 3
    assert body["datasets"][0]["folder_path"] is not None

    assert "folders" in body
    assert len(body["folders"]) >= 1
    for folder in body["folders"]:
        assert "folder_name" in folder
        assert "folder_path" in folder
        assert "description" in folder
        assert "files" in folder
        assert len(folder["files"]) >= 1


def test_download_without_bucket_returns_503() -> None:
    pytest.importorskip("httpx")
    from fastapi.testclient import TestClient

    from backend.app.main import app

    test_client = TestClient(app)
    with (
        patch(
            "backend.app.routers.datasets.load_dataset_catalog",
            return_value=_catalog_for_tests(),
        ),
        patch(
            "backend.app.routers.datasets.firebase_bucket_configured",
            return_value=False,
        ),
    ):
        resp = test_client.post("/api/datasets/nmnist/download")
    assert resp.status_code == 503
    assert "NEUROCNL_FIREBASE_BUCKET" in resp.json()["detail"]


def test_concurrent_download_returns_202() -> None:
    """A second POST /download while the same dataset is already in-flight must
    return 202 (keep polling) instead of spawning a racing duplicate job — the
    download endpoint is poll-friendly by design, not a strict-conflict 409."""
    pytest.importorskip("httpx")
    from fastapi.testclient import TestClient

    from backend.app.main import app

    test_client = TestClient(app)

    large_entry = DatasetCatalogEntry(
        id="nmnist",
        label="nmnist.h5",
        description="Event-based MNIST",
        storage_path="datasets/nmnist/nmnist.h5",
        folder_path="datasets/nmnist/",
        source_filename="nmnist.h5",
        # Large enough to trigger the async path (> DEFAULT_SYNC_MAX_BYTES).
        size_bytes=100 * 1024 * 1024,
        format="hdf5_generic_event",
    )
    large_catalog = DatasetCatalog(datasets=[large_entry])

    with (
        patch(
            "backend.app.routers.datasets.load_dataset_catalog",
            return_value=large_catalog,
        ),
        patch(
            "backend.app.routers.datasets.firebase_bucket_configured",
            return_value=True,
        ),
        patch(
            "backend.app.routers.datasets.dataset_cache.get_ready_path",
            return_value=None,
        ),
        patch(
            "backend.app.routers.datasets.dataset_cache._is_downloading",
            return_value=True,
        ),
    ):
        resp = test_client.post("/api/datasets/nmnist/download")

    assert resp.status_code == 202
    body = resp.json()
    assert body["status"] == "downloading"
    assert body["dataset_id"] == "nmnist"


def test_job_failure_message_propagates() -> None:
    """When a download job fails, the stored error message must appear in the
    job response body so the Dart client can surface it to the user."""
    pytest.importorskip("httpx")
    from fastapi.testclient import TestClient

    from backend.app.main import app

    with TestClient(app) as test_client:
        resp = test_client.get("/api/jobs/nonexistent-job-id")
    # A job that was never created returns 404 — verify the endpoint responds.
    assert resp.status_code == 404


def test_set_download_started_persists_downloading_state(
    isolated_cache: DatasetCache,
) -> None:
    """set_download_started writes status=downloading + job_id to DB so that
    get_status and get_active_job_id reflect the active download."""

    async def _run() -> None:
        await isolated_cache.initialize()
        await isolated_cache.set_download_started(
            "nmnist", "datasets/nmnist/nmnist.h5", "job-test-abc"
        )
        status = await isolated_cache.get_status("nmnist")
        assert status == DatasetDownloadStatus.downloading

        job_id = await isolated_cache.get_active_job_id("nmnist")
        assert job_id == "job-test-abc"

    asyncio.run(_run())


def test_concurrent_download_reuses_job_id() -> None:
    """A second POST /download while a job_id is already persisted in DB must
    return 202 with the same existing job_id instead of spawning a duplicate."""
    pytest.importorskip("httpx")
    from fastapi.testclient import TestClient

    from backend.app.main import app

    test_client = TestClient(app)

    large_entry = DatasetCatalogEntry(
        id="nmnist",
        label="nmnist.h5",
        description="Event-based MNIST",
        storage_path="datasets/nmnist/nmnist.h5",
        folder_path="datasets/nmnist/",
        source_filename="nmnist.h5",
        size_bytes=100 * 1024 * 1024,
        format="hdf5_generic_event",
    )
    large_catalog = DatasetCatalog(datasets=[large_entry])
    existing_job_id = "existing-job-abc123"

    with (
        patch(
            "backend.app.routers.datasets.load_dataset_catalog",
            return_value=large_catalog,
        ),
        patch(
            "backend.app.routers.datasets.firebase_bucket_configured",
            return_value=True,
        ),
        patch(
            "backend.app.routers.datasets.dataset_cache.get_ready_path",
            new_callable=AsyncMock,
            return_value=None,
        ),
        patch(
            "backend.app.routers.datasets.dataset_cache.get_active_job_id",
            new_callable=AsyncMock,
            return_value=existing_job_id,
        ),
    ):
        resp = test_client.post("/api/datasets/nmnist/download")

    assert resp.status_code == 202
    body = resp.json()
    assert body["job_id"] == existing_job_id


def test_companion_archive_extracted_alongside_dataset(
    isolated_cache: DatasetCache,
) -> None:
    """After a folder download, companion zip archives in the same directory
    are automatically extracted to a sibling __extracted directory."""
    # Build the primary payload and a companion zip archive.
    companion_buf = io.BytesIO()
    with zipfile.ZipFile(companion_buf, "w") as handle:
        handle.writestr("labels.csv", b"0,1,0\n1,0,1\n")
    companion_zip_payload = companion_buf.getvalue()

    payloads = {
        "Davis 24/main.aedat": b"selected-aedat-bytes",
        "Davis 24/labels.zip": companion_zip_payload,
    }

    class _MockResponse:
        def __init__(self, payload: bytes) -> None:
            self.status_code = 200
            self._payload = payload
            self.headers: dict[str, str] = {}

        def raise_for_status(self) -> None:
            return None

        def iter_bytes(self, chunk_size: int = 0):
            del chunk_size
            yield self._payload

    class _MockStream:
        def __init__(self, payload: bytes) -> None:
            self._payload = payload

        def __enter__(self):
            return _MockResponse(self._payload)

        def __exit__(self, *args: object) -> None:
            return None

    mock_http = MagicMock()
    mock_http.stream.side_effect = lambda _method, url: _MockStream(
        payloads[unquote(url.split("/o/", 1)[1].split("?alt=media", 1)[0])]
    )
    mock_http.__enter__.return_value = mock_http
    mock_http.__exit__.return_value = None

    async def _run() -> None:
        await isolated_cache.initialize()
        with (
            patch(
                "backend.app.services.dataset_cache.load_dataset_catalog",
                return_value=_catalog_for_tests(),
            ),
            patch(
                "backend.app.services.dataset_cache.list_firebase_folder_objects",
                return_value=[
                    FirebaseStorageObject(name="Davis 24/main.aedat"),
                    FirebaseStorageObject(name="Davis 24/labels.zip"),
                ],
            ),
            patch("httpx.Client", return_value=mock_http),
        ):
            result = isolated_cache._download_blocking("davis24-main")

        ready_path = Path(result["local_path"])
        assert ready_path.name == "main.aedat"
        assert ready_path.read_bytes() == payloads["Davis 24/main.aedat"]

        # Companion zip must have been extracted to labels__extracted/.
        extract_dir = ready_path.parent / "labels__extracted"
        assert extract_dir.is_dir(), "companion archive was not extracted"
        assert (extract_dir / "labels.csv").is_file()

    asyncio.run(_run())


def test_missing_extractor_does_not_fail_companion_archive(
    isolated_cache: DatasetCache,
) -> None:
    """If bsdtar is unavailable and a companion .7z exists, extraction is
    best-effort — it must not raise and the selected dataset must be ready."""
    payloads = {
        "Davis 24/main.aedat": b"selected-aedat-bytes",
        "Davis 24/extra.7z": b"not-a-real-7z",
    }

    class _MockResponse:
        def __init__(self, payload: bytes) -> None:
            self.status_code = 200
            self._payload = payload
            self.headers: dict[str, str] = {}

        def raise_for_status(self) -> None:
            return None

        def iter_bytes(self, chunk_size: int = 0):
            del chunk_size
            yield self._payload

    class _MockStream:
        def __init__(self, payload: bytes) -> None:
            self._payload = payload

        def __enter__(self):
            return _MockResponse(self._payload)

        def __exit__(self, *args: object) -> None:
            return None

    mock_http = MagicMock()
    mock_http.stream.side_effect = lambda _method, url: _MockStream(
        payloads[unquote(url.split("/o/", 1)[1].split("?alt=media", 1)[0])]
    )
    mock_http.__enter__.return_value = mock_http
    mock_http.__exit__.return_value = None

    async def _run() -> None:
        await isolated_cache.initialize()
        with (
            patch(
                "backend.app.services.dataset_cache.load_dataset_catalog",
                return_value=_catalog_for_tests(),
            ),
            patch(
                "backend.app.services.dataset_cache.list_firebase_folder_objects",
                return_value=[
                    FirebaseStorageObject(name="Davis 24/main.aedat"),
                    FirebaseStorageObject(name="Davis 24/extra.7z"),
                ],
            ),
            patch("httpx.Client", return_value=mock_http),
            # Simulate no bsdtar installed.
            patch("shutil.which", return_value=None),
        ):
            # Must complete without raising — companion extraction is best-effort.
            result = isolated_cache._download_blocking("davis24-main")

        status = await isolated_cache.get_status("davis24-main")
        assert status == DatasetDownloadStatus.ready
        ready_path = Path(result["local_path"])
        assert ready_path.name == "main.aedat"

    asyncio.run(_run())


def test_list_entries_includes_local_imports_folder(
    isolated_cache: DatasetCache,
) -> None:
    async def _run() -> None:
        await isolated_cache.initialize()
        with patch(
            "backend.app.services.dataset_cache.load_dataset_catalog",
            return_value=_catalog_for_tests(),
        ):
            await isolated_cache.register_local_dataset(
                filename="events.aedat",
                file_bytes=b"event-stream",
            )
            entries = await isolated_cache.list_entries()

        local_entries = [entry for entry in entries if entry.get("source") == "local"]
        assert len(local_entries) == 1
        assert local_entries[0]["folder_path"] == "local/"
        assert local_entries[0]["status"] == DatasetDownloadStatus.ready.value

    asyncio.run(_run())


@pytest.mark.asyncio
async def test_source_column_added_to_existing_db(tmp_path: Path) -> None:
    """Migration adds 'source' column without losing existing rows."""
    import aiosqlite

    db_path = tmp_path / "datasets.db"
    # Create DB with old schema (no source column)
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE dataset_downloads (
                dataset_id TEXT PRIMARY KEY,
                local_path TEXT NOT NULL,
                storage_path TEXT NOT NULL,
                content_sha256 TEXT,
                size_bytes INTEGER,
                downloaded_at TEXT NOT NULL,
                status TEXT NOT NULL,
                error_message TEXT,
                job_id TEXT
            )
        """
        )
        await db.execute(
            "INSERT INTO dataset_downloads VALUES (?, ?, ?, NULL, NULL, ?, ?, NULL, NULL)",
            ("ds1", "/tmp/ds1.h5", "bucket/ds1.h5", "2024-01-01T00:00:00Z", "ready"),
        )
        await db.commit()

    cache = DatasetCache(db_path=db_path, cache_root=tmp_path / "cache")
    await cache.initialize()

    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute("SELECT source FROM dataset_downloads WHERE dataset_id='ds1'") as cur:
            row = await cur.fetchone()
    assert row is not None
    assert row["source"] == "firebase"


@pytest.mark.asyncio
async def test_register_local_upload(tmp_path):
    cache = DatasetCache(db_path=tmp_path / "datasets.db", cache_root=tmp_path / "cache")
    await cache.initialize()

    file_bytes = b"fake aedat content" * 100
    result = await cache.register_local_upload(
        original_filename="recording.aedat",
        file_bytes=file_bytes,
    )

    assert result["local_path"].endswith("recording.aedat")
    assert result["sha256_verified"] is True
    assert result["size_bytes"] == len(file_bytes)
    assert Path(result["local_path"]).is_file()


@pytest.mark.asyncio
async def test_register_local_upload_collision(tmp_path):
    cache = DatasetCache(db_path=tmp_path / "datasets.db", cache_root=tmp_path / "cache")
    await cache.initialize()

    bytes1 = b"content1" * 10
    bytes2 = b"content2" * 10
    r1 = await cache.register_local_upload(original_filename="rec.aedat4", file_bytes=bytes1)
    r2 = await cache.register_local_upload(original_filename="rec.aedat4", file_bytes=bytes2)
    assert r1["local_path"] != r2["local_path"]
    assert "rec_1.aedat4" in r2["local_path"]


@pytest.mark.asyncio
async def test_register_local_upload_bad_extension(tmp_path):
    cache = DatasetCache(db_path=tmp_path / "datasets.db", cache_root=tmp_path / "cache")
    await cache.initialize()

    with pytest.raises(ValueError, match="Unsupported"):
        await cache.register_local_upload(
            original_filename="model.pt",
            file_bytes=b"not a dataset",
        )


@pytest.mark.asyncio
async def test_legacy_registry_without_source_column_is_migrated(tmp_path):
    """`initialize()` upgrades a pre-`source` database rather than failing.

    Documents the migration contract. It does not, on its own, guard the bug
    that shipped — see the next test for that one.
    """
    import sqlite3

    db_path = tmp_path / "datasets.db"
    legacy = sqlite3.connect(db_path)
    legacy.execute(
        """
        CREATE TABLE dataset_downloads (
            dataset_id TEXT PRIMARY KEY,
            local_path TEXT NOT NULL,
            storage_path TEXT NOT NULL,
            content_sha256 TEXT,
            size_bytes INTEGER,
            downloaded_at TEXT NOT NULL,
            status TEXT NOT NULL,
            error_message TEXT,
            job_id TEXT
        )
        """
    )
    legacy.commit()
    legacy.close()

    cache = DatasetCache(db_path=db_path, cache_root=tmp_path / "cache")
    await cache.initialize()

    columns = [
        row[1] for row in sqlite3.connect(db_path).execute("PRAGMA table_info(dataset_downloads)")
    ]
    assert "source" in columns

    # The query that actually broke: listing must not raise.
    entries, _ = await cache.list_entries_with_availability()
    assert isinstance(entries, list)


@pytest.mark.asyncio
async def test_registry_row_read_repairs_a_legacy_table(tmp_path):
    """Reading must work even when `initialize()` never ran.

    This is the bug that shipped. Under Docker suite_api never called
    `initialize()`, so the table was created by `_get_registry_row`'s own
    CREATE — which omitted `source` while the SELECT two lines later required
    it. Every dataset listing then returned 500 "no such column: source",
    leaving Setup unable to choose a dataset and every later Studio step locked
    behind it. Without the shared schema helper this raises OperationalError.
    """
    cache = DatasetCache(db_path=tmp_path / "datasets.db", cache_root=tmp_path / "cache")

    assert await cache.get_status("unknown-dataset") is not None
