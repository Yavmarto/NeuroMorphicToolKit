"""Server-side cache for datasets downloaded from public Firebase Storage."""

from __future__ import annotations

import os
import shutil
import tempfile
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path
from typing import Any
from urllib.parse import quote

import structlog
from sqlalchemy import select, update
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import OperationalError

from backend.app.services.dataset_archive import (
    DatasetDownloadError,
    archive_extension,
    cache_relative_dir,
    extract_companion_archives,
    local_filename,
    resolve_ready_path,
    sha256_file,
)
from backend.app.services.dataset_cache_db import (
    DatasetDownloadDB,
    raw_session_scope,
    session_scope,
    sync_session_scope,
)
from backend.app.services.dataset_catalog import (
    IMPORTABLE_DATASET_MESSAGE,
    LOCAL_DATASET_FOLDER_PATH,
    DatasetCatalogEntry,
    FirebaseStorageObject,
    _entry_id,
    infer_dataset_format,
    is_importable_dataset_filename,
    list_firebase_folder_objects,
    load_dataset_catalog,
)

logger = structlog.get_logger(__name__)

DATA_DIR = Path(os.environ.get("NEUROCNL_DATA_DIR", Path.home() / ".neurocnl"))
DB_PATH = DATA_DIR / "datasets.db"
CACHE_ROOT = DATA_DIR / "datasets"

DEFAULT_SYNC_MAX_BYTES = 50 * 1024 * 1024


class DatasetDownloadStatus(StrEnum):
    not_downloaded = "not_downloaded"
    downloading = "downloading"
    ready = "ready"
    error = "error"


class DatasetSource(StrEnum):
    firebase = "firebase"
    local = "local"


class DatasetNotFoundError(KeyError):
    """Unknown dataset id."""


class FirebaseNotConfiguredError(RuntimeError):
    """NEUROCNL_FIREBASE_BUCKET is not set."""


class DatasetIntegrityError(ValueError):
    """Downloaded bytes do not match the catalog hash."""


class LocalDatasetImportError(ValueError):
    """Local dataset import rejected (unsupported format or missing path)."""


def firebase_public_url(bucket: str, storage_path: str) -> str:
    encoded = quote(storage_path, safe="")
    return f"https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encoded}?alt=media"


def firebase_bucket_configured() -> bool:
    return bool(os.environ.get("NEUROCNL_FIREBASE_BUCKET", "").strip())


def get_firebase_bucket() -> str:
    bucket = os.environ.get("NEUROCNL_FIREBASE_BUCKET", "").strip()
    if not bucket:
        raise FirebaseNotConfiguredError(
            "Firebase Storage is not configured on this server. "
            "Set NEUROCNL_FIREBASE_BUCKET to your public bucket name and restart the backend."
        )
    return bucket


def _local_row_to_entry(row: dict) -> dict:
    local_path = Path(row["local_path"])
    status = (
        DatasetDownloadStatus.ready
        if local_path.exists()
        else DatasetDownloadStatus.not_downloaded
    )
    return {
        "id": row["dataset_id"],
        "label": local_path.name,
        "description": f"Local file: {local_path.name}",
        "storage_path": row["storage_path"],
        "folder_path": "local",
        "source_filename": local_path.name,
        "size_bytes": row["size_bytes"],
        "content_sha256": row["content_sha256"],
        "status": status.value,
        "local_path": (
            str(local_path) if status == DatasetDownloadStatus.ready else None
        ),
        "downloaded_at": (
            row["downloaded_at"] if status == DatasetDownloadStatus.ready else None
        ),
        "error_message": row.get("error_message"),
        "download_progress": None,
    }


def _row_to_dict(row: DatasetDownloadDB) -> dict[str, Any]:
    return {
        "dataset_id": row.dataset_id,
        "local_path": row.local_path,
        "storage_path": row.storage_path,
        "content_sha256": row.content_sha256,
        "size_bytes": row.size_bytes,
        "downloaded_at": row.downloaded_at,
        "status": row.status,
        "error_message": row.error_message,
        "job_id": row.job_id,
        "source": row.source,
    }


class DatasetCache:
    """Persistent dataset download registry and on-disk cache."""

    def __init__(
        self,
        db_path: Path = DB_PATH,
        cache_root: Path = CACHE_ROOT,
    ) -> None:
        self.db_path = db_path
        self.cache_root = cache_root
        self._downloading: set[str] = set()
        self._progress: dict[str, float] = {}

    async def initialize(self) -> None:
        self.cache_root.mkdir(parents=True, exist_ok=True)
        # Reset any rows left in 'downloading' state from a previous (crashed/killed)
        # server process.  The in-memory job_store is gone on restart, so these rows
        # would appear stuck forever to the frontend.
        async with session_scope(self.db_path) as session:
            await session.execute(
                update(DatasetDownloadDB)
                .where(
                    DatasetDownloadDB.status == DatasetDownloadStatus.downloading.value
                )
                .values(status=DatasetDownloadStatus.not_downloaded.value, job_id=None)
            )
            await session.commit()
        logger.info(
            "dataset_cache.initialized",
            db_path=str(self.db_path),
            cache_root=str(self.cache_root),
        )

    def _is_downloading(self, dataset_id: str) -> bool:
        return dataset_id in self._downloading

    async def _get_registry_row(self, dataset_id: str) -> dict[str, Any] | None:
        try:
            async with session_scope(self.db_path) as session:
                row = await session.get(DatasetDownloadDB, dataset_id)
                if row is None:
                    return None
                return _row_to_dict(row)
        except OperationalError as exc:
            if "no such table" in str(exc).lower():
                return None
            raise

    async def get_status(self, dataset_id: str) -> DatasetDownloadStatus:
        if self._is_downloading(dataset_id):
            return DatasetDownloadStatus.downloading
        row = await self._get_registry_row(dataset_id)
        if row is None:
            return DatasetDownloadStatus.not_downloaded
        status = row["status"]
        if status == DatasetDownloadStatus.downloading.value:
            # Persisted downloading state (survives server restarts).
            return DatasetDownloadStatus.downloading
        if status == DatasetDownloadStatus.ready.value:
            local_path = Path(row["local_path"])
            if local_path.is_file() or local_path.is_dir():
                return DatasetDownloadStatus.ready
            return DatasetDownloadStatus.not_downloaded
        if status == DatasetDownloadStatus.error.value:
            return DatasetDownloadStatus.error
        return DatasetDownloadStatus.not_downloaded

    async def get_active_job_id(self, dataset_id: str) -> str | None:
        """Return the persisted job_id if this dataset is currently downloading."""
        row = await self._get_registry_row(dataset_id)
        if row and row.get("status") == DatasetDownloadStatus.downloading.value:
            return row.get("job_id") or None
        return None

    async def set_download_started(
        self, dataset_id: str, storage_path: str, job_id: str
    ) -> None:
        """Persist that a download job has been queued.

        Allows repeated POST requests to return the existing job_id instead of
        spawning a duplicate download.
        """
        async with session_scope(self.db_path) as session:
            stmt = sqlite_insert(DatasetDownloadDB).values(
                dataset_id=dataset_id,
                local_path="",
                storage_path=storage_path,
                content_sha256=None,
                size_bytes=None,
                downloaded_at=datetime.now(UTC).isoformat(),
                status=DatasetDownloadStatus.downloading.value,
                error_message=None,
                job_id=job_id,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[DatasetDownloadDB.dataset_id],
                set_={
                    "status": stmt.excluded.status,
                    "job_id": stmt.excluded.job_id,
                    "storage_path": stmt.excluded.storage_path,
                    "downloaded_at": stmt.excluded.downloaded_at,
                    "error_message": None,
                },
            )
            await session.execute(stmt)
            await session.commit()

    async def get_ready_path(self, dataset_id: str) -> str | None:
        status = await self.get_status(dataset_id)
        if status != DatasetDownloadStatus.ready:
            return None
        row = await self._get_registry_row(dataset_id)
        if row is None:
            return None
        return row["local_path"]

    async def list_entries(self) -> list[dict[str, Any]]:
        catalog = load_dataset_catalog(refresh=False)
        items: list[dict[str, Any]] = []
        for entry in catalog.datasets:
            status = await self.get_status(entry.id)
            row = await self._get_registry_row(entry.id)
            items.append(
                {
                    "id": entry.id,
                    "label": entry.label,
                    "description": entry.description,
                    "storage_path": entry.storage_path,
                    "folder_path": entry.folder_path,
                    "source_filename": entry.source_filename,
                    "size_bytes": (
                        row.get("size_bytes")
                        if row and row.get("size_bytes") is not None
                        else entry.size_bytes
                    ),
                    "content_sha256": entry.content_sha256,
                    "status": status.value,
                    "local_path": (
                        row["local_path"]
                        if row and status == DatasetDownloadStatus.ready
                        else None
                    ),
                    "downloaded_at": (
                        row["downloaded_at"]
                        if row and status == DatasetDownloadStatus.ready
                        else None
                    ),
                    "error_message": (
                        row["error_message"]
                        if row and status == DatasetDownloadStatus.error
                        else None
                    ),
                    "download_progress": self._progress.get(entry.id),
                    "source": "firebase",
                    "format": entry.format,
                }
            )
        local_items = await self._list_local_entry_dicts()
        catalog_ids = {item["id"] for item in items}
        for local_item in local_items:
            if local_item["id"] not in catalog_ids:
                items.append(local_item)
        return items

    async def _list_local_entry_dicts(self) -> list[dict[str, Any]]:
        rows = await self._fetch_local_registry_rows()
        items: list[dict[str, Any]] = []
        for row in rows:
            dataset_id = row["dataset_id"]
            status = await self.get_status(dataset_id)
            items.append(self._local_registry_row_to_entry(row, status))
        return items

    async def _fetch_local_registry_rows(self) -> list[dict[str, Any]]:
        try:
            async with raw_session_scope(self.db_path) as session:
                rows = (
                    (
                        await session.execute(
                            select(DatasetDownloadDB)
                            .where(
                                DatasetDownloadDB.source == DatasetSource.local.value
                            )
                            .order_by(DatasetDownloadDB.downloaded_at.desc())
                        )
                    )
                    .scalars()
                    .all()
                )
                return [_row_to_dict(row) for row in rows]
        except OperationalError:
            return []

    async def _list_local_rows(self) -> list[dict]:
        async with raw_session_scope(self.db_path) as session:
            rows = (
                (
                    await session.execute(
                        select(DatasetDownloadDB)
                        .where(DatasetDownloadDB.source == "local")
                        .order_by(DatasetDownloadDB.downloaded_at.desc())
                    )
                )
                .scalars()
                .all()
            )
            return [_row_to_dict(row) for row in rows]

    async def register_local_upload(
        self,
        *,
        original_filename: str,
        file_bytes: bytes,
    ) -> dict:
        from backend.app.services.dataset_catalog import SUPPORTED_DATASET_EXTENSIONS

        suffix = Path(original_filename).suffix.lower()
        if suffix not in SUPPORTED_DATASET_EXTENSIONS:
            supported = ", ".join(sorted(SUPPORTED_DATASET_EXTENSIONS))
            raise ValueError(
                f"Unsupported file type '{suffix}'. Accepted formats: {supported}"
            )

        local_dir = self.cache_root / "local"
        local_dir.mkdir(parents=True, exist_ok=True)

        stem = Path(original_filename).stem
        dest = local_dir / original_filename
        counter = 0
        while dest.exists() and counter < 999:
            counter += 1
            dest = local_dir / f"{stem}_{counter}{suffix}"

        with tempfile.NamedTemporaryFile(
            dir=local_dir, delete=False, suffix=suffix
        ) as tmp:
            tmp_inner = Path(tmp.name)
            tmp.write(file_bytes)
        tmp_inner.replace(dest)

        sha256 = sha256_file(dest)
        dataset_id = f"local__{dest.stem}"
        now = datetime.now(UTC).isoformat()

        self._upsert_registry_sync(
            dataset_id=dataset_id,
            local_path=str(dest),
            storage_path=f"local/{dest.name}",
            content_sha256=sha256,
            size_bytes=len(file_bytes),
            downloaded_at=now,
            status=DatasetDownloadStatus.ready,
            error_message=None,
            job_id=None,
            source=DatasetSource.local,
        )
        return {
            "dataset_id": dataset_id,
            "local_path": str(dest),
            "downloaded_at": now,
            "sha256_verified": True,
            "size_bytes": len(file_bytes),
        }

    def _local_registry_row_to_entry(
        self,
        row: dict[str, Any],
        status: DatasetDownloadStatus,
    ) -> dict[str, Any]:
        storage_path = str(row["storage_path"])
        if storage_path.startswith("local://"):
            label = Path(storage_path.removeprefix("local://")).name
        else:
            label = Path(row["local_path"]).name
        return {
            "id": row["dataset_id"],
            "label": label,
            "description": f"Imported from this device ({label}).",
            "storage_path": storage_path,
            "folder_path": LOCAL_DATASET_FOLDER_PATH,
            "source_filename": label,
            "size_bytes": row.get("size_bytes"),
            "content_sha256": row.get("content_sha256"),
            "status": status.value,
            "local_path": (
                row["local_path"] if status == DatasetDownloadStatus.ready else None
            ),
            "downloaded_at": (
                row["downloaded_at"] if status == DatasetDownloadStatus.ready else None
            ),
            "error_message": (
                row["error_message"] if status == DatasetDownloadStatus.error else None
            ),
            "download_progress": None,
            "source": DatasetSource.local.value,
            "format": infer_dataset_format(label),
        }

    async def get_entry_dict(self, dataset_id: str) -> dict[str, Any] | None:
        catalog = load_dataset_catalog(refresh=False)
        entry = catalog.get(dataset_id)
        if entry is not None:
            status = await self.get_status(dataset_id)
            row = await self._get_registry_row(dataset_id)
            return {
                "id": entry.id,
                "label": entry.label,
                "description": entry.description,
                "storage_path": entry.storage_path,
                "folder_path": entry.folder_path,
                "source_filename": entry.source_filename,
                "size_bytes": (
                    row.get("size_bytes")
                    if row and row.get("size_bytes") is not None
                    else entry.size_bytes
                ),
                "content_sha256": entry.content_sha256,
                "status": status.value,
                "local_path": (
                    row["local_path"]
                    if row and status == DatasetDownloadStatus.ready
                    else None
                ),
                "downloaded_at": (
                    row["downloaded_at"]
                    if row and status == DatasetDownloadStatus.ready
                    else None
                ),
                "error_message": (
                    row["error_message"]
                    if row and status == DatasetDownloadStatus.error
                    else None
                ),
                "download_progress": self._progress.get(entry.id),
                "source": "firebase",
                "format": entry.format,
            }
        row = await self._get_registry_row(dataset_id)
        if row is None or row.get("source") != DatasetSource.local.value:
            return None
        status = await self.get_status(dataset_id)
        return self._local_registry_row_to_entry(row, status)

    def register_local_dataset_blocking(
        self,
        *,
        filename: str,
        file_bytes: bytes | None = None,
        server_path: str | None = None,
    ) -> dict[str, Any]:
        safe_name = Path(filename).name
        if not safe_name or safe_name in {".", ".."}:
            raise LocalDatasetImportError("Dataset filename is invalid.")
        if not is_importable_dataset_filename(safe_name):
            raise LocalDatasetImportError(IMPORTABLE_DATASET_MESSAGE)

        storage_path = f"local://{safe_name}"
        dataset_id = _entry_id(LOCAL_DATASET_FOLDER_PATH, storage_path)
        dest_dir = self.cache_root / "local" / dataset_id
        dest_dir.mkdir(parents=True, exist_ok=True)

        if file_bytes is not None:
            dest_path = dest_dir / safe_name
            dest_path.write_bytes(file_bytes)
            ready_path = dest_path
        elif server_path:
            source = Path(server_path).expanduser()
            if not source.exists():
                raise LocalDatasetImportError(
                    f"Dataset path '{server_path}' does not exist on the server. "
                    "Choose the file again or upload it instead."
                )
            if source.is_dir():
                if infer_dataset_format(safe_name) != "nmnist_bin" and not any(
                    child.suffix.lower() == ".bin"
                    for child in source.rglob("*")
                    if child.is_file()
                ):
                    raise LocalDatasetImportError(IMPORTABLE_DATASET_MESSAGE)
                dest_path = dest_dir / safe_name
                if dest_path.exists():
                    shutil.rmtree(dest_path)
                shutil.copytree(source, dest_path)
                ready_path = dest_path
            else:
                if not is_importable_dataset_filename(source.name):
                    raise LocalDatasetImportError(IMPORTABLE_DATASET_MESSAGE)
                ready_path = source.resolve()
                dest_path = ready_path
        else:
            raise LocalDatasetImportError(
                "Provide a dataset file upload or a server_path to import."
            )

        entry = DatasetCatalogEntry(
            id=dataset_id,
            label=safe_name,
            description=f"Imported from this device ({safe_name}).",
            storage_path=storage_path,
            folder_path=LOCAL_DATASET_FOLDER_PATH,
            source_filename=safe_name,
            size_bytes=self._path_size(ready_path),
            format=infer_dataset_format(safe_name),
        )

        if ready_path.is_file() and archive_extension(ready_path) is not None:
            ready_path = resolve_ready_path(entry, dest_dir, ready_path)

        content_sha256 = sha256_file(ready_path) if ready_path.is_file() else None
        downloaded_at = datetime.now(UTC).isoformat()
        size_bytes = self._path_size(ready_path)
        self._upsert_registry_sync(
            dataset_id=dataset_id,
            local_path=str(ready_path.resolve()),
            storage_path=storage_path,
            content_sha256=content_sha256,
            size_bytes=size_bytes,
            downloaded_at=downloaded_at,
            status=DatasetDownloadStatus.ready,
            error_message=None,
            source=DatasetSource.local,
        )
        return self._local_registry_row_to_entry(
            {
                "dataset_id": dataset_id,
                "local_path": str(ready_path.resolve()),
                "storage_path": storage_path,
                "content_sha256": content_sha256,
                "size_bytes": size_bytes,
                "downloaded_at": downloaded_at,
                "status": DatasetDownloadStatus.ready.value,
                "error_message": None,
            },
            DatasetDownloadStatus.ready,
        )

    async def register_local_dataset(
        self,
        *,
        filename: str,
        file_bytes: bytes | None = None,
        server_path: str | None = None,
    ) -> dict[str, Any]:
        import asyncio

        return await asyncio.to_thread(
            self.register_local_dataset_blocking,
            filename=filename,
            file_bytes=file_bytes,
            server_path=server_path,
        )

    def _download_blocking(self, dataset_id: str) -> dict[str, Any]:
        catalog = load_dataset_catalog(refresh=True)
        entry = catalog.get(dataset_id)
        if entry is None:
            raise DatasetNotFoundError(
                f"Dataset '{dataset_id}' is not in the catalog. "
                "Choose a dataset from the Setup list or verify it still exists in Firebase Storage."
            )

        bucket = get_firebase_bucket()
        dest_dir = self.cache_root / cache_relative_dir(entry)
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest_path = dest_dir / local_filename(entry)

        folder_path = (
            entry.folder_path or f"{Path(entry.storage_path).parent.as_posix()}/"
        ).rstrip("/")
        objects = list_firebase_folder_objects(bucket, folder_path)
        if not objects:
            objects = [
                FirebaseStorageObject(
                    name=entry.storage_path,
                    size_bytes=entry.size_bytes,
                )
            ]

        try:
            import httpx
        except ImportError as exc:
            raise DatasetDownloadError(
                "httpx is required for dataset downloads. Install with: pip install httpx"
            ) from exc

        self._downloading.add(dataset_id)
        try:
            missing_objects = [
                storage_object
                for storage_object in objects
                if not (dest_dir / Path(storage_object.name).name).is_file()
            ]
            if missing_objects:
                # Compute total bytes for aggregate progress reporting.
                # Use size_bytes from Firebase metadata when available, otherwise
                # fall back to the catalog entry size (covers single-file case).
                total_bytes = sum(obj.size_bytes or 0 for obj in missing_objects)
                if total_bytes == 0 and entry.size_bytes:
                    total_bytes = entry.size_bytes
                bytes_done_offset = 0
                with httpx.Client(timeout=httpx.Timeout(60.0, connect=30.0)) as client:
                    for storage_object in missing_objects:
                        object_dest = dest_dir / Path(storage_object.name).name
                        self._download_object(
                            client,
                            bucket=bucket,
                            storage_path=storage_object.name,
                            dest_path=object_dest,
                            dataset_id=dataset_id,
                            progress_offset=bytes_done_offset,
                            total_bytes=total_bytes,
                        )
                        bytes_done_offset += storage_object.size_bytes or 0
            if not dest_path.is_file():
                raise DatasetDownloadError(
                    f"Dataset file '{entry.storage_path}' was not found in Firebase folder "
                    f"'{folder_path}/'."
                )
            actual_hash = sha256_file(dest_path)
            sha256_verified = False
            if entry.content_sha256:
                if actual_hash.lower() != entry.content_sha256.lower():
                    dest_path.unlink(missing_ok=True)
                    raise DatasetIntegrityError(
                        f"Downloaded dataset '{dataset_id}' failed integrity check. "
                        f"Expected SHA-256 {entry.content_sha256}, got {actual_hash}. "
                        "Re-download it or update the dataset metadata."
                    )
                sha256_verified = True
            ready_path = resolve_ready_path(entry, dest_dir, dest_path)
            # Best-effort extraction of companion archives in the same folder.
            extract_companion_archives(dest_dir, dest_path, logger=logger)
            return self._finalize_ready(
                entry,
                dest_path,
                actual_hash,
                ready_path=ready_path,
                sha256_verified=sha256_verified,
            )
        finally:
            self._downloading.discard(dataset_id)
            self._progress.pop(dataset_id, None)

    def _download_object(
        self,
        client: Any,
        *,
        bucket: str,
        storage_path: str,
        dest_path: Path,
        dataset_id: str = "",
        progress_offset: int = 0,
        total_bytes: int = 0,
    ) -> None:
        url = firebase_public_url(bucket, storage_path)
        with tempfile.NamedTemporaryFile(delete=False, dir=dest_path.parent) as tmp:
            tmp_path = Path(tmp.name)
        try:
            with client.stream("GET", url) as response:
                if response.status_code == 404:
                    raise DatasetDownloadError(
                        f"Dataset object '{storage_path}' was not found in Firebase Storage. "
                        "Check the live bucket contents and retry from Setup."
                    )
                response.raise_for_status()
                content_length = int(response.headers.get("content-length", 0))
                # Fall back to caller-supplied total if Firebase omits Content-Length.
                effective_total = total_bytes if total_bytes > 0 else content_length
                bytes_written = 0
                with tmp_path.open("wb") as out:
                    for chunk in response.iter_bytes(chunk_size=1024 * 1024):
                        out.write(chunk)
                        bytes_written += len(chunk)
                        if dataset_id and effective_total > 0:
                            self._progress[dataset_id] = min(
                                1.0,
                                (progress_offset + bytes_written) / effective_total,
                            )
            tmp_path.replace(dest_path)
            # NOTE: do NOT pop self._progress here — _download_blocking manages
            # lifetime so multi-file progress remains monotonically increasing.
        except OSError as exc:
            tmp_path.unlink(missing_ok=True)
            raise DatasetDownloadError(
                f"Could not save dataset content on the server: {exc}. "
                "Check disk space and NEUROCNL_DATA_DIR permissions."
            ) from exc
        except Exception as exc:
            tmp_path.unlink(missing_ok=True)
            try:
                import httpx
            except ImportError:
                raise
            if isinstance(exc, httpx.HTTPError):
                raise DatasetDownloadError(
                    "Could not download dataset content from Firebase Storage. "
                    "Verify NEUROCNL_FIREBASE_BUCKET and that the bucket allows public read."
                ) from exc
            raise

    def _finalize_ready(
        self,
        entry: DatasetCatalogEntry,
        dest_path: Path,
        content_sha256: str,
        *,
        ready_path: Path | None = None,
        sha256_verified: bool | None = None,
    ) -> dict[str, Any]:
        resolved_ready_path = ready_path or dest_path
        if sha256_verified is None:
            sha256_verified = bool(
                entry.content_sha256
                and content_sha256.lower() == entry.content_sha256.lower()
            )
        downloaded_at = datetime.now(UTC).isoformat()
        size_bytes = self._path_size(resolved_ready_path)
        self._upsert_registry_sync(
            dataset_id=entry.id,
            local_path=str(resolved_ready_path.resolve()),
            storage_path=entry.storage_path,
            content_sha256=content_sha256,
            size_bytes=size_bytes,
            downloaded_at=downloaded_at,
            status=DatasetDownloadStatus.ready,
            error_message=None,
            source=DatasetSource.firebase,
        )
        return {
            "dataset_id": entry.id,
            "local_path": str(resolved_ready_path.resolve()),
            "downloaded_at": downloaded_at,
            "sha256_verified": sha256_verified,
            "size_bytes": size_bytes,
        }

    def _path_size(self, path: Path) -> int:
        if path.is_file():
            return path.stat().st_size
        if path.is_dir():
            return sum(
                child.stat().st_size for child in path.rglob("*") if child.is_file()
            )
        return 0

    def _upsert_registry_sync(
        self,
        *,
        dataset_id: str,
        local_path: str,
        storage_path: str,
        content_sha256: str | None,
        size_bytes: int | None,
        downloaded_at: str,
        status: DatasetDownloadStatus,
        error_message: str | None,
        job_id: str | None = None,
        source: DatasetSource = DatasetSource.firebase,
    ) -> None:
        with sync_session_scope(self.db_path) as session:
            stmt = sqlite_insert(DatasetDownloadDB).values(
                dataset_id=dataset_id,
                local_path=local_path,
                storage_path=storage_path,
                content_sha256=content_sha256,
                size_bytes=size_bytes,
                downloaded_at=downloaded_at,
                status=status.value,
                error_message=error_message,
                job_id=job_id,
                source=source.value,
            )
            stmt = stmt.on_conflict_do_update(
                index_elements=[DatasetDownloadDB.dataset_id],
                set_={
                    "local_path": stmt.excluded.local_path,
                    "storage_path": stmt.excluded.storage_path,
                    "content_sha256": stmt.excluded.content_sha256,
                    "size_bytes": stmt.excluded.size_bytes,
                    "downloaded_at": stmt.excluded.downloaded_at,
                    "status": stmt.excluded.status,
                    "error_message": stmt.excluded.error_message,
                    "job_id": stmt.excluded.job_id,
                    "source": stmt.excluded.source,
                },
            )
            session.execute(stmt)
            session.commit()

    async def ensure_downloaded(self, dataset_id: str) -> dict[str, Any]:
        status = await self.get_status(dataset_id)
        if status == DatasetDownloadStatus.ready:
            path = await self.get_ready_path(dataset_id)
            row = await self._get_registry_row(dataset_id)
            return {
                "dataset_id": dataset_id,
                "local_path": path,
                "downloaded_at": row["downloaded_at"] if row else None,
                "sha256_verified": bool(row and row.get("content_sha256")),
                "size_bytes": row["size_bytes"] if row else None,
            }
        if status == DatasetDownloadStatus.downloading:
            raise DatasetDownloadError(
                f"Dataset '{dataset_id}' is already downloading. Poll GET /api/datasets/{dataset_id}."
            )
        import asyncio

        return await asyncio.to_thread(self._download_blocking, dataset_id)

    def should_download_async(self, entry: DatasetCatalogEntry) -> bool:
        sync_max = int(
            os.environ.get(
                "NEUROCNL_DATASET_SYNC_MAX_BYTES",
                str(DEFAULT_SYNC_MAX_BYTES),
            )
        )
        if entry.size_bytes is None:
            return True
        return entry.size_bytes > sync_max

    async def list_entries_with_availability(self) -> tuple[list[dict], bool]:
        """Like list_entries but also returns whether Firebase catalog loaded OK."""
        from backend.app.services.dataset_catalog import (
            DatasetCatalog,
            FirebaseCatalogError,
        )

        firebase_ok = True
        try:
            catalog = load_dataset_catalog(refresh=False)
        except FirebaseCatalogError:
            catalog = DatasetCatalog()
            firebase_ok = False

        items: list[dict] = []
        for entry in catalog.datasets:
            status = await self.get_status(entry.id)
            row = await self._get_registry_row(entry.id)
            items.append(
                {
                    "id": entry.id,
                    "label": entry.label,
                    "description": entry.description,
                    "storage_path": entry.storage_path,
                    "folder_path": entry.folder_path,
                    "source_filename": entry.source_filename,
                    "size_bytes": (
                        row.get("size_bytes")
                        if row and row.get("size_bytes") is not None
                        else entry.size_bytes
                    ),
                    "content_sha256": entry.content_sha256,
                    "status": status.value,
                    "local_path": (
                        row["local_path"]
                        if row and status == DatasetDownloadStatus.ready
                        else None
                    ),
                    "downloaded_at": (
                        row["downloaded_at"]
                        if row and status == DatasetDownloadStatus.ready
                        else None
                    ),
                    "error_message": (
                        row["error_message"]
                        if row and status == DatasetDownloadStatus.error
                        else None
                    ),
                    "download_progress": self._progress.get(entry.id),
                    "source": "firebase",
                    "format": entry.format,
                }
            )
        local_items = await self._list_local_entry_dicts()
        catalog_ids = {item["id"] for item in items}
        for local_item in local_items:
            if local_item["id"] not in catalog_ids:
                items.append(local_item)
        return items, firebase_ok

    def start_download(self, dataset_id: str) -> None:
        """Start a background download thread. Idempotent: no-op if already running."""
        if self._is_downloading(dataset_id):
            return
        import threading

        # Persist downloading status immediately so the frontend sees it on the next
        # GET /api/datasets/{id} poll even before the thread begins.
        try:
            catalog = load_dataset_catalog(refresh=False)
            entry = catalog.get(dataset_id)
            if entry is not None:
                self._upsert_registry_sync(
                    dataset_id=dataset_id,
                    local_path="",
                    storage_path=entry.storage_path,
                    content_sha256=None,
                    size_bytes=entry.size_bytes,
                    downloaded_at=datetime.now(UTC).isoformat(),
                    status=DatasetDownloadStatus.downloading,
                    error_message=None,
                    job_id=None,
                    source=DatasetSource.firebase,
                )
        except Exception:  # noqa: BLE001
            pass  # Non-fatal: thread will set status itself

        t = threading.Thread(
            target=self._run_download_safe,
            args=(dataset_id,),
            daemon=True,
            name=f"dataset-dl-{dataset_id}",
        )
        t.start()

    def _run_download_safe(self, dataset_id: str) -> None:
        """Thread entry point: runs _download_blocking and logs unexpected errors."""
        try:
            self._download_blocking(dataset_id)
        except Exception as exc:  # noqa: BLE001
            # _download_blocking writes error status to DB via _finalize_ready /
            # _upsert_registry_sync path; this catch is a backstop for unexpected raises.
            logger.error(
                "dataset_download_unexpected_error",
                dataset_id=dataset_id,
                error=str(exc),
            )


dataset_cache = DatasetCache()
