"""Tests for neurocli.manifest."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from neurocli.manifest import (
    ManifestNotFoundError,
    ModuleEntry,
    find_module,
    load_manifest,
)

_REPO_ROOT = Path(__file__).parent.parent.parent  # neurocli/ -> repo root


def test_manifest_loads_all_ids() -> None:
    modules = load_manifest(_REPO_ROOT)
    ids = {m.id for m in modules}
    expected = {
        "neurocnl",
        "Neurochip",
        "Neurobench",
        "Neurosense",
        "Neurohub",
        "neuro_dream_hand",
        "lava_backend",
    }
    assert expected.issubset(ids), f"Missing ids: {expected - ids}"


def test_manifest_returns_module_entries() -> None:
    modules = load_manifest(_REPO_ROOT)
    assert all(isinstance(m, ModuleEntry) for m in modules)


def test_manifest_missing_raises(tmp_path: Path) -> None:
    # tmp_path has no NMTK_ROOT and no modules.json ancestor
    with patch.dict("os.environ", {"NMTK_ROOT": str(tmp_path)}, clear=False), pytest.raises(ManifestNotFoundError):
        load_manifest(tmp_path)


def test_find_module_returns_entry() -> None:
    modules = load_manifest(_REPO_ROOT)
    entry = find_module(modules, "neurocnl")
    assert entry is not None
    assert entry.id == "neurocnl"


def test_find_module_unknown_returns_none() -> None:
    modules = load_manifest(_REPO_ROOT)
    assert find_module(modules, "does_not_exist") is None


def test_manifest_neurohub_has_port() -> None:
    modules = load_manifest(_REPO_ROOT)
    hub = find_module(modules, "Neurohub")
    assert hub is not None
    # Neurohub port used as registry default
    assert hub.port is not None


def test_manifest_from_fake_json(tmp_path: Path) -> None:
    fake = [
        {
            "id": "test_mod",
            "name": "Test",
            "port": 1234,
            "installPath": "test/",
            "uvicornTarget": "test.app:app",
            "hasFrontend": False,
            "required": False,
            "deployment": {"healthPath": "/health"},
        }
    ]
    manifest_dir = tmp_path / "nmtk" / "neuro_toolkit" / "assets"
    manifest_dir.mkdir(parents=True)
    (manifest_dir / "modules.json").write_text(json.dumps(fake))

    with patch.dict("os.environ", {"NMTK_ROOT": str(tmp_path)}, clear=False):
        modules = load_manifest(tmp_path)

    assert len(modules) == 1
    assert modules[0].id == "test_mod"
    assert modules[0].port == 1234
