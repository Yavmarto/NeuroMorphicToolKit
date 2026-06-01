from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SIGN_SCRIPT = REPO_ROOT / "nmtk" / "installer" / "macos" / "sign-and-notarize.sh"
IMPORT_SCRIPT = REPO_ROOT / "nmtk" / "installer" / "macos" / "import-signing-cert.sh"
BUILD_SCRIPT = REPO_ROOT / "nmtk" / "installer" / "macos" / "build-standalone.sh"
RELEASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release-desktop.yml"


def run_bash(script: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        ["bash", str(script), *args],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
        env=merged_env,
    )


def test_sign_and_notarize_check_reports_missing_credentials() -> None:
    scrubbed_env = {key: "" for key in os.environ if key.startswith(("MACOS_", "APPLE_"))}
    result = run_bash(SIGN_SCRIPT, "--check", env=scrubbed_env)

    assert result.returncode == 0, result.stderr
    assert "macos_signing_ready=false" in result.stdout
    assert "macos_notarization_ready=false" in result.stdout


def test_sign_and_notarize_check_reports_ready_when_configured() -> None:
    result = run_bash(
        SIGN_SCRIPT,
        "--check",
        env={
            "MACOS_SIGNING_IDENTITY": "Developer ID Application: Example Org (TEAMID1234)",
            "APPLE_ID": "release@example.com",
            "APPLE_APP_SPECIFIC_PASSWORD": "app-specific-password",
            "APPLE_TEAM_ID": "TEAMID1234",
            "MACOS_NOTARIZE": "true",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "macos_signing_ready=true" in result.stdout
    assert "macos_notarization_ready=true" in result.stdout
    assert "macos_notarize_requested=true" in result.stdout


def test_sign_and_notarize_dry_run_emits_codesign_and_notarytool_commands(tmp_path: Path) -> None:
    app_path = tmp_path / "neuro_toolkit.app"
    app_path.mkdir()

    result = run_bash(
        SIGN_SCRIPT,
        "--dry-run",
        "sign-app",
        str(app_path),
        env={
            "MACOS_SIGNING_IDENTITY": "Developer ID Application: Example Org (TEAMID1234)",
            "APPLE_ID": "release@example.com",
            "APPLE_APP_SPECIFIC_PASSWORD": "app-specific-password",
            "APPLE_TEAM_ID": "TEAMID1234",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "DRY-RUN: codesign" in result.stdout
    assert "--options runtime" in result.stdout
    assert "Developer ID Application: Example Org (TEAMID1234)" in result.stdout


def test_sign_and_notarize_dry_run_notarize_emits_notarytool(tmp_path: Path) -> None:
    dmg_path = tmp_path / "NeuroMorphicToolKit-dev-macos.dmg"
    dmg_path.write_bytes(b"fake-dmg")

    result = run_bash(
        SIGN_SCRIPT,
        "--dry-run",
        "notarize",
        str(dmg_path),
        env={
            "MACOS_SIGNING_IDENTITY": "Developer ID Application: Example Org (TEAMID1234)",
            "APPLE_ID": "release@example.com",
            "APPLE_APP_SPECIFIC_PASSWORD": "app-specific-password",
            "APPLE_TEAM_ID": "TEAMID1234",
        },
    )

    assert result.returncode == 0, result.stderr
    assert "DRY-RUN: xcrun notarytool submit" in result.stdout
    assert "DRY-RUN: xcrun stapler staple" in result.stdout


def test_import_signing_cert_skips_without_secrets() -> None:
    result = run_bash(IMPORT_SCRIPT, env={"MACOS_CERTIFICATE_P12": "", "MACOS_CERTIFICATE_PASSWORD": ""})

    assert result.returncode == 0, result.stderr
    assert "Skipping certificate import" in result.stdout


def test_build_standalone_reads_macos_signing_identity_env() -> None:
    source = BUILD_SCRIPT.read_text(encoding="utf-8")

    assert 'SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"' in source
    assert 'bash "$SIGN_HELPER" sign-app "$APP_PATH"' in source


def test_release_desktop_workflow_wires_macos_signing() -> None:
    source = RELEASE_WORKFLOW.read_text(encoding="utf-8")

    assert "import-signing-cert.sh" in source
    assert "sign-and-notarize.sh --check" in source
    assert "MACOS_SIGNING_IDENTITY: ${{ secrets.MACOS_SIGNING_IDENTITY }}" in source
    assert "APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}" in source
