"""Archive-extraction and path-resolution helpers for downloaded/imported datasets.

Mechanical extraction from `dataset_cache.py`: the pieces that decide "is this
path an archive, and if so, unpack it and find the payload inside" have no
dependency on the download registry (the DB-backed status/job tracking that
stays in `dataset_cache.py`), so they live here instead. Bodies are copied
verbatim — behavior, strings, and comments are unchanged; the only shape
change is that former `DatasetCache` instance methods became plain functions
(none of them touched `self` for anything but calling one another).
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path

from backend.app.services.dataset_catalog import (
    DatasetCatalogEntry,
    infer_dataset_format,
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


class DatasetDownloadError(OSError):
    """Network or filesystem failure during download."""


def local_filename(entry: DatasetCatalogEntry) -> str:
    return entry.source_filename or Path(entry.storage_path).name or f"{entry.id}.bin"


def archive_extension(path: Path) -> str | None:
    lower_name = path.name.lower()
    for archive_ext in _ARCHIVE_EXTENSIONS:
        if lower_name.endswith(archive_ext):
            return archive_ext
    return None


def archive_payload_name(path: Path) -> str:
    archive_ext = archive_extension(path)
    if archive_ext is None:
        return path.name
    return path.name[: -len(archive_ext)]


def cache_relative_dir(entry: DatasetCatalogEntry) -> Path:
    raw = (entry.folder_path or entry.id).strip("/")
    relative = Path(raw) if raw else Path(entry.id)
    if relative.is_absolute() or ".." in relative.parts:
        raise DatasetDownloadError(
            f"Dataset '{entry.id}' resolved to an unsafe cache path. "
            "Check the Firebase folder layout and retry."
        )
    return relative


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_safe_member_path(extract_root: Path, member_name: str) -> None:
    target = (extract_root / member_name).resolve()
    root = extract_root.resolve()
    if target != root and root not in target.parents:
        raise DatasetDownloadError(
            "Downloaded dataset archive contains an unsafe path and was rejected."
        )


def extract_archive_with_bsdtar(archive_path: Path, extract_root: Path) -> None:
    bsdtar = shutil.which("bsdtar")
    if bsdtar is None:
        raise DatasetDownloadError(
            f"Downloaded dataset archive '{archive_path.name}' needs an external extractor. "
            "Install bsdtar to unpack .7z or .rar datasets on the server."
        )
    try:
        subprocess.run(
            [bsdtar, "-xf", str(archive_path), "-C", str(extract_root)],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise DatasetDownloadError(
            f"Downloaded dataset archive '{archive_path.name}' could not be extracted "
            f"with bsdtar: {exc.stderr.strip() or exc.stdout.strip() or 'unknown error'}"
        ) from exc


def extract_archive(archive_path: Path, extract_root: Path) -> None:
    archive_ext = archive_extension(archive_path)
    if archive_ext is None:
        return
    try:
        if archive_ext == ".zip":
            with zipfile.ZipFile(archive_path) as handle:
                for member in handle.infolist():
                    assert_safe_member_path(extract_root, member.filename)
                handle.extractall(extract_root)
            return
        if archive_ext in {
            ".tar",
            ".tar.gz",
            ".tar.bz2",
            ".tar.xz",
            ".tgz",
            ".tbz2",
            ".txz",
        }:
            with tarfile.open(archive_path) as handle:
                for member in handle.getmembers():
                    assert_safe_member_path(extract_root, member.name)
                handle.extractall(extract_root)
            return
        extract_archive_with_bsdtar(archive_path, extract_root)
    except DatasetDownloadError:
        shutil.rmtree(extract_root, ignore_errors=True)
        raise
    except (OSError, zipfile.BadZipFile, tarfile.TarError) as exc:
        shutil.rmtree(extract_root, ignore_errors=True)
        raise DatasetDownloadError(
            f"Downloaded dataset archive '{archive_path.name}' could not be extracted. "
            "Check that the archive is valid and that the server has the required "
            "extractor installed."
        ) from exc


def select_extracted_ready_path(
    entry: DatasetCatalogEntry,
    extract_root: Path,
    archive_path: Path,
) -> Path:
    exact_names: list[str] = []
    for raw_name in (
        entry.source_filename,
        Path(entry.storage_path).name,
        archive_payload_name(archive_path),
    ):
        if raw_name:
            candidate = archive_payload_name(Path(raw_name))
            if candidate and candidate not in exact_names:
                exact_names.append(candidate)

    for exact_name in exact_names:
        matches = [path for path in extract_root.rglob(exact_name)]
        files = [path for path in matches if path.is_file()]
        if len(files) == 1:
            return files[0]
        dirs = [path for path in matches if path.is_dir()]
        if len(dirs) == 1 and entry.format == "nmnist_bin":
            return dirs[0]

    dataset_files = [
        path
        for path in extract_root.rglob("*")
        if path.is_file() and infer_dataset_format(path.name) is not None
    ]
    if len(dataset_files) == 1:
        return dataset_files[0]
    if entry.format == "nmnist_bin":
        if dataset_files:
            return extract_root
        dataset_dirs = [path for path in extract_root.rglob("*") if path.is_dir()]
        if dataset_dirs:
            return extract_root

    raise DatasetDownloadError(
        f"Downloaded dataset archive '{archive_path.name}' was extracted, but NeuroCNL "
        "could not determine which file to use. Update the dataset catalog so the "
        "archive contains a single supported dataset payload."
    )


def resolve_ready_path(
    entry: DatasetCatalogEntry,
    dest_dir: Path,
    dest_path: Path,
) -> Path:
    if archive_extension(dest_path) is None:
        return dest_path

    extract_root = dest_dir / f"{archive_payload_name(dest_path)}__extracted"
    if extract_root.exists():
        shutil.rmtree(extract_root)
    extract_root.mkdir(parents=True, exist_ok=True)

    extract_archive(dest_path, extract_root)
    return select_extracted_ready_path(entry, extract_root, dest_path)


def extract_companion_archives(
    dest_dir: Path, selected_path: Path, *, logger: object
) -> None:
    """Best-effort extraction of companion archives in *dest_dir*.

    Archives other than *selected_path* are extracted non-blockingly.
    Errors are logged but never raised, so a broken companion archive
    never prevents the selected dataset from being marked ready.
    """
    for candidate in dest_dir.iterdir():
        if not candidate.is_file():
            continue
        if candidate.resolve() == selected_path.resolve():
            continue
        if archive_extension(candidate) is None:
            continue
        extract_root = dest_dir / f"{archive_payload_name(candidate)}__extracted"
        if extract_root.exists():
            continue  # already extracted from a previous run
        extract_root.mkdir(parents=True, exist_ok=True)
        try:
            extract_archive(candidate, extract_root)
            logger.info(  # type: ignore[attr-defined]
                "companion_archive_extracted",
                archive=candidate.name,
                dest=str(extract_root),
            )
        except Exception as exc:  # noqa: BLE001
            shutil.rmtree(extract_root, ignore_errors=True)
            logger.warning(  # type: ignore[attr-defined]
                "companion_archive_extraction_failed",
                archive=candidate.name,
                error=str(exc),
            )
