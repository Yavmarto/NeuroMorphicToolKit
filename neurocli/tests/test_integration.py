"""Integration smoke tests — full help tree and command registration."""

from __future__ import annotations

from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def test_full_help_tree() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    for cmd in ("new", "deploy", "install", "run", "status", "hub", "studio"):
        assert cmd in result.output, f"'{cmd}' not found in --help output:\n{result.output}"


def test_hub_help_tree() -> None:
    result = runner.invoke(app, ["hub", "--help"])
    assert result.exit_code == 0
    for cmd in ("login", "push", "pull", "search"):
        assert cmd in result.output, f"'{cmd}' not found in hub --help:\n{result.output}"


def test_new_help_lists_supported_combos() -> None:
    result = runner.invoke(app, ["new", "--help"])
    assert result.exit_code == 0
    for combo in ("nir+snntorch", "nir+lava_sim", "neurocnl+pynq", "akida+brainchip", "neurocnl+neurosim"):
        assert combo in result.output, f"'{combo}' not found in new --help:\n{result.output}"


def test_status_unreachable_is_runtime_error() -> None:
    from unittest.mock import patch

    import httpx

    with patch("neurocli.lifecycle.httpx.get", side_effect=httpx.ConnectError("refused")):
        result = runner.invoke(app, ["status", "--json"])
    assert result.exit_code == 2


def test_new_all_five_combos_json(tmp_path: Path) -> None:  # type: ignore[name-defined]  # noqa: F821
    combos = [
        ("nir", "snntorch"),
        ("nir", "lava_sim"),
        ("neurocnl", "pynq"),
        ("akida", "brainchip"),
        ("neurocnl", "neurosim"),
    ]
    for fw, tgt in combos:
        result = runner.invoke(
            app,
            [
                "new",
                f"p_{fw}_{tgt}",
                "--framework",
                fw,
                "--target",
                tgt,
                "--experimental",
                "--json",
                "--output-dir",
                str(tmp_path),
            ],
        )
        assert result.exit_code == 0, f"{fw}+{tgt}: {result.output}"
