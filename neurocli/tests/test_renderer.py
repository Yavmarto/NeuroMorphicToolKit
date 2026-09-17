"""Tests for neurocli.renderer."""

from __future__ import annotations

from pathlib import Path

import pytest
from jinja2 import UndefinedError

from neurocli.renderer import UnknownBundleError, render_template

_VARS = {
    "project_name": "test_proj",
    "task": "kws",
    "data_type": "event",
}


def test_renderer_creates_files(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    assert (tmp_path / "pyproject.toml").exists()
    assert (tmp_path / "README.md").exists()
    assert (tmp_path / "src" / "train.py").exists()
    assert (tmp_path / "network.cnl").exists()
    assert (tmp_path / "scripts" / "run.sh").exists()


def test_renderer_files_non_empty(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    for path in [
        tmp_path / "pyproject.toml",
        tmp_path / "README.md",
        tmp_path / "src" / "train.py",
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
    import tomllib

    tomllib.loads(content)


def test_renderer_unknown_bundle_raises(tmp_path: Path) -> None:
    with pytest.raises(UnknownBundleError):
        render_template("does_not_exist", _VARS, tmp_path)


def test_renderer_pyproject_is_non_package_uv_project(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    content = (tmp_path / "pyproject.toml").read_text()
    assert "package = false" in content
    assert "snntorch" in content


def test_renderer_run_sh_trains_model(tmp_path: Path) -> None:
    render_template("nir_snntorch", _VARS, tmp_path)
    run_sh = (tmp_path / "scripts" / "run.sh").read_text()
    assert "python src/train.py" in run_sh


def test_renderer_missing_variable_raises(tmp_path: Path) -> None:
    with pytest.raises(UndefinedError):
        render_template("nir_snntorch", {"project_name": "x"}, tmp_path)
