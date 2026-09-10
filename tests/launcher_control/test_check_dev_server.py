"""Unit tests for check_dev_server.sh."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "check_dev_server.sh"


def test_help_flag():
    """Verify --help exits 0 and displays the usage message."""
    res = subprocess.run(
        ["bash", str(SCRIPT), "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert res.returncode == 0
    assert "check_dev_server.sh" in res.stdout
    assert "192.168.2.90" in res.stdout
    assert "--check-only" in res.stdout


def test_unreachable_host_mocked(tmp_path: Path):
    """Verify that an unreachable host exits 1 and displays troubleshooting instructions."""
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    fake_ssh = fake_bin / "ssh"
    fake_ssh.write_text("#!/bin/sh\nexit 255\n")
    fake_ssh.chmod(0o755)

    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
    res = subprocess.run(
        ["bash", str(SCRIPT), "192.168.2.90"],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    assert res.returncode == 1
    assert "Cannot reach moosebun2@192.168.2.90 via SSH" in res.stdout
    assert "Troubleshooting:" in res.stdout


def test_all_services_healthy_mocked(tmp_path: Path):
    """Verify that when all probes return OK, the script reports all healthy and exits 0."""
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()

    # Fake ssh that simulates successful checks on the remote server
    fake_ssh = fake_bin / "ssh"
    fake_ssh.write_text(
        """#!/usr/bin/env bash
cmd="$*"
if [[ "$cmd" == *"true"* ]]; then
  exit 0
elif [[ "$cmd" == *"systemctl is-active neurochip.service"* ]]; then
  echo "active"
  exit 0
elif [[ "$cmd" == *"command -v docker"* ]]; then
  echo "docker"
  exit 0
elif [[ "$cmd" == *"nmtk-read-akida-key"* ]]; then
  echo "fake-akida-key"
  exit 0
elif [[ "$cmd" == *"python3 -c"* ]]; then
  echo "OK"
  exit 0
fi
exit 0
"""
    )
    fake_ssh.chmod(0o755)

    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
    res = subprocess.run(
        ["bash", str(SCRIPT), "192.168.2.90"],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    assert res.returncode == 0
    assert "All dev server services are up and healthy!" in res.stdout
    assert "[OK]     suite_api (port 9000): running & healthy" in res.stdout
    assert "[OK]     launcher-control (port 8090): running & healthy" in res.stdout
    assert "[OK]     jupyter-server (port 8008): running & healthy" in res.stdout


def test_check_only_detects_down_service(tmp_path: Path):
    """Verify that --check-only exits 1 when a service is down without restarting."""
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()

    fake_ssh = fake_bin / "ssh"
    fake_ssh.write_text(
        """#!/usr/bin/env bash
cmd="$*"
if [[ "$cmd" == *"true"* ]]; then
  exit 0
elif [[ "$cmd" == *"systemctl is-active neurochip.service"* ]]; then
  echo "not-found"
  exit 0
elif [[ "$cmd" == *"systemctl list-unit-files"* ]]; then
  echo "0"
  exit 0
elif [[ "$cmd" == *"command -v docker"* ]]; then
  echo "docker"
  exit 0
elif [[ "$cmd" == *"9000"* ]]; then
  # suite_api is down
  echo "UNREACHABLE"
  exit 1
elif [[ "$cmd" == *"python3 -c"* ]]; then
  echo "OK"
  exit 0
fi
exit 0
"""
    )
    fake_ssh.chmod(0o755)

    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
    res = subprocess.run(
        ["bash", str(SCRIPT), "--check-only", "192.168.2.90"],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    assert res.returncode == 1
    assert "Check-only mode requested; exiting without restarting" in res.stdout
    assert "[DOWN]   suite_api (port 9000): UNREACHABLE" in res.stdout


def test_restarts_down_service_and_recovers(tmp_path: Path):
    """Verify that down services are restarted and verified."""
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    state_file = tmp_path / "restarted.txt"

    fake_ssh = fake_bin / "ssh"
    fake_ssh.write_text(
        f"""#!/usr/bin/env bash
cmd="$*"
if [[ "$cmd" == *"true"* ]]; then
  exit 0
elif [[ "$cmd" == *"systemctl is-active neurochip.service"* ]]; then
  echo "not-found"
  exit 0
elif [[ "$cmd" == *"systemctl list-unit-files"* ]]; then
  echo "0"
  exit 0
elif [[ "$cmd" == *"command -v docker"* ]]; then
  echo "docker"
  exit 0
elif [[ "$cmd" == *"compose"*"restart suite_api"* ]]; then
  touch "{state_file}"
  exit 0
elif [[ "$cmd" == *"9000"* ]]; then
  if [ -f "{state_file}" ]; then
    echo "OK"
    exit 0
  else
    echo "UNREACHABLE"
    exit 1
  fi
elif [[ "$cmd" == *"python3 -c"* ]]; then
  echo "OK"
  exit 0
fi
exit 0
"""
    )
    fake_ssh.chmod(0o755)

    env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
    res = subprocess.run(
        ["bash", str(SCRIPT), "192.168.2.90"],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )
    assert res.returncode == 0
    assert "Restarting container service: suite_api..." in res.stdout
    assert "suite_api (port 9000) is now healthy." in res.stdout
    assert "All dev server services are now running and healthy!" in res.stdout
