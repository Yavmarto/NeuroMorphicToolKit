"""Build a provisioning bundle for the minimal PYNQ runtime agent."""

from __future__ import annotations

import json
import shutil
import stat
import subprocess
from pathlib import Path
from typing import Any

from .pynq_agent_launch import (
    build_pynq_agent_stop_command,
    build_pynq_user_space_agent_launch_command,
)

DEFAULT_REMOTE_INSTALL_ROOT = "/opt/neurochip-pynq-agent"
DEFAULT_REMOTE_VENV_PATH = f"{DEFAULT_REMOTE_INSTALL_ROOT}/venv"
DEFAULT_REMOTE_PYNQ_VENV_PATH = f"{DEFAULT_REMOTE_INSTALL_ROOT}/pynq-venv"
DEFAULT_REMOTE_OVERLAY_DIR = f"{DEFAULT_REMOTE_INSTALL_ROOT}/overlays"
DEFAULT_REMOTE_SERVICE_NAME = "neurochip-pynq-agent"
DEFAULT_CANONICAL_PYNQ_PYTHON = "/usr/local/share/pynq-venv/bin/python"
# On the stock PYNQ Linux image the Xilinx XRT libraries ship under /usr/lib
# (not /opt/xilinx/xrt as on workstation installs). /etc/profile.d/xrt_setup.sh
# sets XILINX_XRT=/usr which we mirror here so the systemd unit inherits the
# same environment an interactive xilinx shell does. Without these env vars
# the pynq subprocess worker fails with PYNQ_DEVICE_NOT_FOUND / cannot locate
# libxrt_core.so.2.
DEFAULT_XILINX_XRT_PATH = "/usr"
DEFAULT_BOARD_NAME = "Pynq-Z2"
DEFAULT_AGENT_HEALTH_TIMEOUT_S = 120


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _latest_wheel(dist_dir: Path) -> Path | None:
    wheels = sorted(dist_dir.glob("neurochip-*.whl"), key=lambda path: path.stat().st_mtime)
    return wheels[-1] if wheels else None


def ensure_agent_wheel(repo_root: Path | None = None) -> Path:
    """Locate or build the latest Neurochip wheel for provisioning."""
    root = repo_root or _repo_root()
    dist_dir = root / "dist"

    result = subprocess.run(
        ["poetry", "build", "-f", "wheel"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "poetry build failed")

    wheel = _latest_wheel(dist_dir)
    if wheel is None:
        raise RuntimeError("poetry build completed without producing a wheel")
    return wheel


def _systemd_unit_text(
    *,
    service_name: str,
    install_root: str,
    agent_venv_path: str,
    pynq_python_path: str,
    install_status_path: str,
    overlay_dir: str,
    xilinx_xrt_path: str = DEFAULT_XILINX_XRT_PATH,
    board_name: str = DEFAULT_BOARD_NAME,
) -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=NeuroChip PYNQ runtime agent",
            "After=network-online.target",
            "Wants=network-online.target",
            "",
            "[Service]",
            "Type=simple",
            f"WorkingDirectory={install_root}",
            f"Environment=PYTHONPATH={install_root}",
            f"Environment=NEUROCHIP_PYNQ_PYTHON={pynq_python_path}",
            "Environment=NEUROCHIP_PYNQ_INSTALL_MODE=systemd",
            f"Environment=NEUROCHIP_PYNQ_INSTALL_STATUS_PATH={install_status_path}",
            f"Environment=NEUROCHIP_PYNQ_OVERLAY_DIR={overlay_dir}",
            # XRT / BOARD env — systemd does not source /etc/profile.d, so the
            # agent and its pynq subprocess worker would otherwise be missing
            # XILINX_XRT, LD_LIBRARY_PATH, and BOARD and fail device probe with
            # PYNQ_DEVICE_NOT_FOUND. Mirror the values that a login shell on
            # the stock PYNQ image inherits.
            f"Environment=XILINX_XRT={xilinx_xrt_path}",
            f"Environment=LD_LIBRARY_PATH={xilinx_xrt_path}/lib:/usr/lib:/usr/local/lib",
            (
                f"Environment=PATH={xilinx_xrt_path}/bin:/usr/local/sbin:"
                "/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
            ),
            f"Environment=BOARD={board_name}",
            f"ExecStart={agent_venv_path}/bin/neurochip-pynq-agent",
            "Restart=on-failure",
            "RestartSec=5",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _install_script_text(
    *,
    install_root: str,
    agent_venv_path: str,
    pynq_venv_path: str,
    overlay_dir: str,
    service_name: str,
    wheel_name: str,
) -> str:
    stop_command = build_pynq_agent_stop_command(
        agent_executable='"$AGENT_VENV_PATH/bin/neurochip-pynq-agent"',
        shell_safe_values=True,
    )
    launch_command = build_pynq_user_space_agent_launch_command(
        agent_executable='"$AGENT_VENV_PATH/bin/neurochip-pynq-agent"',
        pynq_python_path='"$EFFECTIVE_PYNQ_PYTHON"',
        install_status_path='"$INSTALL_STATUS_PATH"',
        overlay_dir='"$OVERLAY_DIR"',
        runtime_log_path='"$RUNTIME_LOG_PATH"',
        shell_safe_values=True,
    )
    return "\n".join(
        [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "",
            'log_step() { printf "[install-pynq-agent] %s\\n" "$1"; }',
            "",
            'BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
            f'INSTALL_ROOT="${{INSTALL_ROOT:-{install_root}}}"',
            f'AGENT_VENV_PATH="${{AGENT_VENV_PATH:-{agent_venv_path}}}"',
            f'PYNQ_VENV_PATH="${{PYNQ_VENV_PATH:-{pynq_venv_path}}}"',
            f'OVERLAY_DIR="${{OVERLAY_DIR:-{overlay_dir}}}"',
            f'SERVICE_NAME="${{SERVICE_NAME:-{service_name}}}"',
            f'WHEEL_NAME="${{WHEEL_NAME:-{wheel_name}}}"',
            'INSTALL_STATUS_PATH="${INSTALL_STATUS_PATH:-$INSTALL_ROOT/install-status.json}"',
            'RUNTIME_LOG_PATH="${RUNTIME_LOG_PATH:-$INSTALL_ROOT/runtime.log}"',
            'AGENT_HOST="${NEUROCHIP_PYNQ_AGENT_HOST:-127.0.0.1}"',
            'AGENT_PORT="${NEUROCHIP_PYNQ_AGENT_PORT:-8002}"',
            f'CANONICAL_PYNQ_PYTHON="${{CANONICAL_PYNQ_PYTHON:-{DEFAULT_CANONICAL_PYNQ_PYTHON}}}"',
            'EFFECTIVE_PYNQ_PYTHON=""',
            'PYNQ_RUNTIME_SOURCE="unknown"',
            'AGENT_PACKAGE_VERSION=""',
            'AGENT_WHEEL_NAME="$WHEEL_NAME"',
            "",
            "write_install_status() {",
            '  STATUS_JSON="$(python3 - "$1" "$2" "$SERVICE_NAME" "$AGENT_VENV_PATH" "$PYNQ_VENV_PATH" "$RUNTIME_LOG_PATH" "$EFFECTIVE_PYNQ_PYTHON" "$PYNQ_RUNTIME_SOURCE" "$AGENT_PACKAGE_VERSION" "$AGENT_WHEEL_NAME" <<'
            "'"
            "PY"
            "'"
            "",
            "import json",
            "import sys",
            "from pathlib import Path",
            "",
            "payload = {",
            '    "installMode": sys.argv[1],',
            '    "message": sys.argv[2],',
            '    "serviceName": sys.argv[3],',
            '    "agentVenvPath": sys.argv[4],',
            '    "pynqVenvPath": sys.argv[5],',
            '    "runtimeLogPath": sys.argv[6],',
            '    "effectivePynqPython": sys.argv[7],',
            '    "pynqRuntimeSource": sys.argv[8],',
            '    "agentPackageVersion": sys.argv[9],',
            '    "agentWheelName": sys.argv[10],',
            '    "autoStartSupported": sys.argv[1] == "systemd",',
            "}",
            "print(json.dumps(payload, indent=2, sort_keys=True))",
            "PY",
            ')"',
            "  if sudo -n true >/dev/null 2>&1; then",
            '    sudo -n mkdir -p "$(dirname "$INSTALL_STATUS_PATH")"',
            '    printf "%s\\n" "$STATUS_JSON" | sudo -n tee "$INSTALL_STATUS_PATH" >/dev/null',
            "  else",
            '    mkdir -p "$(dirname "$INSTALL_STATUS_PATH")"',
            '    printf "%s\\n" "$STATUS_JSON" > "$INSTALL_STATUS_PATH"',
            "  fi",
            "}",
            "",
            "detect_pynq_runtime() {",
            '  if [ -x "$CANONICAL_PYNQ_PYTHON" ] && \\',
            '     "$CANONICAL_PYNQ_PYTHON" -c "import pynq; import pyxrt" >/dev/null 2>&1; then',
            '    EFFECTIVE_PYNQ_PYTHON="$CANONICAL_PYNQ_PYTHON"',
            '    PYNQ_RUNTIME_SOURCE="canonical"',
            "    return 0",
            "  fi",
            "  return 1",
            "}",
            "",
            "wait_for_health() {",
            '  python3 - "$AGENT_HOST" "$AGENT_PORT" <<\'PY\'',
            "import sys",
            "import time",
            "import urllib.error",
            "import urllib.request",
            "",
            "host = sys.argv[1]",
            "port = int(sys.argv[2])",
            'url = f"http://{host}:{port}/health"',
            # Cold-start on slow ARM boards can take 15-30s for uvicorn to
            # bind; provisioning after a fresh image rebuild plus pydantic
            # compilation regularly overshoots 30s. 120s gives enough head
            # room without blocking the launcher indefinitely.
            f"deadline = time.time() + {DEFAULT_AGENT_HEALTH_TIMEOUT_S}.0",
            "while time.time() < deadline:",
            "    try:",
            "        with urllib.request.urlopen(url, timeout=2.0) as response:",
            "            if response.status == 200:",
            "                sys.exit(0)",
            "    except (urllib.error.URLError, TimeoutError):",
            "        time.sleep(1.0)",
            "sys.exit(1)",
            "PY",
            "}",
            "",
            'log_step "Preparing install directories at $INSTALL_ROOT"',
            'mkdir -p "$INSTALL_ROOT" "$OVERLAY_DIR"',
            'log_step "Creating Python virtual environment at $AGENT_VENV_PATH"',
            'python3 -m venv "$AGENT_VENV_PATH"',
            'log_step "Upgrading pip in agent virtual environment"',
            '"$AGENT_VENV_PATH/bin/pip" install --upgrade pip',
            'log_step "Locating PYNQ runtime interpreter"',
            "if detect_pynq_runtime; then",
            '  log_step "Detected canonical PYNQ runtime at $EFFECTIVE_PYNQ_PYTHON; skipping isolated venv"',
            "else",
            '  log_step "Canonical PYNQ runtime unavailable at $CANONICAL_PYNQ_PYTHON"',
            '  log_step "Creating isolated PYNQ virtual environment at $PYNQ_VENV_PATH"',
            '  python3 -m venv "$PYNQ_VENV_PATH"',
            '  log_step "Upgrading pip in PYNQ virtual environment"',
            '  "$PYNQ_VENV_PATH/bin/pip" install --upgrade pip',
            '  log_step "Installing pynq runtime dependency into isolated environment"',
            '  "$PYNQ_VENV_PATH/bin/pip" install --upgrade pynq',
            '  EFFECTIVE_PYNQ_PYTHON="$PYNQ_VENV_PATH/bin/python"',
            '  PYNQ_RUNTIME_SOURCE="isolated"',
            "fi",
            'log_step "Force-reinstalling Neurochip PYNQ agent wheel $WHEEL_NAME"',
            '"$AGENT_VENV_PATH/bin/pip" install --force-reinstall --no-deps "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            'AGENT_PACKAGE_VERSION="$(',
            "  \"$AGENT_VENV_PATH/bin/python\" - <<'PY'",
            "from importlib import metadata",
            "try:",
            '    print(metadata.version("neurochip"))',
            "except metadata.PackageNotFoundError:",
            '    print("")',
            "PY",
            ')"',
            'log_step "Checking passwordless sudo access for system service install"',
            "if sudo -n true >/dev/null 2>&1; then",
            '  log_step "Passwordless sudo available; installing systemd service"',
            '  write_install_status "systemd" "Runtime installed with systemd auto-start."',
            '  log_step "Staging systemd unit for $SERVICE_NAME.service with PYNQ runtime $EFFECTIVE_PYNQ_PYTHON"',
            '  sed "s|^Environment=NEUROCHIP_PYNQ_PYTHON=.*|Environment=NEUROCHIP_PYNQ_PYTHON=$EFFECTIVE_PYNQ_PYTHON|" \\',
            '    "$BUNDLE_DIR/systemd/$SERVICE_NAME.service" > "/tmp/$SERVICE_NAME.service"',
            '  chmod 0644 "/tmp/$SERVICE_NAME.service"',
            '  log_step "Installing systemd unit into /etc/systemd/system"',
            '  sudo -n mv "/tmp/$SERVICE_NAME.service" "/etc/systemd/system/$SERVICE_NAME.service"',
            '  log_step "Reloading systemd daemon"',
            "  sudo -n systemctl daemon-reload",
            '  log_step "Enabling $SERVICE_NAME.service"',
            '  sudo -n systemctl enable "$SERVICE_NAME.service"',
            '  log_step "Restarting $SERVICE_NAME.service"',
            '  sudo -n systemctl restart "$SERVICE_NAME.service"',
            "else",
            '  log_step "Passwordless sudo unavailable; falling back to user-space runtime install"',
            '  write_install_status "user-space" "Runtime installed in user space; the launcher can start and restart it, but it will not come back automatically after a board reboot without privileged setup."',
            f"  {stop_command}",
            f"  {launch_command}",
            "fi",
            'log_step "Waiting for runtime health endpoint"',
            "wait_for_health",
            'printf "INSTALL_STATUS_JSON=%s\\n" "$(cat "$INSTALL_STATUS_PATH")"',
            'log_step "Install script completed successfully"',
            "",
        ]
    )


def _overlay_manifest(
    *,
    overlay_version: str,
    overlay_dir: str,
) -> dict[str, Any]:
    return {
        "overlayVersion": overlay_version,
        "overlayDirectory": overlay_dir,
        "requiredFiles": ["snn_overlay.bit", "snn_overlay.hwh", "overlay_manifest.json"],
        "agentRuntime": "neurochip-pynq-agent",
    }


def build_pynq_agent_bundle(
    output_dir: Path,
    *,
    overlay_version: str = "dev",
    repo_root: Path | None = None,
    wheel_path: Path | None = None,
    install_root: str = DEFAULT_REMOTE_INSTALL_ROOT,
    agent_venv_path: str = DEFAULT_REMOTE_VENV_PATH,
    pynq_venv_path: str = DEFAULT_REMOTE_PYNQ_VENV_PATH,
    overlay_dir: str = DEFAULT_REMOTE_OVERLAY_DIR,
    service_name: str = DEFAULT_REMOTE_SERVICE_NAME,
) -> dict[str, Any]:
    """Build a local bundle of files needed for remote board provisioning."""
    root = repo_root or _repo_root()
    bundle_dir = output_dir.resolve()
    wheel = (wheel_path or ensure_agent_wheel(root)).resolve()

    wheels_dir = bundle_dir / "wheels"
    systemd_dir = bundle_dir / "systemd"
    overlays_dir = bundle_dir / "overlays"
    for directory in (wheels_dir, systemd_dir, overlays_dir):
        directory.mkdir(parents=True, exist_ok=True)

    copied_wheel = wheels_dir / wheel.name
    shutil.copy2(wheel, copied_wheel)

    manifest = _overlay_manifest(
        overlay_version=overlay_version,
        overlay_dir=overlay_dir,
    )
    (bundle_dir / "bundle-manifest.json").write_text(
        json.dumps(
            {
                "serviceName": service_name,
                "installRoot": install_root,
                "venvPath": agent_venv_path,
                "agentVenvPath": agent_venv_path,
                "pynqVenvPath": pynq_venv_path,
                "installStatusPath": f"{install_root}/install-status.json",
                "overlay": manifest,
                "wheel": copied_wheel.name,
            },
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    (bundle_dir / "requirements-pynq-agent.txt").write_text(
        "pynq>=2.7\n",
        encoding="utf-8",
    )
    (systemd_dir / f"{service_name}.service").write_text(
        _systemd_unit_text(
            service_name=service_name,
            install_root=install_root,
            agent_venv_path=agent_venv_path,
            pynq_python_path=f"{pynq_venv_path}/bin/python",
            install_status_path=f"{install_root}/install-status.json",
            overlay_dir=overlay_dir,
        ),
        encoding="utf-8",
    )
    install_script = bundle_dir / "install-pynq-agent.sh"
    install_script.write_text(
        _install_script_text(
            install_root=install_root,
            agent_venv_path=agent_venv_path,
            pynq_venv_path=pynq_venv_path,
            overlay_dir=overlay_dir,
            service_name=service_name,
            wheel_name=copied_wheel.name,
        ),
        encoding="utf-8",
    )
    install_script.chmod(install_script.stat().st_mode | stat.S_IXUSR)
    (overlays_dir / "pynq_overlay_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    (bundle_dir / "README.md").write_text(
        "\n".join(
            [
                "# NeuroChip PYNQ Agent Bundle",
                "",
                "This bundle is uploaded by the launcher control service to provision a stock PYNQ image.",
                "",
                "Contents:",
                f"- wheels/{copied_wheel.name}",
                "- systemd/neurochip-pynq-agent.service",
                "- install-pynq-agent.sh",
                "- overlays/pynq_overlay_manifest.json",
                "",
            ]
        ),
        encoding="utf-8",
    )
    return {
        "bundleDir": str(bundle_dir),
        "wheelName": copied_wheel.name,
        "overlayManifest": manifest,
        "serviceName": service_name,
        "installRoot": install_root,
        "venvPath": agent_venv_path,
        "agentVenvPath": agent_venv_path,
        "pynqVenvPath": pynq_venv_path,
        "overlayDir": overlay_dir,
    }
