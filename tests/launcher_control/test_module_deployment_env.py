"""Tests for module deployment environment helpers."""

from __future__ import annotations

from pathlib import Path

from nmtk.launcher_control.module_deployment_env import (
    build_dotenv_sync_script,
    missing_module_environment,
    module_env_requirements,
)

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_module_env_requirements_includes_neurohub_oauth() -> None:
    requirements = module_env_requirements(REPO_ROOT)
    assert "Neurohub" in requirements
    assert "GITHUB_OAUTH_CLIENT_ID" in requirements["Neurohub"][0]


def test_missing_module_environment_warns_when_oauth_unset() -> None:
    warnings = missing_module_environment({}, REPO_ROOT)
    assert any("GITHUB_OAUTH_CLIENT_ID" in item for item in warnings)


def test_missing_module_environment_is_clear_when_oauth_set() -> None:
    warnings = missing_module_environment(
        {"GITHUB_OAUTH_CLIENT_ID": "public-client"},
        REPO_ROOT,
    )
    assert not any("GITHUB_OAUTH_CLIENT_ID" in item for item in warnings)


def test_build_dotenv_sync_script_writes_values(tmp_path: Path) -> None:
    import subprocess

    script = build_dotenv_sync_script(str(tmp_path), {"GITHUB_OAUTH_CLIENT_ID": "abc"})
    subprocess.run(["bash", "-lc", script], check=True)
    env_file = tmp_path / ".env"
    assert env_file.exists()
    assert "GITHUB_OAUTH_CLIENT_ID=abc" in env_file.read_text(encoding="utf-8")
