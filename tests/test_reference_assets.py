"""Tests for pinned third-party reference asset resolution."""

from __future__ import annotations

import hashlib
import io
import json
import tarfile
from pathlib import Path

import pytest

from tools.reference_assets import (
    INSTALL_METADATA,
    LegacyMapping,
    ReferenceAssetError,
    ReferenceSource,
    fetch_source,
    legacy_report,
    load_manifest,
    verify_source,
)


def _archive(tmp_path: Path, files: dict[str, bytes]) -> tuple[Path, str]:
    path = tmp_path / "source.tar.gz"
    with tarfile.open(path, mode="w:gz") as bundle:
        for name, content in files.items():
            info = tarfile.TarInfo(name=f"upstream-revision/{name}")
            info.size = len(content)
            bundle.addfile(info, io.BytesIO(content))
    return path, hashlib.sha256(path.read_bytes()).hexdigest()


def _source(archive: Path, sha256: str) -> ReferenceSource:
    return ReferenceSource(
        source_id="example-source",
        display_name="Example source",
        repository_url="https://example.invalid/upstream",
        revision="abc123",
        archive_url=archive.as_uri(),
        archive_sha256=sha256,
        license="MIT",
        include=("examples/*.ipynb", "LICENSE"),
        legacy=(LegacyMapping(Path("paper/example"), Path("examples")),),
    )


def test_repository_manifest_is_valid_and_immutable() -> None:
    sources = load_manifest()

    assert set(sources) == {
        "nir-paper",
        "norse-notebooks",
        "snntorch-tutorials",
        "spikingjelly-tutorials",
    }
    assert all(len(source.revision) == 40 for source in sources.values())
    assert all(len(source.archive_sha256) == 64 for source in sources.values())


def test_fetch_selects_files_and_verify_detects_missing_file(tmp_path: Path) -> None:
    archive, digest = _archive(
        tmp_path,
        {
            "examples/tutorial.ipynb": b"{}",
            "examples/internal.py": b"do_not_copy = True\n",
            "LICENSE": b"MIT\n",
        },
    )
    source = _source(archive, digest)
    cache = tmp_path / "cache"

    result = fetch_source(source, cache)

    installed = cache / source.source_id / source.revision
    assert result["status"] == "ok"
    assert (installed / "examples/tutorial.ipynb").read_bytes() == b"{}"
    assert (installed / "LICENSE").is_file()
    assert not (installed / "examples/internal.py").exists()
    metadata = json.loads((installed / INSTALL_METADATA).read_text(encoding="utf-8"))
    assert metadata["files"] == ["LICENSE", "examples/tutorial.ipynb"]

    (installed / "LICENSE").unlink()
    with pytest.raises(ReferenceAssetError, match="missing 1 file"):
        verify_source(source, cache)


def test_fetch_rejects_checksum_mismatch(tmp_path: Path) -> None:
    archive, _digest = _archive(tmp_path, {"LICENSE": b"MIT\n"})
    source = _source(archive, "0" * 64)

    with pytest.raises(ReferenceAssetError, match="Checksum mismatch"):
        fetch_source(source, tmp_path / "cache")


def test_fetch_rejects_selected_link(tmp_path: Path) -> None:
    archive = tmp_path / "source.tar.gz"
    with tarfile.open(archive, mode="w:gz") as bundle:
        info = tarfile.TarInfo(name="upstream-revision/examples/tutorial.ipynb")
        info.type = tarfile.SYMTYPE
        info.linkname = "../../outside"
        bundle.addfile(info)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()

    with pytest.raises(ReferenceAssetError, match="is a link"):
        fetch_source(_source(archive, digest), tmp_path / "cache")


def test_legacy_report_identifies_modified_and_unmanaged_files(tmp_path: Path) -> None:
    archive, digest = _archive(
        tmp_path,
        {
            "examples/same.ipynb": b"same",
            "examples/changed.ipynb": b"pinned",
            "LICENSE": b"MIT\n",
        },
    )
    source = _source(archive, digest)
    cache = tmp_path / "cache"
    fetch_source(source, cache)
    legacy = tmp_path / "paper" / "example"
    legacy.mkdir(parents=True)
    (legacy / "same.ipynb").write_bytes(b"same")
    (legacy / "changed.ipynb").write_bytes(b"local edit")
    (legacy / "local-only.py").write_text("local = True\n", encoding="utf-8")

    report = legacy_report({source.source_id: source}, cache, tmp_path)

    assert report["modified"] is True
    tree = report["legacy_trees"][0]
    assert tree["counts"] == {"matching": 1, "modified": 1, "legacy_only": 1}
    assert tree["examples"]["modified"] == ["changed.ipynb"]
    assert tree["examples"]["legacy_only"] == ["local-only.py"]
