"""Fetch and verify pinned third-party reference assets.

The application never imports these sources. The resolver keeps tutorial and
reference material reproducible without committing upstream repositories or
depending on the legacy, gitignored ``paper/`` directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = Path(__file__).with_name("reference_assets.lock.json")
DEFAULT_CACHE = REPO_ROOT / ".cache" / "nmtk" / "reference-assets"
INSTALL_METADATA = ".nmtk-reference.json"


class ReferenceAssetError(RuntimeError):
    """A reference source could not be validated, fetched, or installed."""


@dataclass(frozen=True)
class LegacyMapping:
    """Map one legacy local tree to a subdirectory of a pinned source."""

    path: Path
    source_subdir: PurePosixPath


@dataclass(frozen=True)
class ReferenceSource:
    """One immutable upstream reference source."""

    source_id: str
    display_name: str
    repository_url: str
    revision: str
    archive_url: str
    archive_sha256: str
    license: str
    include: tuple[str, ...]
    legacy: tuple[LegacyMapping, ...]

    @property
    def cache_key(self) -> str:
        """Return the immutable on-disk cache key."""
        return f"{self.source_id}/{self.revision}"


def _require_text(raw: dict[str, Any], key: str) -> str:
    value = raw.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ReferenceAssetError(
            f"Reference source field '{key}' must be a non-empty string."
        )
    return value.strip()


def _parse_source(raw: object) -> ReferenceSource:
    if not isinstance(raw, dict):
        raise ReferenceAssetError("Every reference source must be a JSON object.")

    include_raw = raw.get("include")
    if not isinstance(include_raw, list) or not include_raw:
        raise ReferenceAssetError(
            "Reference source field 'include' must be a non-empty list."
        )
    include = tuple(str(item) for item in include_raw if isinstance(item, str) and item)
    if len(include) != len(include_raw):
        raise ReferenceAssetError(
            "Reference source include patterns must be non-empty strings."
        )

    legacy_raw = raw.get("legacy", [])
    if not isinstance(legacy_raw, list):
        raise ReferenceAssetError("Reference source field 'legacy' must be a list.")
    legacy: list[LegacyMapping] = []
    for mapping in legacy_raw:
        if not isinstance(mapping, dict):
            raise ReferenceAssetError("Legacy mappings must be JSON objects.")
        legacy_path = _require_text(mapping, "path")
        source_subdir = str(mapping.get("source_subdir", "")).strip("/")
        legacy.append(
            LegacyMapping(
                path=Path(legacy_path), source_subdir=PurePosixPath(source_subdir)
            )
        )

    archive_sha256 = _require_text(raw, "archive_sha256").lower()
    if len(archive_sha256) != 64 or any(
        char not in "0123456789abcdef" for char in archive_sha256
    ):
        raise ReferenceAssetError(
            "Reference archive_sha256 must contain 64 hexadecimal characters."
        )

    source_id = _require_text(raw, "id")
    if any(char not in "abcdefghijklmnopqrstuvwxyz0123456789-" for char in source_id):
        raise ReferenceAssetError(
            f"Reference source id '{source_id}' is not a safe cache name."
        )

    return ReferenceSource(
        source_id=source_id,
        display_name=_require_text(raw, "display_name"),
        repository_url=_require_text(raw, "repository_url"),
        revision=_require_text(raw, "revision"),
        archive_url=_require_text(raw, "archive_url"),
        archive_sha256=archive_sha256,
        license=_require_text(raw, "license"),
        include=include,
        legacy=tuple(legacy),
    )


def load_manifest(path: Path = DEFAULT_MANIFEST) -> dict[str, ReferenceSource]:
    """Load and strictly validate the reference-source lock file."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReferenceAssetError(
            f"Could not read reference manifest '{path}': {exc}"
        ) from exc
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise ReferenceAssetError("Reference manifest schema_version must be 1.")
    raw_sources = payload.get("sources")
    if not isinstance(raw_sources, list) or not raw_sources:
        raise ReferenceAssetError(
            "Reference manifest must contain at least one source."
        )

    sources: dict[str, ReferenceSource] = {}
    for raw in raw_sources:
        source = _parse_source(raw)
        if source.source_id in sources:
            raise ReferenceAssetError(
                f"Duplicate reference source id '{source.source_id}'."
            )
        sources[source.source_id] = source
    return sources


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _matches(path: PurePosixPath, patterns: tuple[str, ...]) -> bool:
    return any(path.match(pattern) for pattern in patterns)


def _archive_relative_path(member_name: str) -> PurePosixPath | None:
    member_path = PurePosixPath(member_name)
    if member_path.is_absolute() or ".." in member_path.parts:
        raise ReferenceAssetError(f"Archive contains unsafe path '{member_name}'.")
    if len(member_path.parts) < 2:
        return None
    relative = PurePosixPath(*member_path.parts[1:])
    if not relative.parts:
        return None
    return relative


def _extract_selected(
    archive: Path, destination: Path, source: ReferenceSource
) -> list[str]:
    extracted: list[str] = []
    with tarfile.open(archive, mode="r:gz") as bundle:
        for member in bundle.getmembers():
            relative = _archive_relative_path(member.name)
            if relative is None or not _matches(relative, source.include):
                continue
            if member.issym() or member.islnk():
                raise ReferenceAssetError(
                    f"Selected archive member '{member.name}' is a link."
                )
            if member.isdir():
                continue
            if not member.isfile():
                raise ReferenceAssetError(
                    f"Selected archive member '{member.name}' is not a regular file."
                )
            source_file = bundle.extractfile(member)
            if source_file is None:
                raise ReferenceAssetError(
                    f"Could not read archive member '{member.name}'."
                )
            target = destination.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with source_file, target.open("wb") as output:
                shutil.copyfileobj(source_file, output)
            extracted.append(relative.as_posix())
    if not extracted:
        raise ReferenceAssetError(
            f"Reference source '{source.source_id}' matched no files."
        )
    return sorted(extracted)


def _metadata(source: ReferenceSource, files: list[str]) -> dict[str, object]:
    return {
        "schema_version": 1,
        "source_id": source.source_id,
        "repository_url": source.repository_url,
        "revision": source.revision,
        "archive_sha256": source.archive_sha256,
        "license": source.license,
        "files": files,
    }


def verify_source(
    source: ReferenceSource, cache_root: Path = DEFAULT_CACHE
) -> dict[str, object]:
    """Verify one installed source against its pinned metadata and file inventory."""
    destination = cache_root / source.source_id / source.revision
    metadata_path = destination / INSTALL_METADATA
    if not metadata_path.is_file():
        raise ReferenceAssetError(
            f"Reference source '{source.source_id}' is not installed."
        )
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReferenceAssetError(
            f"Installed metadata for '{source.source_id}' is unreadable: {exc}"
        ) from exc
    if not isinstance(metadata, dict):
        raise ReferenceAssetError(
            f"Installed metadata for '{source.source_id}' is invalid."
        )
    expected_fields = {
        "source_id": source.source_id,
        "repository_url": source.repository_url,
        "revision": source.revision,
        "archive_sha256": source.archive_sha256,
        "license": source.license,
    }
    for key, expected in expected_fields.items():
        if metadata.get(key) != expected:
            raise ReferenceAssetError(
                f"Installed source '{source.source_id}' has mismatched field '{key}'."
            )
    files = metadata.get("files")
    if (
        not isinstance(files, list)
        or not files
        or not all(isinstance(item, str) for item in files)
    ):
        raise ReferenceAssetError(
            f"Installed source '{source.source_id}' has no valid file list."
        )
    missing = [item for item in files if not (destination / item).is_file()]
    if missing:
        raise ReferenceAssetError(
            f"Installed source '{source.source_id}' is missing {len(missing)} file(s)."
        )
    return {
        "source_id": source.source_id,
        "revision": source.revision,
        "path": str(destination),
        "file_count": len(files),
        "status": "ok",
    }


def fetch_source(
    source: ReferenceSource,
    cache_root: Path = DEFAULT_CACHE,
    *,
    force: bool = False,
) -> dict[str, object]:
    """Download, checksum, and atomically install one selected reference tree."""
    destination = cache_root / source.source_id / source.revision
    if destination.exists() and not force:
        return verify_source(source, cache_root)

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=f"nmtk-{source.source_id}-", dir=destination.parent
    ) as raw:
        staging = Path(raw)
        archive = staging / "source.tar.gz"
        install_root = staging / "install"
        install_root.mkdir()
        try:
            with (
                urllib.request.urlopen(source.archive_url, timeout=60) as response,
                archive.open("wb") as output,
            ):
                shutil.copyfileobj(response, output)
        except (OSError, urllib.error.URLError) as exc:
            raise ReferenceAssetError(
                f"Could not download '{source.display_name}' from its pinned upstream source."
            ) from exc
        actual_sha256 = _sha256(archive)
        if actual_sha256 != source.archive_sha256:
            raise ReferenceAssetError(
                f"Checksum mismatch for '{source.source_id}': expected "
                f"{source.archive_sha256}, received {actual_sha256}."
            )
        files = _extract_selected(archive, install_root, source)
        (install_root / INSTALL_METADATA).write_text(
            json.dumps(_metadata(source, files), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if destination.exists():
            if not force:
                raise ReferenceAssetError(
                    f"Reference destination '{destination}' already exists."
                )
            shutil.rmtree(destination)
        os.replace(install_root, destination)
    return verify_source(source, cache_root)


def legacy_report(
    sources: dict[str, ReferenceSource],
    cache_root: Path = DEFAULT_CACHE,
    repo_root: Path = REPO_ROOT,
) -> dict[str, object]:
    """Compare legacy ignored trees with pinned cache files without modifying either tree."""
    reports: list[dict[str, object]] = []
    has_local_changes = False
    for source in sources.values():
        pinned_root = cache_root / source.source_id / source.revision
        for mapping in source.legacy:
            legacy_root = repo_root / mapping.path
            counts = {"matching": 0, "modified": 0, "legacy_only": 0}
            examples: dict[str, list[str]] = {"modified": [], "legacy_only": []}
            if legacy_root.is_dir():
                for legacy_file in sorted(
                    path for path in legacy_root.rglob("*") if path.is_file()
                ):
                    relative = legacy_file.relative_to(legacy_root)
                    pinned_relative = Path(*mapping.source_subdir.parts) / relative
                    pinned_file = pinned_root / pinned_relative
                    if not pinned_file.is_file():
                        counts["legacy_only"] += 1
                        if len(examples["legacy_only"]) < 20:
                            examples["legacy_only"].append(relative.as_posix())
                    elif _sha256(legacy_file) == _sha256(pinned_file):
                        counts["matching"] += 1
                    else:
                        counts["modified"] += 1
                        if len(examples["modified"]) < 20:
                            examples["modified"].append(relative.as_posix())
            has_local_changes = has_local_changes or bool(
                counts["modified"] or counts["legacy_only"]
            )
            reports.append(
                {
                    "source_id": source.source_id,
                    "legacy_path": str(mapping.path),
                    "legacy_exists": legacy_root.is_dir(),
                    "cache_installed": (pinned_root / INSTALL_METADATA).is_file(),
                    "counts": counts,
                    "examples": examples,
                }
            )
    return {
        "status": "ok",
        "legacy_trees": reports,
        "modified": has_local_changes,
    }


def _selected_sources(
    sources: dict[str, ReferenceSource], requested: str
) -> list[ReferenceSource]:
    if requested == "all":
        return list(sources.values())
    try:
        return [sources[requested]]
    except KeyError as exc:
        choices = ", ".join(sorted(sources))
        raise ReferenceAssetError(
            f"Unknown reference source '{requested}'. Choose: {choices}."
        ) from exc


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List pinned reference sources.")
    list_parser.set_defaults(source="all")

    fetch_parser = subparsers.add_parser(
        "fetch", help="Fetch one source or all sources."
    )
    fetch_parser.add_argument("source", nargs="?", default="all")
    fetch_parser.add_argument("--force", action="store_true")

    verify_parser = subparsers.add_parser(
        "verify", help="Verify one installed source or all."
    )
    verify_parser.add_argument("source", nargs="?", default="all")

    subparsers.add_parser(
        "legacy-report",
        help="Compare ignored legacy paper trees without changing them.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the reference-assets command and emit machine-readable JSON."""
    args = build_parser().parse_args(argv)
    try:
        sources = load_manifest(args.manifest)
        if args.command == "list":
            result: object = [
                {
                    "source_id": source.source_id,
                    "display_name": source.display_name,
                    "revision": source.revision,
                    "license": source.license,
                    "cache_key": source.cache_key,
                }
                for source in sources.values()
            ]
        elif args.command == "fetch":
            result = [
                fetch_source(source, args.cache, force=args.force)
                for source in _selected_sources(sources, args.source)
            ]
        elif args.command == "verify":
            result = [
                verify_source(source, args.cache)
                for source in _selected_sources(sources, args.source)
            ]
        else:
            result = legacy_report(sources, args.cache)
    except ReferenceAssetError as exc:
        print(json.dumps({"status": "error", "message": str(exc)}), file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
