"""Tests for Windows installer signing plumbing.

Mirrors tests/test_macos_installer_signing.py structure.
No real certificate or signtool.exe required — cross-platform tests only.
"""

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SIGN_SCRIPT = REPO_ROOT / "nmtk" / "installer" / "windows" / "sign-installer.ps1"


@pytest.mark.skipif(sys.platform != "win32", reason="Windows-only signing tests")
class TestWindowsSigningScript:
    def test_sign_script_exists(self):
        assert SIGN_SCRIPT.exists(), f"sign-installer.ps1 not found at {SIGN_SCRIPT}"

    def test_sign_script_check_mode_fails_gracefully_without_cert(self):
        result = subprocess.run(
            ["powershell.exe", "-File", str(SIGN_SCRIPT), "-Check"],
            capture_output=True, text=True,
        )
        output = result.stdout + result.stderr
        assert (
            "signtool.exe" in output
            or "not found" in output
            or "Prerequisites OK" in output
        ), f"Unexpected output from -Check: {output}"

    def test_sign_script_dry_run_without_installer_fails_with_message(self):
        result = subprocess.run(
            ["powershell.exe", "-File", str(SIGN_SCRIPT),
             "-InstallerPath", "nonexistent.exe", "-Thumbprint", "AABBCC", "-DryRun"],
            capture_output=True, text=True,
        )
        assert result.returncode != 0
        assert "not found" in (result.stdout + result.stderr).lower()

    def test_sign_script_missing_thumbprint_fails_with_message(self):
        import os
        env = os.environ.copy()
        env.pop("WINDOWS_SIGNING_THUMBPRINT", None)
        result = subprocess.run(
            ["powershell.exe", "-File", str(SIGN_SCRIPT),
             "-InstallerPath", str(SIGN_SCRIPT)],
            capture_output=True, text=True, env=env,
        )
        assert result.returncode != 0
        output = result.stdout + result.stderr
        assert "thumbprint" in output.lower() or "required" in output.lower()


class TestWindowsSigningScriptCrossPlatform:
    """Non-Windows checks that do not require powershell."""

    def test_sign_script_exists(self):
        assert SIGN_SCRIPT.exists(), f"sign-installer.ps1 not found at {SIGN_SCRIPT}"

    def test_sign_script_contains_dry_run_support(self):
        content = SIGN_SCRIPT.read_text()
        assert "DryRun" in content, "sign-installer.ps1 must support -DryRun flag"
        assert "Check" in content, "sign-installer.ps1 must support -Check flag"

    def test_code_signing_docs_exist(self):
        docs = SIGN_SCRIPT.parent / "CODE_SIGNING.md"
        assert docs.exists(), "CODE_SIGNING.md must exist alongside sign-installer.ps1"

    def test_build_script_references_signing(self):
        build_script = SIGN_SCRIPT.parent / "build-standalone.ps1"
        assert build_script.exists()
        content = build_script.read_text()
        assert "WINDOWS_SIGNING_THUMBPRINT" in content, \
            "build-standalone.ps1 must reference WINDOWS_SIGNING_THUMBPRINT"
        assert "sign-installer.ps1" in content, \
            "build-standalone.ps1 must invoke sign-installer.ps1"
