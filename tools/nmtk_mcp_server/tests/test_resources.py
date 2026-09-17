from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.nmtk_mcp_server.resources import (
    CanonicalPaths,
    find_repo_root,
    load_cnl_grammar,
    load_modules_manifest,
    load_support_matrix,
)


def test_find_repo_root_from_nested_file() -> None:
    root = find_repo_root(Path(__file__))
    assert (root / "AGENTS.md").exists()
    assert (root / "CODING_STYLE_GUIDE.md").exists()


def test_load_cnl_grammar_success() -> None:
    paths = CanonicalPaths(find_repo_root(Path(__file__)))
    grammar = load_cnl_grammar(paths)
    assert "CNL Grammar" in grammar


def test_load_support_matrix_success() -> None:
    paths = CanonicalPaths(find_repo_root(Path(__file__)))
    support = load_support_matrix(paths)
    assert "support" in support.lower()


def test_load_modules_manifest_success() -> None:
    paths = CanonicalPaths(find_repo_root(Path(__file__)))
    manifest = load_modules_manifest(paths)
    assert isinstance(manifest, list)
    assert manifest
    assert "id" in manifest[0]


def test_missing_file_failure(tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    paths = CanonicalPaths(repo_root)
    with pytest.raises(FileNotFoundError):
        load_cnl_grammar(paths)


def test_invalid_manifest_failure(tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    manifest_path = repo_root / "nmtk" / "neuro_toolkit" / "assets"
    manifest_path.mkdir(parents=True)
    (manifest_path / "modules.json").write_text("{bad json", encoding="utf-8")
    paths = CanonicalPaths(repo_root)
    with pytest.raises(ValueError, match="Invalid JSON"):
        load_modules_manifest(paths)


def test_manifest_must_be_list(tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    manifest_path = repo_root / "nmtk" / "neuro_toolkit" / "assets"
    manifest_path.mkdir(parents=True)
    (manifest_path / "modules.json").write_text(
        json.dumps({"id": "not-a-list"}),
        encoding="utf-8",
    )
    paths = CanonicalPaths(repo_root)
    with pytest.raises(ValueError, match="Expected modules manifest to be a list"):
        load_modules_manifest(paths)
