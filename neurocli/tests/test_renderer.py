"""Tests for neurocli.renderer."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

from neurocli.renderer import UnknownBundleError, render_template

_VARS = {
    "project_name": "test_proj",
    "task": "kws",
}


def test_renderer_creates_files(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    assert (tmp_path / "pyproject.toml").exists()
    assert (tmp_path / "README.md").exists()
    assert (tmp_path / "src" / "main.py").exists()
    assert (tmp_path / "scripts" / "run.sh").exists()


def test_renderer_files_non_empty(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    for path in [
        tmp_path / "pyproject.toml",
        tmp_path / "README.md",
        tmp_path / "src" / "main.py",
        tmp_path / "scripts" / "run.sh",
    ]:
        assert path.stat().st_size > 0, f"{path} is empty"


def test_renderer_jinja_substitution(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    readme = (tmp_path / "README.md").read_text()
    assert "test_proj" in readme
    assert "kws" in readme
    # No un-rendered Jinja tags left
    assert "{{" not in readme


def test_renderer_pyproject_parseable(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    content = (tmp_path / "pyproject.toml").read_text()
    if sys.version_info >= (3, 11):
        import tomllib
        tomllib.loads(content)
    else:
        # tomllib available as tomli on older pythons — just check it's non-empty
        assert len(content) > 10


def test_renderer_unknown_bundle_raises(tmp_path: Path) -> None:
    with pytest.raises(UnknownBundleError):
        render_template("does_not_exist", _VARS, tmp_path)
