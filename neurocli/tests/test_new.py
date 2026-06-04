"""Tests for neuro new command."""

from __future__ import annotations

import json
from pathlib import Path

from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def test_new_nir_snntorch_creates_structure(tmp_path: Path) -> None:
    result = runner.invoke(
        app,
        ["new", "my_proj", "--framework", "nir", "--target", "snntorch", "--output-dir", str(tmp_path)],
    )
    assert result.exit_code == 0, result.output
    assert (tmp_path / "my_proj" / "pyproject.toml").exists()
    assert (tmp_path / "my_proj" / "README.md").exists()
    assert (tmp_path / "my_proj" / "src" / "train.py").exists()
    assert (tmp_path / "my_proj" / "scripts" / "run.sh").exists()


def test_new_unsupported_combo_exits_1(tmp_path: Path) -> None:
    result = runner.invoke(
        app,
        ["new", "x", "--framework", "bad", "--target", "worse", "--json", "--output-dir", str(tmp_path)],
    )
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "unsupported_combination"
    assert "supported" in data


def test_new_json_output_mode(tmp_path: Path) -> None:
    result = runner.invoke(
        app,
        ["new", "json_proj", "--framework", "nir", "--target", "snntorch", "--json", "--output-dir", str(tmp_path)],
    )
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert data["status"] == "created"
    assert "json_proj" in data["path"]


def test_new_with_trainer(tmp_path: Path) -> None:
    result = runner.invoke(
        app,
        ["new", "trainer_proj", "--trainer", "snntorch", "--data", "event", "--output-dir", str(tmp_path)],
    )
    assert result.exit_code == 0
    assert (tmp_path / "trainer_proj" / "src" / "train.py").exists()


def test_new_existing_dir_exits_1(tmp_path: Path) -> None:
    # Pre-create the destination
    (tmp_path / "existing").mkdir()
    result = runner.invoke(
        app,
        ["new", "existing", "--framework", "nir", "--target", "snntorch", "--json", "--output-dir", str(tmp_path)],
    )
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "destination_exists"


def test_new_all_bundles_render(tmp_path: Path) -> None:
    combos = [
        ("nir", "snntorch"),
        ("nir", "lava_sim"),
        ("nir", "sc_neurocore"),
        ("neurocnl", "pynq"),
        ("akida", "brainchip"),
        ("neurocnl", "neurosim"),
    ]
    for fw, tgt in combos:
        result = runner.invoke(
            app,
            ["new", f"proj_{fw}_{tgt}", "--framework", fw, "--target", tgt, "--output-dir", str(tmp_path)],
        )
        assert result.exit_code == 0, f"{fw}+{tgt} failed: {result.output}"
        assert (tmp_path / f"proj_{fw}_{tgt}" / "pyproject.toml").exists()


def test_new_nir_sc_neurocore_creates_structure(tmp_path: Path) -> None:
    result = runner.invoke(
        app,
        ["new", "sc_proj", "--framework", "nir", "--target", "sc_neurocore", "--output-dir", str(tmp_path)],
    )
    assert result.exit_code == 0, result.output
    assert (tmp_path / "sc_proj" / "pyproject.toml").exists()
    assert (tmp_path / "sc_proj" / "README.md").exists()
    assert (tmp_path / "sc_proj" / "src" / "main.py").exists()
    assert (tmp_path / "sc_proj" / "scripts" / "run.sh").exists()
    # Verify sc-neurocore dep is present
    content = (tmp_path / "sc_proj" / "pyproject.toml").read_text()
    assert "sc-neurocore" in content
