"""Unit tests for scripts/dev/akida_driver_rebuild.sh.

The script's ``NMTK_AKIDA_REBUILD_TESTING=1`` mode skips root/visudo/systemctl
and lets every install path be redirected, so the recovery-timer installer
(CEL-460) can be exercised without touching the host.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "dev" / "akida_driver_rebuild.sh"


def _testing_env(tmp_path: Path) -> dict[str, str]:
    return {
        **os.environ,
        "NMTK_AKIDA_REBUILD_TESTING": "1",
        "NMTK_AKIDA_REBUILD_INSTALLED_HELPER": str(
            tmp_path / "libexec" / "nmtk-akida-driver-rebuild"
        ),
        "NMTK_AKIDA_REBUILD_SUDOERS_FILE": str(
            tmp_path / "sudoers" / "nmtk-akida-driver-rebuild"
        ),
        "NMTK_AKIDA_RECOVERY_HELPER": str(
            tmp_path / "libexec" / "nmtk-akida-driver-health"
        ),
        "NMTK_AKIDA_RECOVERY_SERVICE": str(
            tmp_path / "systemd" / "nmtk-akida-driver-recovery.service"
        ),
        "NMTK_AKIDA_RECOVERY_TIMER": str(
            tmp_path / "systemd" / "nmtk-akida-driver-recovery.timer"
        ),
        "NMTK_AKIDA_SRC_DIR": str(tmp_path / "src"),
    }


def _run(tmp_path: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        env=_testing_env(tmp_path),
    )


def test_version_flag_prints_helper_version(tmp_path: Path):
    res = _run(tmp_path, "--version")
    assert res.returncode == 0
    assert res.stdout.startswith("nmtk-akida-driver-rebuild ")


def test_install_recovery_timer_writes_units_and_wrapper(tmp_path: Path):
    env = _testing_env(tmp_path)
    res = _run(tmp_path, "--install-recovery-timer")
    assert res.returncode == 0, res.stderr

    helper = Path(env["NMTK_AKIDA_RECOVERY_HELPER"])
    service = Path(env["NMTK_AKIDA_RECOVERY_SERVICE"])
    timer = Path(env["NMTK_AKIDA_RECOVERY_TIMER"])

    assert helper.exists() and os.access(helper, os.X_OK)
    helper_text = helper.read_text(encoding="utf-8")
    # The wrapper probes the PCI binding before invoking the rebuild helper.
    assert "akida-pcie" in helper_text
    assert env["NMTK_AKIDA_REBUILD_INSTALLED_HELPER"] in helper_text

    service_text = service.read_text(encoding="utf-8")
    assert f"ExecStart={helper}" in service_text
    assert "Type=oneshot" in service_text

    timer_text = timer.read_text(encoding="utf-8")
    assert "OnUnitActiveSec=15min" in timer_text
    assert "OnBootSec=2min" in timer_text
    assert "Unit=nmtk-akida-driver-recovery.service" in timer_text
    assert "WantedBy=timers.target" in timer_text


def test_install_for_writes_scoped_sudoers_rule(tmp_path: Path):
    env = _testing_env(tmp_path)
    # In testing mode the install-for step runs, then the script stops at the
    # (absent) driver source tree instead of attempting apt-get/dkms.
    res = _run(tmp_path, "--install-for", "operator")
    assert res.returncode == 1
    assert "driver source not found" in res.stderr

    helper = Path(env["NMTK_AKIDA_REBUILD_INSTALLED_HELPER"])
    sudoers = Path(env["NMTK_AKIDA_REBUILD_SUDOERS_FILE"])
    assert helper.exists() and os.access(helper, os.X_OK)
    assert sudoers.exists()
    line = sudoers.read_text(encoding="utf-8")
    assert line == (
        f"operator ALL=(root) NOPASSWD: {env['NMTK_AKIDA_REBUILD_INSTALLED_HELPER']}\n"
    )


def test_install_for_rejects_unsafe_account(tmp_path: Path):
    res = _run(tmp_path, "--install-for", "bad name")
    assert res.returncode == 1
    assert "invalid account name" in res.stderr
