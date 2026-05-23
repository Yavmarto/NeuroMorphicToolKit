"""Smoke tests for the root CLI entry point."""

from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def test_cli_help() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "neuro" in result.output.lower() or "nmtk" in result.output.lower()
