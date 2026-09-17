"""Dataset catalog for bundled fixtures or live Firebase Storage discovery."""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import cast
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import urlopen

from pydantic import BaseModel, Field

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_CATALOG_PATH = _BACKEND_ROOT / "assets" / "datasets" / "catalog.json"
_FIREBASE_OBJECT_BASE_URL = "https://firebasestorage.googleapis.com/v0/b"
SUPPORTED_DATASET_EXTENSIONS = frozenset({".aedat", ".aedat4", ".h5", ".hdf5", ".bin"})
LOCAL_DATASET_FOLDER_PATH = "local/"
IMPORTABLE_DATASET_MESSAGE = (
    "Supported formats: .aedat, .aedat4, .h5, .hdf5, .bin, "
    "and common archives (.zip, .tar, .tar.gz, .tgz)."
)
_ARCHIVE_EXTENSIONS = (
    ".tar.gz",
    ".tar.bz2",
    ".tar.xz",
    ".tgz",
    ".tbz2",
    ".txz",
    ".zip",
    ".7z",
    ".rar",
    ".tar",
)
_DESCRIPTION_FILENAME = "description.txt"


class FirebaseCatalogError(RuntimeError):
    """Live Firebase dataset discovery failed."""


class FirebaseStorageObject(BaseModel):
    name: str
    size_bytes: int | None = None


class DatasetCatalogEntry(BaseModel):
    id: str
    label: str
    description: str
    storage_path: str
    folder_path: str | None = None
    source_filename: str | None = None
    size_bytes: int | None = None
    content_sha256: str | None = None
    format: str | None = None
    split_layout: str | None = None
    loader_config: dict[str, object] = Field(default_factory=dict)


class DatasetCatalog(BaseModel):
    datasets: list[DatasetCatalogEntry] = Field(default_factory=list)

    def get(self, dataset_id: str) -> DatasetCatalogEntry | None:
        for entry in self.datasets:
            if entry.id == dataset_id:
                return entry
        return None


def _firebase_bucket_name() -> str:
    return os.environ.get("NEUROCNL_FIREBASE_BUCKET", "").strip()


def _firebase_endpoint(bucket: str, *, storage_path: str | None = None) -> str:
    if storage_path is not None:
        encoded = quote(storage_path, safe="")
        return f"{_FIREBASE_OBJECT_BASE_URL}/{bucket}/o/{encoded}"
    return f"{_FIREBASE_OBJECT_BASE_URL}/{bucket}/o"


def _read_json(url: str) -> dict[str, object]:
    try:
        with urlopen(url, timeout=30) as response:
            payload = response.read().decode("utf-8")
    except HTTPError as exc:
        raise FirebaseCatalogError(
            f"Firebase Storage listing failed with HTTP {exc.code} while requesting '{url}'."
        ) from exc
    except URLError as exc:
        raise FirebaseCatalogError(
            "Could not reach Firebase Storage while listing datasets. "
            "Verify NEUROCNL_FIREBASE_BUCKET and outbound network access."
        ) from exc
    return cast("dict[str, object]", json.loads(payload))


def _read_text(url: str) -> str:
    try:
        with urlopen(url, timeout=30) as response:
            return str(response.read().decode("utf-8").strip())
    except HTTPError as exc:
        if exc.code == 404:
            return ""
        raise FirebaseCatalogError(
            f"Firebase Storage object read failed with HTTP {exc.code} while requesting '{url}'."
        ) from exc
    except URLError as exc:
        raise FirebaseCatalogError(
            "Could not reach Firebase Storage while reading dataset descriptions."
        ) from exc


def list_firebase_folder_objects(
    bucket: str,
    folder_path: str,
) -> list[FirebaseStorageObject]:
    normalized = folder_path if folder_path.endswith("/") else f"{folder_path}/"
    url = (
        f"{_firebase_endpoint(bucket)}?prefix={quote(normalized, safe='')}&delimiter=/"
    )
    payload = _read_json(url)
    items = payload.get("items")
    if not isinstance(items, list):
        return []
    objects: list[FirebaseStorageObject] = []
    for raw in items:
        if not isinstance(raw, dict):
            continue
        name = raw.get("name")
        if not isinstance(name, str) or not name:
            continue
        size_raw = raw.get("size")
        size_bytes: int | None = None
        if isinstance(size_raw, str) and size_raw.isdigit():
            size_bytes = int(size_raw)
        elif isinstance(size_raw, int):
            size_bytes = size_raw
        objects.append(FirebaseStorageObject(name=name, size_bytes=size_bytes))
    return objects


def _fetch_size(bucket: str, name: str) -> int | None:
    meta_url = _firebase_endpoint(bucket, storage_path=name)
    try:
        payload = _read_json(meta_url)
        size_raw = payload.get("size")
        if isinstance(size_raw, str) and size_raw.isdigit():
            return int(size_raw)
        if isinstance(size_raw, int):
            return size_raw
    except Exception:
        pass
    return None


def is_importable_dataset_filename(filename: str) -> bool:
    """Return True when *filename* is a supported dataset file or archive wrapper."""
    if infer_dataset_format(filename) is not None:
        return True
    lower = Path(filename).name.lower()
    return any(lower.endswith(archive_ext) for archive_ext in _ARCHIVE_EXTENSIONS)


def infer_dataset_format(storage_path: str) -> str | None:
    suffix = _dataset_payload_suffix(storage_path)
    if suffix == ".aedat":
        return "aedat"
    if suffix == ".aedat4":
        return "aedat4"
    if suffix in {".h5", ".hdf5"}:
        return "hdf5_generic_event"
    if suffix == ".bin":
        return "nmnist_bin"
    return None


def _dataset_payload_suffix(storage_path: str) -> str:
    filename = Path(storage_path).name.lower()
    stripped = filename
    changed = True
    while changed:
        changed = False
        for archive_ext in _ARCHIVE_EXTENSIONS:
            if stripped.endswith(archive_ext):
                stripped = stripped[: -len(archive_ext)]
                changed = True
                break
    return Path(stripped).suffix.lower()


def _entry_id(folder_path: str, storage_path: str) -> str:
    folder_name = Path(folder_path.rstrip("/")).name or "dataset"
    slug = re.sub(r"[^a-z0-9]+", "-", folder_name.lower()).strip("-") or "dataset"
    digest = hashlib.sha1(storage_path.encode("utf-8")).hexdigest()[:12]
    return f"{slug}-{digest}"


def _description_for_folder(bucket: str, folder_path: str) -> str:
    text = _read_text(
        f"{_firebase_endpoint(bucket, storage_path=f'{folder_path}{_DESCRIPTION_FILENAME}')}?alt=media"
    )
    folder_name = Path(folder_path.rstrip("/")).name or "Dataset"
    return text or f"Dataset files from {folder_name}."


@lru_cache(maxsize=1)
def _load_static_dataset_catalog() -> DatasetCatalog:
    if not _CATALOG_PATH.is_file():
        raise FileNotFoundError(
            f"Dataset catalog not found at {_CATALOG_PATH}. "
            "Ensure backend/assets/datasets/catalog.json is present."
        )
    raw = json.loads(_CATALOG_PATH.read_text(encoding="utf-8"))
    return DatasetCatalog.model_validate(raw)


@lru_cache(maxsize=4)
def _load_firebase_dataset_catalog(bucket: str) -> DatasetCatalog:
    top_level = _read_json(f"{_firebase_endpoint(bucket)}?delimiter=/")
    prefixes = top_level.get("prefixes")
    if not isinstance(prefixes, list):
        return DatasetCatalog()

    entries: list[DatasetCatalogEntry] = []
    all_objects = []
    for raw_prefix in prefixes:
        if not isinstance(raw_prefix, str) or not raw_prefix:
            continue
        folder_path = raw_prefix if raw_prefix.endswith("/") else f"{raw_prefix}/"
        description = _description_for_folder(bucket, folder_path)
        objects = list_firebase_folder_objects(bucket, folder_path)
        for storage_object in objects:
            all_objects.append((folder_path, description, storage_object))

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = {
            executor.submit(_fetch_size, bucket, obj.name): obj
            for _, _, obj in all_objects
            if obj.size_bytes is None
        }
        for future in concurrent.futures.as_completed(futures):
            obj = futures[future]
            try:
                obj.size_bytes = future.result()
            except Exception:
                pass

    for folder_path, description, storage_object in all_objects:
        filename = Path(storage_object.name).name
        if filename == _DESCRIPTION_FILENAME:
            continue
        if infer_dataset_format(filename) is None:
            continue
        entries.append(
            DatasetCatalogEntry(
                id=_entry_id(folder_path, storage_object.name),
                label=filename,
                description=description,
                storage_path=storage_object.name,
                folder_path=folder_path,
                source_filename=filename,
                size_bytes=storage_object.size_bytes,
                format=infer_dataset_format(storage_object.name),
            )
        )

    entries.sort(
        key=lambda entry: ((entry.folder_path or "").lower(), entry.label.lower())
    )
    return DatasetCatalog(datasets=entries)


def load_dataset_catalog(*, refresh: bool = False) -> DatasetCatalog:
    bucket = _firebase_bucket_name()
    if bucket:
        if refresh:
            _load_firebase_dataset_catalog.cache_clear()
        return _load_firebase_dataset_catalog(bucket)
    if refresh:
        _load_static_dataset_catalog.cache_clear()
    return _load_static_dataset_catalog()


def reload_dataset_catalog_for_tests() -> None:
    """Clear the catalog cache (for unit tests only)."""
    _load_static_dataset_catalog.cache_clear()
    _load_firebase_dataset_catalog.cache_clear()
