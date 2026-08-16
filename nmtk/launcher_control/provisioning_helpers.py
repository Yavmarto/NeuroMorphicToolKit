"""Launcher-owned provisioning bundle helpers.

These helpers intentionally mirror the minimal Neurochip remote-install
artifacts the launcher needs so launcher runtime behavior does not depend on
importing or loading checked-out Neurochip package internals.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import stat
import subprocess
from pathlib import Path
from typing import Any

from .runtime_artifact import inspect_neurochip_runtime_artifact

# These module-level constants are secondary fallbacks for callers that invoke
# build_pynq_agent_bundle() or build_akida_host_bundle() directly without passing
# manifest-owned values.  Within the normal launcher server flow, server.py always
# derives these values from the typed NeurochipLauncherRuntimeContract loaded from
# modules.json before calling the bundle helpers, so these constants are never hit
# on the hot path.  Do not treat them as authoritative defaults for new code;
# use _load_neurochip_launcher_runtime_contract() from server.py instead.
DEFAULT_REMOTE_INSTALL_ROOT = "/opt/neurochip-pynq-agent"
DEFAULT_REMOTE_VENV_PATH = f"{DEFAULT_REMOTE_INSTALL_ROOT}/venv"
DEFAULT_REMOTE_PYNQ_VENV_PATH = f"{DEFAULT_REMOTE_INSTALL_ROOT}/pynq-venv"
DEFAULT_REMOTE_OVERLAY_DIR = f"{DEFAULT_REMOTE_INSTALL_ROOT}/overlays"
DEFAULT_REMOTE_SERVICE_NAME = "neurochip-pynq-agent"
DEFAULT_CANONICAL_PYNQ_PYTHON = "/usr/local/share/pynq-venv/bin/python"
DEFAULT_XILINX_XRT_PATH = "/usr"
DEFAULT_BOARD_NAME = "Pynq-Z2"
DEFAULT_AGENT_HEALTH_TIMEOUT_S = 120

DEFAULT_AKIDA_INSTALL_ROOT = "/opt/neurochip-akida-host"
DEFAULT_AKIDA_SERVICE_USER = "neurochip"
DEFAULT_AKIDA_VENV_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/venv"
DEFAULT_AKIDA_RUNTIME_SERVICE = "neurochip"
DEFAULT_AKIDA_CONTROL_SERVICE = "neurochip-akida-control"
DEFAULT_AKIDA_RUNTIME_PORT = 8002
DEFAULT_AKIDA_CONTROL_PORT = 8091
DEFAULT_AKIDA_TOKEN_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/credentials/api-token"
DEFAULT_AKIDA_INSTALL_STATUS_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/install-status.json"
# The BrainChip SDK publishes wheels for CPython 3.10-3.12 only, and TensorFlow
# ships none at all for 3.13+. Mirrors `akidaRuntime.pythonRange` in
# nmtk/neuro_toolkit/assets/modules.json, which stays the source of truth.
DEFAULT_AKIDA_PYTHON_MIN = (3, 10)
DEFAULT_AKIDA_PYTHON_MAX = (3, 13)
DEFAULT_AKIDA_PYTHON_RANGE = ">=3.10,<3.13"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _latest_wheel(dist_dir: Path) -> Path | None:
    wheels = sorted(
        dist_dir.glob("neurochip-*.whl"),
        key=lambda path: path.stat().st_mtime,
    )
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
        raise RuntimeError(
            result.stderr.strip() or result.stdout.strip() or "poetry build failed"
        )

    wheel = _latest_wheel(dist_dir)
    if wheel is None:
        raise RuntimeError("poetry build completed without producing a wheel")
    return wheel


def _shell_value(value: str, *, shell_safe_values: bool) -> str:
    return value if shell_safe_values else shlex.quote(value)


def build_pynq_agent_match_pattern(agent_executable: str) -> str:
    """Return a ``pkill -f``/``pgrep -f`` pattern that cannot match its own carrier.

    ``-f`` matches whole command lines, so when the pattern travels inside the very
    command line that runs it — an inline ``ssh host 'pkill -f /path/agent; … start …'``
    — it matches the remote shell as well as the agent, and the stop step kills the
    process that was about to do the restart. Bracketing the first character of the
    executable name keeps the regex matching the real process (whose command line is
    ``…/neurochip-pynq-agent``) while the literal ``…/[n]eurochip-pynq-agent`` sitting in
    a carrier's argv does not match it.

    Executables written as shell expressions (the install-script call sites, where the
    pattern lives in a file and never appears in a command line) are returned unchanged.
    """
    head, separator, name = agent_executable.rpartition("/")
    if not name or not name[0].isalnum():
        return agent_executable
    return f"{head}{separator}[{name[0]}]{name[1:]}"


def build_pynq_agent_stop_command(
    *,
    agent_executable: str,
    shell_safe_values: bool = False,
) -> str:
    """Build the shell command that stops a running user-space PYNQ agent."""
    pattern = _shell_value(
        build_pynq_agent_match_pattern(agent_executable),
        shell_safe_values=shell_safe_values,
    )
    return f"pkill -f {pattern} >/dev/null 2>&1 || true"


def build_pynq_user_space_agent_launch_command(
    *,
    agent_executable: str,
    pynq_python_path: str,
    install_status_path: str,
    overlay_dir: str,
    runtime_log_path: str,
    shell_safe_values: bool = False,
    xilinx_xrt_path: str = DEFAULT_XILINX_XRT_PATH,
    board_name: str = DEFAULT_BOARD_NAME,
) -> str:
    """Build a durable shell command for launching the PYNQ agent in user space."""
    env_assignments = " ".join(
        [
            f"NEUROCHIP_PYNQ_PYTHON={_shell_value(pynq_python_path, shell_safe_values=shell_safe_values)}",
            'NEUROCHIP_PYNQ_INSTALL_MODE="user-space"',
            f"NEUROCHIP_PYNQ_INSTALL_STATUS_PATH={_shell_value(install_status_path, shell_safe_values=shell_safe_values)}",
            f"NEUROCHIP_PYNQ_OVERLAY_DIR={_shell_value(overlay_dir, shell_safe_values=shell_safe_values)}",
            # The same XRT environment the systemd unit injects. The stock image
            # sets these in /etc/profile.d/xrt_setup.sh, which a detached
            # `setsid sh -c` never sources — without them pynq reports "No devices
            # found, is the XRT environment sourced?" and enumerates nothing, so a
            # user-space agent could never see the board it is running on.
            f"XILINX_XRT={xilinx_xrt_path}",
            f"LD_LIBRARY_PATH={xilinx_xrt_path}/lib:/usr/lib:/usr/local/lib",
            f"BOARD={board_name}",
        ]
    )
    executable = _shell_value(agent_executable, shell_safe_values=shell_safe_values)
    runtime_log = _shell_value(runtime_log_path, shell_safe_values=shell_safe_values)
    launch_payload = (
        f"exec env {env_assignments} {executable} >{runtime_log} 2>&1 </dev/null"
    )
    quoted_payload = shlex.quote(launch_payload)
    return (
        "if command -v setsid >/dev/null 2>&1; then "
        f"setsid sh -c {quoted_payload} >/dev/null 2>&1 & "
        "else "
        f"nohup sh -c {quoted_payload} >/dev/null 2>&1 & "
        "fi"
    )


def _pynq_systemd_unit_text(
    *,
    service_name: str,
    install_root: str,
    agent_venv_path: str,
    agent_executable_name: str,
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
            f"Environment=XILINX_XRT={xilinx_xrt_path}",
            f"Environment=LD_LIBRARY_PATH={xilinx_xrt_path}/lib:/usr/lib:/usr/local/lib",
            (
                f"Environment=PATH={xilinx_xrt_path}/bin:/usr/local/sbin:"
                "/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
            ),
            f"Environment=BOARD={board_name}",
            f"ExecStart={agent_venv_path}/bin/{agent_executable_name}",
            "Restart=on-failure",
            "RestartSec=5",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _pynq_install_script_text(
    *,
    install_root: str,
    agent_venv_path: str,
    pynq_venv_path: str,
    overlay_dir: str,
    service_name: str,
    agent_executable_name: str,
    install_status_path: str,
    runtime_log_path: str,
    wheel_name: str,
) -> str:
    stop_command = build_pynq_agent_stop_command(
        agent_executable='"$AGENT_VENV_PATH/bin/$AGENT_EXECUTABLE_NAME"',
        shell_safe_values=True,
    )
    launch_command = build_pynq_user_space_agent_launch_command(
        agent_executable='"$AGENT_VENV_PATH/bin/$AGENT_EXECUTABLE_NAME"',
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
            f'AGENT_EXECUTABLE_NAME="${{AGENT_EXECUTABLE_NAME:-{agent_executable_name}}}"',
            f'WHEEL_NAME="${{WHEEL_NAME:-{wheel_name}}}"',
            f'INSTALL_STATUS_PATH="${{INSTALL_STATUS_PATH:-{install_status_path}}}"',
            f'RUNTIME_LOG_PATH="${{RUNTIME_LOG_PATH:-{runtime_log_path}}}"',
            'AGENT_HOST="${NEUROCHIP_PYNQ_AGENT_HOST:-127.0.0.1}"',
            'AGENT_PORT="${NEUROCHIP_PYNQ_AGENT_PORT:-8002}"',
            f'CANONICAL_PYNQ_PYTHON="${{CANONICAL_PYNQ_PYTHON:-{DEFAULT_CANONICAL_PYNQ_PYTHON}}}"',
            'EFFECTIVE_PYNQ_PYTHON=""',
            'PYNQ_RUNTIME_SOURCE="unknown"',
            'AGENT_PACKAGE_VERSION=""',
            'AGENT_WHEEL_NAME="$WHEEL_NAME"',
            "",
            "write_install_status() {",
            '  python3 - "$INSTALL_STATUS_PATH" "$1" "$2" "$SERVICE_NAME" "$AGENT_VENV_PATH" "$PYNQ_VENV_PATH" "$RUNTIME_LOG_PATH" "$EFFECTIVE_PYNQ_PYTHON" "$PYNQ_RUNTIME_SOURCE" "$AGENT_PACKAGE_VERSION" "$AGENT_WHEEL_NAME" <<'
            "'"
            "PY"
            "'"
            "",
            "import json",
            "import sys",
            "from pathlib import Path",
            "",
            "payload = {",
            '    "installMode": sys.argv[2],',
            '    "message": sys.argv[3],',
            '    "serviceName": sys.argv[4],',
            '    "agentVenvPath": sys.argv[5],',
            '    "pynqVenvPath": sys.argv[6],',
            '    "runtimeLogPath": sys.argv[7],',
            '    "effectivePynqPython": sys.argv[8],',
            '    "pynqRuntimeSource": sys.argv[9],',
            '    "agentPackageVersion": sys.argv[10],',
            '    "agentWheelName": sys.argv[11],',
            '    "autoStartSupported": sys.argv[2] == "systemd",',
            "}",
            'Path(sys.argv[1]).write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")',
            "PY",
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
            # A board can correct its wall clock by several minutes after it
            # reaches the network.  Use monotonic elapsed time so that cannot
            # stretch this bounded health wait.
            "started_at = time.monotonic()",
            f"deadline = started_at + {DEFAULT_AGENT_HEALTH_TIMEOUT_S}.0",
            "next_progress = started_at + 15.0",
            "while time.monotonic() < deadline:",
            "    try:",
            "        with urllib.request.urlopen(url, timeout=2.0) as response:",
            "            if response.status == 200:",
            "                sys.exit(0)",
            "    except (urllib.error.URLError, TimeoutError):",
            "        pass",
            "    now = time.monotonic()",
            "    if now >= next_progress:",
            '        print(f"[install-pynq-agent] Still waiting for runtime health ({now - started_at:.0f}s elapsed)", flush=True)',
            "        next_progress += 15.0",
            "    time.sleep(1.0)",
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
            # The agent venv starts empty.  Installing the wheel with --no-deps
            # leaves FastAPI, uvicorn, and the other runtime requirements absent,
            # so the detached agent exits before its /health endpoint can bind.
            '"$AGENT_VENV_PATH/bin/pip" install --force-reinstall "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
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
            "if sudo -n true >/dev/null 2>&1; then",
            '  printf "INSTALL_STATUS_JSON=%s\\n" "$(sudo -n cat "$INSTALL_STATUS_PATH")"',
            "else",
            '  printf "INSTALL_STATUS_JSON=%s\\n" "$(cat "$INSTALL_STATUS_PATH")"',
            "fi",
            'log_step "Install script completed successfully"',
            "",
        ]
    )


def _overlay_manifest(
    *,
    overlay_version: str,
    overlay_dir: str,
    agent_runtime: str,
) -> dict[str, Any]:
    return {
        "overlayVersion": overlay_version,
        "overlayDirectory": overlay_dir,
        "requiredFiles": [
            "snn_overlay.bit",
            "snn_overlay.hwh",
            "overlay_manifest.json",
        ],
        "agentRuntime": agent_runtime,
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
    agent_executable_name: str = DEFAULT_REMOTE_SERVICE_NAME,
    install_status_path: str | None = None,
    runtime_log_path: str | None = None,
) -> dict[str, Any]:
    """Build a local bundle of files needed for remote PYNQ provisioning."""
    root = repo_root or _repo_root()
    bundle_dir = output_dir.resolve()
    wheel = (wheel_path or ensure_agent_wheel(root)).resolve()
    resolved_install_status_path = (
        install_status_path or f"{install_root}/install-status.json"
    )
    resolved_runtime_log_path = runtime_log_path or f"{install_root}/runtime.log"

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
        agent_runtime=agent_executable_name,
    )
    (bundle_dir / "bundle-manifest.json").write_text(
        json.dumps(
            {
                "serviceName": service_name,
                "installRoot": install_root,
                "venvPath": agent_venv_path,
                "agentVenvPath": agent_venv_path,
                "pynqVenvPath": pynq_venv_path,
                "installStatusPath": resolved_install_status_path,
                "runtimeLogPath": resolved_runtime_log_path,
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
        _pynq_systemd_unit_text(
            service_name=service_name,
            install_root=install_root,
            agent_venv_path=agent_venv_path,
            agent_executable_name=agent_executable_name,
            pynq_python_path=f"{pynq_venv_path}/bin/python",
            install_status_path=resolved_install_status_path,
            overlay_dir=overlay_dir,
        ),
        encoding="utf-8",
    )
    install_script = bundle_dir / "install-pynq-agent.sh"
    install_script.write_text(
        _pynq_install_script_text(
            install_root=install_root,
            agent_venv_path=agent_venv_path,
            pynq_venv_path=pynq_venv_path,
            overlay_dir=overlay_dir,
            service_name=service_name,
            agent_executable_name=agent_executable_name,
            install_status_path=resolved_install_status_path,
            runtime_log_path=resolved_runtime_log_path,
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
        "installStatusPath": resolved_install_status_path,
        "runtimeLogPath": resolved_runtime_log_path,
    }


def _akida_runtime_unit_text(
    *,
    install_root: str,
    venv_path: str,
    service_user: str,
    runtime_service_name: str,
    runtime_port: int,
) -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=Neurochip Akida runtime",
            "After=network-online.target",
            "Wants=network-online.target",
            "",
            "[Service]",
            "Type=simple",
            f"User={service_user}",
            f"Group={service_user}",
            f"WorkingDirectory={install_root}",
            f"EnvironmentFile={install_root}/env/{runtime_service_name}.env",
            (
                f"ExecStart={venv_path}/bin/uvicorn neurochip.app.main:app "
                f"--host 0.0.0.0 --port {runtime_port}"
            ),
            "Restart=on-failure",
            "RestartSec=5",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _akida_control_unit_text(
    *,
    install_root: str,
    venv_path: str,
    service_user: str,
    control_service_name: str,
) -> str:
    return "\n".join(
        [
            "[Unit]",
            "Description=Neurochip Akida host control service",
            "After=network-online.target",
            "Wants=network-online.target",
            "",
            "[Service]",
            "Type=simple",
            f"User={service_user}",
            f"Group={service_user}",
            f"WorkingDirectory={install_root}",
            f"EnvironmentFile={install_root}/env/{control_service_name}.env",
            f"ExecStart={venv_path}/bin/python {install_root}/bin/akida_remote_control_service.py",
            "Restart=on-failure",
            "RestartSec=5",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "",
        ]
    )


def _remote_control_script_text() -> str:
    return r"""#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import platform
import subprocess
import sys
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONTROL_HOST = os.getenv("NEUROCHIP_REMOTE_CONTROL_HOST", "0.0.0.0")
CONTROL_PORT = int(os.getenv("NEUROCHIP_REMOTE_CONTROL_PORT", "8091"))
API_KEY = os.getenv("NEUROCHIP_REMOTE_CONTROL_API_KEY", "").strip()
LOCAL_NEUROCHIP_BASE_URL = os.getenv("LOCAL_NEUROCHIP_BASE_URL", "http://127.0.0.1:8002").rstrip("/")
INSTALL_STATUS_PATH = Path(
    os.getenv(
        "NEUROCHIP_INSTALL_STATUS_PATH",
        "/opt/neurochip-akida-host/install-status.json",
    )
)


def _load_install_status() -> dict[str, object]:
    try:
        return json.loads(INSTALL_STATUS_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _run_probe(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except FileNotFoundError:
        return ""
    except subprocess.TimeoutExpired:
        return "command timed out"
    if result.returncode != 0:
        return (result.stderr or result.stdout).strip()
    return result.stdout.strip()


AKIDA_PCI_VENDOR = "0x1e7c"
AKIDA_PCI_DEVICE = "0xbca1"
PCI_DEVICES_ROOT = Path("/sys/bus/pci/devices")


def _sysfs_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


# Reports whether the AKD1000 is fitted, bound, and answering.
#
# Everything here is an unprivileged sysfs read. The PCI COMMAND register
# lives at byte offset 4, inside the first 64 bytes of config space, which
# are world-readable - so no sudo and no extra packages. lspci was already
# being captured next to this and never parsed, which is why a missing board,
# a missing driver, and a wedged board all reported the same thing.
#
# A wedged board is the case worth naming: the driver stays bound and the
# kernel still reports enable=1/D0, but COMMAND goes to 0, clearing Memory
# Space Enable. Every register read then times out inside the SDK and
# surfaces as an errno the user cannot act on.
def _probe_akida_device() -> dict[str, object]:
    probe: dict[str, object] = {
        "present": False,
        "bdf": "",
        "driver": "",
        "memorySpaceEnabled": None,
    }
    try:
        entries = sorted(PCI_DEVICES_ROOT.iterdir())
    except OSError:
        return probe
    for entry in entries:
        if _sysfs_text(entry / "vendor").lower() != AKIDA_PCI_VENDOR:
            continue
        if _sysfs_text(entry / "device").lower() != AKIDA_PCI_DEVICE:
            continue
        probe["present"] = True
        probe["bdf"] = entry.name
        driver_link = entry / "driver"
        if driver_link.is_symlink() or driver_link.exists():
            probe["driver"] = os.path.basename(os.path.realpath(driver_link))
        try:
            with open(entry / "config", "rb") as config:
                header = config.read(6)
            if len(header) >= 6:
                command = int.from_bytes(header[4:6], "little")
                probe["memorySpaceEnabled"] = bool(command & 0x2)
        except OSError:
            pass
        break
    return probe


DMA_TIMEOUT_MARKER = "DMA wait completion timed out"
ASPM_UNCONTROLLED_MARKER = "can't disable ASPM"


# The kernel log, or "" when this account may not read it. Provisioning puts
# the service user in systemd-journal so it usually can, but an install that
# predates that, or a host without systemd, must degrade rather than lie.
def _kernel_log_text() -> str:
    for command in (
        ["journalctl", "--dmesg", "--boot", "--no-pager"],
        ["dmesg"],
    ):
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and result.stdout:
            return result.stdout
    return ""


# Correctable PCIe errors counted by the kernel for this device. A healthy
# link sits at zero; a rising count means the board and the slot are not
# talking cleanly. Unprivileged sysfs read, absent on kernels without AER.
def _correctable_link_errors(probe: dict[str, object]) -> int | None:
    bdf = str(probe.get("bdf") or "")
    if not bdf:
        return None
    text = _sysfs_text(PCI_DEVICES_ROOT / bdf / "aer_dev_correctable")
    for line in text.splitlines():
        name, _, value = line.partition(" ")
        if name.strip() == "TOTAL_ERR_COR":
            try:
                return int(value.strip())
            except ValueError:
                return None
    return None


# Said when the board is fitted, bound, and its registers are enabled, yet the
# SDK still fell back to the simulator. Nothing above catches that: every cheap
# check passes and the fault only shows up once data moves.
def _akida_unresponsive_message(probe: dict[str, object]) -> str:
    opening = (
        "The Akida board is fitted and its driver is loaded, but it stops "
        "responding as soon as data is sent to it, so the software simulator "
        "is being used instead. Switch the host fully off and on again - a "
        "restart is not enough."
    )
    kernel_log = _kernel_log_text()
    if kernel_log and ASPM_UNCONTROLLED_MARKER in kernel_log:
        return (
            f"{opening} If that does not help: this machine does not let the "
            "driver turn PCIe power saving off, which is the usual cause. Turn "
            "PCIe power management (ASPM) off for the board's slot in the "
            "machine's BIOS."
        )
    if kernel_log and DMA_TIMEOUT_MARKER in kernel_log:
        return f"{opening} The driver reports that transfers to the board time out."
    errors = _correctable_link_errors(probe)
    if errors:
        return (
            f"{opening} The connection to the board has logged {errors} errors, "
            "so it may also be worth reseating the card in its slot."
        )
    return opening


# Plain-English remedy for a hardware fault, or "" when the board looks fine.
# Returning "" deliberately means "not a board problem" so the caller keeps
# whatever the SDK said - this must not mask genuine SDK faults.
#
# usb_text is the already-collected lsusb output. The probe only knows about
# PCI, and BrainChip also ships USB Akida devices, so "absent from PCI" is not
# proof of "no board" - claiming it would be a confident lie to a USB user.
def _akida_device_message(
    probe: dict[str, object],
    usb_text: str = "",
    runtime_target: str = "",
) -> str:
    if not probe.get("present"):
        haystack = usb_text.lower()
        if "brainchip" in haystack or "akida" in haystack:
            return ""
        return "No Akida board was found in this host."
    if not probe.get("driver"):
        return "An Akida board is fitted but its PCIe driver is not loaded."
    if probe.get("memorySpaceEnabled") is False:
        return (
            "The Akida board has stopped responding. Switch the host fully off "
            "and on again - a restart is not enough."
        )
    if runtime_target in {"akd1000_simulator", "software_fallback"}:
        return _akida_unresponsive_message(probe)
    return ""


def _local_json(path: str) -> tuple[int | None, dict[str, object]]:
    request = urllib.request.Request(
        f"{LOCAL_NEUROCHIP_BASE_URL}{path}",
        headers={
            "Content-Type": "application/json",
            **({"X-API-Key": API_KEY} if API_KEY else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15.0) as response:
            body = response.read().decode("utf-8")
            decoded = json.loads(body) if body else {}
            return response.status, decoded if isinstance(decoded, dict) else {}
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read().decode("utf-8"))
            if isinstance(payload, dict):
                return exc.code, payload
        except json.JSONDecodeError:
            pass
        return exc.code, {"error": f"HTTP {exc.code}"}
    except Exception as exc:
        return None, {"error": str(exc)}


def _doctor_payload() -> dict[str, object]:
    install_status = _load_install_status()
    runtime_health_status, runtime_health = _local_json("/health")
    runtime_status_status, runtime_status = _local_json("/api/neurochip/akida/status")
    akida_device = _probe_akida_device()
    lspci_text = _run_probe(["lspci"])
    lsusb_text = _run_probe(["lsusb"])

    sdk_status = str(runtime_status.get("sdk_status") or "").strip().lower()
    runtime_target = str(runtime_status.get("runtime_target") or "").strip().lower()
    sdk_available = runtime_status.get("sdk_available") is True
    sdk_issues = runtime_status.get("sdk_issues")
    if not isinstance(sdk_issues, list):
        sdk_issues = []
    # Needs runtime_target: a board that passes every static check and still
    # ends up on the simulator is only visible by comparing the two.
    device_message = _akida_device_message(akida_device, lsusb_text, runtime_target)
    if runtime_health_status != 200:
        preflight_status = "failed"
        preflight_message = "Neurochip runtime health check failed"
    elif runtime_target == "hardware" and (
        sdk_status == "deployable" or (sdk_available and not sdk_issues)
    ):
        preflight_status = "ok"
        preflight_message = "Akida hardware runtime is ready."
    elif runtime_status_status == 200:
        preflight_status = "degraded"
        # A hardware verdict wins over sdk_issue_detail: when the board is
        # absent, unbound, or wedged, the SDK only knows it got an errno back
        # and reports a register address the user cannot act on. The raw text
        # is still carried in the payload's own sdk_issue_detail key.
        preflight_message = device_message or str(
            runtime_status.get("sdk_issue_detail")
            or runtime_status.get("error")
            or "Optional Akida capability is degraded."
        )
    else:
        preflight_status = "failed"
        preflight_message = str(
            runtime_status.get("error") or "Akida runtime diagnostics are unavailable."
        )

    return {
        "host": {
            "platform": platform.platform(),
            "pythonVersion": platform.python_version(),
            "machine": platform.machine(),
        },
        "hardwareProbe": {
            "lspci": lspci_text,
            "lsusb": lsusb_text,
            "akidaDevice": akida_device,
            "correctableLinkErrors": _correctable_link_errors(akida_device),
        },
        "services": {
            "runtimeHealthStatus": runtime_health_status,
            "runtimeHealth": runtime_health,
            "runtimeStatusHttpStatus": runtime_status_status,
        },
        "installStatus": install_status,
        "runtimeStatus": runtime_status,
        "preflight": {
            "preflight_status": preflight_status,
            "preflight_message": preflight_message,
            "runtime_target": runtime_status.get("runtime_target"),
            "sdk_status": runtime_status.get("sdk_status"),
            "sdk_available": runtime_status.get("sdk_available"),
            "sdk_issues": runtime_status.get("sdk_issues"),
            "sdk_issue_detail": runtime_status.get("sdk_issue_detail"),
            "environment_checks": runtime_status.get("environment_checks"),
            "device_info": runtime_status.get("device_info"),
            "physicalHardwareReady": preflight_status == "ok",
        },
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "AkidaRemoteControl/0.1"

    def _send(self, status: HTTPStatus, payload: dict[str, object]) -> None:
        encoded = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _require_api_key(self) -> bool:
        if not API_KEY:
            return True
        provided = self.headers.get("X-API-Key", "")
        if provided == API_KEY:
            return True
        self._send(
            HTTPStatus.UNAUTHORIZED,
            {"detail": "Invalid or missing API Key"},
        )
        return False

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send(HTTPStatus.OK, {"status": "healthy"})
            return
        if not self._require_api_key():
            return
        if self.path == "/api/remote-akida/doctor":
            self._send(HTTPStatus.OK, _doctor_payload())
            return
        self._send(HTTPStatus.NOT_FOUND, {"detail": "Not found"})

    def log_message(self, format: str, *args: object) -> None:
        sys.stdout.write(f"[akida-remote-control] {format % args}\n")
        sys.stdout.flush()


def main() -> int:
    server = ThreadingHTTPServer((CONTROL_HOST, CONTROL_PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
"""


def _parse_python_range(python_range: str) -> tuple[tuple[int, int], tuple[int, int]]:
    """Turn a manifest `pythonRange` like ``>=3.10,<3.13`` into inclusive/exclusive bounds.

    Parsed here rather than in bash so the generated script only ever asks a
    candidate interpreter about itself, which is exact. Anything unparseable
    falls back to the documented Akida range instead of failing the build — a
    malformed manifest must not make provisioning impossible.
    """
    minimum = DEFAULT_AKIDA_PYTHON_MIN
    maximum = DEFAULT_AKIDA_PYTHON_MAX
    for clause in str(python_range or "").split(","):
        clause = clause.strip()
        match = re.match(r"^(>=|<)\s*(\d+)\.(\d+)", clause)
        if not match:
            continue
        operator, major, minor = match.group(1), int(match.group(2)), int(match.group(3))
        if operator == ">=":
            minimum = (major, minor)
        else:
            maximum = (major, minor)
    return minimum, maximum


def _akida_install_script_text(
    *,
    install_root: str,
    service_user: str,
    venv_path: str,
    runtime_service_name: str,
    control_service_name: str,
    runtime_port: int,
    control_port: int,
    token_path: str,
    install_status_path: str,
    wheel_name: str,
    artifact_version: str,
    artifact_sha256: str,
    required_packages: list[str],
    python_range: str = DEFAULT_AKIDA_PYTHON_RANGE,
    standalone_python: dict[str, Any] | None = None,
) -> str:
    package_install = " ".join(shlex.quote(package) for package in required_packages)
    python_min, python_max = _parse_python_range(python_range)
    range_label = f">={python_min[0]}.{python_min[1]},<{python_max[0]}.{python_max[1]}"
    standalone = standalone_python or {}
    standalone_version = str(standalone.get("version") or "").strip()
    standalone_url = str(standalone.get("url") or "").strip()
    standalone_sha256 = str(standalone.get("sha256") or "").strip()
    standalone_arch = str(standalone.get("architecture") or "x86_64").strip()
    # Asked of the interpreter itself — no version parsing in shell.
    version_probe = (
        f"import sys; sys.exit(0 if {python_min} <= sys.version_info[:2] < "
        f"{python_max} else 1)"
    )
    return "\n".join(
        [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "",
            'log_step() { printf "[install-akida-host] %s\\n" "$1"; }',
            "sudo_cmd() {",
            '  if [ -n "${NMTK_AKIDA_SUDO_PASSWORD:-}" ]; then',
            '    printf "%s\\n" "$NMTK_AKIDA_SUDO_PASSWORD" | sudo -S -p "" "$@"',
            "  else",
            '    sudo -n "$@"',
            "  fi",
            "}",
            "sudo_available() {",
            '  if [ -n "${NMTK_AKIDA_SUDO_PASSWORD:-}" ]; then',
            '    printf "%s\\n" "$NMTK_AKIDA_SUDO_PASSWORD" | sudo -S -p "" true >/dev/null 2>&1',
            "  else",
            "    sudo -n true >/dev/null 2>&1",
            "  fi",
            "}",
            "write_sudo_file() {",
            '  target_path="$1"',
            '  mode="$2"',
            '  owner="$3"',
            '  tmp_file="$(mktemp)"',
            '  cat > "$tmp_file"',
            '  if [ -n "$owner" ]; then',
            '    owner_user="${owner%%:*}"',
            '    owner_group="${owner##*:}"',
            '    sudo_cmd install -D -m "$mode" -o "$owner_user" -g "$owner_group" "$tmp_file" "$target_path"',
            "  else",
            '    sudo_cmd install -D -m "$mode" "$tmp_file" "$target_path"',
            "  fi",
            '  rm -f "$tmp_file"',
            "}",
            "",
            'BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
            "# The steps below drop privileges with sudo -u, which keeps the",
            "# current directory. Python refuses to start when it cannot read",
            "# that directory, so move somewhere every account can reach. This",
            "# must come after BUNDLE_DIR is resolved to an absolute path.",
            "cd /",
            f'INSTALL_ROOT="${{INSTALL_ROOT:-{install_root}}}"',
            f'SERVICE_USER="${{SERVICE_USER:-{service_user}}}"',
            f'VENV_PATH="${{VENV_PATH:-{venv_path}}}"',
            f'RUNTIME_SERVICE_NAME="${{RUNTIME_SERVICE_NAME:-{runtime_service_name}}}"',
            f'CONTROL_SERVICE_NAME="${{CONTROL_SERVICE_NAME:-{control_service_name}}}"',
            f'RUNTIME_PORT="${{RUNTIME_PORT:-{runtime_port}}}"',
            f'CONTROL_PORT="${{CONTROL_PORT:-{control_port}}}"',
            f'TOKEN_PATH="${{TOKEN_PATH:-{token_path}}}"',
            f'INSTALL_STATUS_PATH="${{INSTALL_STATUS_PATH:-{install_status_path}}}"',
            'ENV_DIR="${INSTALL_ROOT}/env"',
            'BIN_DIR="${INSTALL_ROOT}/bin"',
            'CREDENTIAL_DIR="$(dirname "$TOKEN_PATH")"',
            f'WHEEL_NAME="${{WHEEL_NAME:-{wheel_name}}}"',
            f'ARTIFACT_VERSION="${{ARTIFACT_VERSION:-{artifact_version}}}"',
            f'ARTIFACT_SHA256="${{ARTIFACT_SHA256:-{artifact_sha256}}}"',
            f'PYTHON_RANGE_LABEL="{range_label}"',
            f'STANDALONE_PYTHON_VERSION="{standalone_version}"',
            f'STANDALONE_PYTHON_URL="{standalone_url}"',
            f'STANDALONE_PYTHON_SHA256="{standalone_sha256}"',
            f'STANDALONE_PYTHON_ARCH="{standalone_arch}"',
            'MANAGED_PYTHON_ROOT="${INSTALL_ROOT}/python"',
            'MANAGED_PYTHON_BIN="${MANAGED_PYTHON_ROOT}/bin/python3"',
            # Owned by the service user. `sudo -u` does not hand over that
            # account's HOME, so without this pip caches wherever the invoking
            # login happens to point -- a directory the service user may not
            # own, and one this installer can never clean up when it goes bad.
            'PIP_CACHE_DIR="${INSTALL_ROOT}/cache/pip"',
            # Set by each install branch before select_python, because the
            # systemd branch writes into root-owned /opt while the user-space
            # fallback writes into the invoking user's own home.
            'USE_SUDO=""',
            'AKIDA_PYTHON=""',
            'RUNTIME_LOG_PATH="${INSTALL_ROOT}/runtime.log"',
            'CONTROL_LOG_PATH="${INSTALL_ROOT}/control.log"',
            'RELEASE_ID="${ARTIFACT_VERSION}-${ARTIFACT_SHA256:0:12}"',
            'RELEASES_DIR="${INSTALL_ROOT}/releases"',
            'NEXT_VENV_PATH="${RELEASES_DIR}/${RELEASE_ID}-staged-$$"',
            'CURRENT_VENV_PATH="${INSTALL_ROOT}/current"',
            'PREVIOUS_VENV_TARGET=""',
            'ACTIVATION_PENDING="0"',
            "",
            'ORIGINAL_INSTALL_ROOT="$INSTALL_ROOT"',
            'ORIGINAL_VENV_BASENAME="$(basename "$VENV_PATH")"',
            'TOKEN_PATH_SUFFIX="credentials/api-token"',
            'if [[ "$TOKEN_PATH" == "$ORIGINAL_INSTALL_ROOT/"* ]]; then',
            '  TOKEN_PATH_SUFFIX="${TOKEN_PATH#"$ORIGINAL_INSTALL_ROOT"/}"',
            "fi",
            'INSTALL_STATUS_PATH_SUFFIX="install-status.json"',
            'if [[ "$INSTALL_STATUS_PATH" == "$ORIGINAL_INSTALL_ROOT/"* ]]; then',
            '  INSTALL_STATUS_PATH_SUFFIX="${INSTALL_STATUS_PATH#"$ORIGINAL_INSTALL_ROOT"/}"',
            "fi",
            "",
            "prepare_release_paths() {",
            '  RELEASES_DIR="${INSTALL_ROOT}/releases"',
            '  NEXT_VENV_PATH="${RELEASES_DIR}/${RELEASE_ID}-staged-$$"',
            '  CURRENT_VENV_PATH="${INSTALL_ROOT}/current"',
            '  if [ -L "$CURRENT_VENV_PATH" ]; then',
            '    PREVIOUS_VENV_TARGET="$(readlink -f "$CURRENT_VENV_PATH" || true)"',
            '  elif [ -x "$VENV_PATH/bin/python" ]; then',
            '    PREVIOUS_VENV_TARGET="$VENV_PATH"',
            "  fi",
            "}",
            "",
            "activate_release() {",
            '  link_path="${INSTALL_ROOT}/.current-${ARTIFACT_SHA256:0:12}"',
            '  if [ "$INSTALL_MODE" = "systemd" ]; then',
            '    sudo_cmd ln -sfn "$NEXT_VENV_PATH" "$link_path"',
            '    sudo_cmd mv -Tf "$link_path" "$CURRENT_VENV_PATH"',
            "  else",
            '    ln -sfn "$NEXT_VENV_PATH" "$link_path"',
            '    mv -Tf "$link_path" "$CURRENT_VENV_PATH"',
            "  fi",
            '  VENV_PATH="$CURRENT_VENV_PATH"',
            "}",
            "",
            "rollback_release() {",
            '  if [ -z "$PREVIOUS_VENV_TARGET" ]; then',
            '    printf "%s\\n" "AKIDA_RUNTIME_ROLLED_BACK=0" >&2',
            "    return",
            "  fi",
            '  rollback_link="${INSTALL_ROOT}/.rollback-${ARTIFACT_SHA256:0:12}"',
            '  if [ "$INSTALL_MODE" = "systemd" ]; then',
            '    sudo_cmd ln -sfn "$PREVIOUS_VENV_TARGET" "$rollback_link"',
            '    sudo_cmd mv -Tf "$rollback_link" "$CURRENT_VENV_PATH"',
            '    sudo_cmd systemctl restart "$RUNTIME_SERVICE_NAME.service" "$CONTROL_SERVICE_NAME.service" || true',
            "  else",
            '    ln -sfn "$PREVIOUS_VENV_TARGET" "$rollback_link"',
            '    mv -Tf "$rollback_link" "$CURRENT_VENV_PATH"',
            '    VENV_PATH="$CURRENT_VENV_PATH"',
            '    "$BIN_DIR/launch-runtime.sh" || true',
            '    "$BIN_DIR/launch-control.sh" || true',
            "  fi",
            '  printf "%s\\n" "AKIDA_RUNTIME_ROLLED_BACK=1" >&2',
            "}",
            "",
            "rollback_on_error() {",
            '  exit_status="$?"',
            "  trap - EXIT",
            '  if [ "$exit_status" -ne 0 ] && [ "$ACTIVATION_PENDING" = "1" ]; then',
            '    log_step "Neurochip activation failed; restoring the previous release"',
            "    rollback_release || true",
            "  fi",
            '  exit "$exit_status"',
            "}",
            "",
            "cleanup_old_releases() {",
            '  while IFS= read -r -d "" release_path; do',
            '    if [ "$release_path" = "$NEXT_VENV_PATH" ] || [ "$release_path" = "$PREVIOUS_VENV_TARGET" ]; then',
            "      continue",
            "    fi",
            '    if [ "$INSTALL_MODE" = "systemd" ]; then',
            '      sudo_cmd rm -rf "$release_path"',
            "    else",
            '      rm -rf "$release_path"',
            "    fi",
            '  done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)',
            "}",
            "",
            'fail_install() { printf "[install-akida-host] %s\\n" "$1" >&2; exit 1; }',
            "run_priv() {",
            '  if [ -n "$USE_SUDO" ]; then',
            '    sudo_cmd "$@"',
            "  else",
            '    "$@"',
            "  fi",
            "}",
            "# True when $1 is an interpreter inside the SDK's supported range.",
            "# The interpreter answers about itself, so there is no version",
            "# parsing here to get wrong.",
            "python_in_range() {",
            '  command -v "$1" >/dev/null 2>&1 || return 1',
            f'  "$1" -c {shlex.quote(version_probe)} >/dev/null 2>&1',
            "}",
            "# Downloads the pinned CPython build. Only ever reached when no",
            "# suitable interpreter already exists, so a host that works today",
            "# never touches the network here.",
            "install_managed_python() {",
            '  host_python="$(python3 -V 2>&1 || echo "none")"',
            '  if [ -z "$STANDALONE_PYTHON_URL" ]; then',
            '    fail_install "This host runs $host_python, but the Akida SDK needs Python $PYTHON_RANGE_LABEL, and no automatic download is configured. Install a Python $PYTHON_RANGE_LABEL on this machine and run setup again."',
            "  fi",
            '  host_arch="$(uname -m)"',
            '  if [ "$host_arch" != "$STANDALONE_PYTHON_ARCH" ]; then',
            '    fail_install "This host runs $host_python on $host_arch. The Akida SDK needs Python $PYTHON_RANGE_LABEL, and an automatic download is only available for $STANDALONE_PYTHON_ARCH. Install a Python $PYTHON_RANGE_LABEL on this machine and run setup again."',
            "  fi",
            '  log_step "Host Python ($host_python) is outside $PYTHON_RANGE_LABEL; installing a private Python $STANDALONE_PYTHON_VERSION for the Akida runtime"',
            '  py_tmp="$(mktemp -d)"',
            '  if ! curl -fsSL --max-time 600 "$STANDALONE_PYTHON_URL" -o "$py_tmp/python.tar.gz"; then',
            '    rm -rf "$py_tmp"',
            '    fail_install "Could not download Python $STANDALONE_PYTHON_VERSION. Check that this server can reach github.com, then run setup again."',
            "  fi",
            '  py_sha="$(sha256sum "$py_tmp/python.tar.gz" | cut -d" " -f1)"',
            '  if [ "$py_sha" != "$STANDALONE_PYTHON_SHA256" ]; then',
            '    rm -rf "$py_tmp"',
            '    fail_install "The downloaded Python archive did not match its expected checksum, so it was discarded. Run setup again; if this repeats, the download is being altered in transit."',
            "  fi",
            # The archive already contains a top-level `python/` directory, so
            # extracting into INSTALL_ROOT lands exactly on MANAGED_PYTHON_ROOT.
            '  run_priv rm -rf "$MANAGED_PYTHON_ROOT"',
            '  run_priv tar -xzf "$py_tmp/python.tar.gz" -C "$INSTALL_ROOT"',
            '  rm -rf "$py_tmp"',
            '  if [ -n "$USE_SUDO" ]; then',
            '    sudo_cmd chown -R "$SERVICE_USER:$SERVICE_USER" "$MANAGED_PYTHON_ROOT"',
            "  fi",
            '  if ! python_in_range "$MANAGED_PYTHON_BIN"; then',
            '    fail_install "The downloaded Python $STANDALONE_PYTHON_VERSION could not run on this server. Install a Python $PYTHON_RANGE_LABEL on this machine and run setup again."',
            "  fi",
            "}",
            "# Order matters: anything already installed wins over a download, so",
            "# hosts that provision correctly today keep behaving exactly as before.",
            "select_python() {",
            "  if python_in_range python3; then",
            '    AKIDA_PYTHON="$(command -v python3)"',
            '    log_step "Using system python3 ($("$AKIDA_PYTHON" -V 2>&1))"',
            "    return",
            "  fi",
            "  for candidate in python3.12 python3.11 python3.10; do",
            '    if python_in_range "$candidate"; then',
            '      AKIDA_PYTHON="$(command -v "$candidate")"',
            '      log_step "Using $candidate ($("$AKIDA_PYTHON" -V 2>&1))"',
            "      return",
            "    fi",
            "  done",
            '  if python_in_range "$MANAGED_PYTHON_BIN"; then',
            '    AKIDA_PYTHON="$MANAGED_PYTHON_BIN"',
            '    log_step "Reusing the private Python at $MANAGED_PYTHON_BIN"',
            "    return",
            "  fi",
            "  install_managed_python",
            '  AKIDA_PYTHON="$MANAGED_PYTHON_BIN"',
            "}",
            "# pip always runs as the account that owns the virtualenv, and",
            "# always against the cache this installer controls.",
            "akida_pip() {",
            # --cache-dir goes directly after the subcommand, never at the end:
            # pip applies these in command-line order, so a trailing one would
            # switch the cache back on and undo the --no-cache-dir retry.
            '  local pip_subcommand="$1"',
            "  shift",
            '  if [ -n "$USE_SUDO" ]; then',
            '    sudo_cmd -u "$SERVICE_USER" "$NEXT_VENV_PATH/bin/pip" "$pip_subcommand" --cache-dir "$PIP_CACHE_DIR" "$@"',
            "  else",
            '    "$NEXT_VENV_PATH/bin/pip" "$pip_subcommand" --cache-dir "$PIP_CACHE_DIR" "$@"',
            "  fi",
            "}",
            *(
                [
                    # pip checks every download against the checksum the package
                    # index publishes, so one damaged file in the cache fails
                    # identically on every retry and the install can never
                    # recover on its own. Take the cached path first -- it is
                    # what a healthy host uses and it is much faster -- and only
                    # throw the cache away once that has failed.
                    "install_akida_packages() {",
                    f"  if akida_pip install {package_install}; then",
                    "    return",
                    "  fi",
                    '  log_step "Package install failed; discarding the download cache and fetching again"',
                    "  akida_pip cache purge || true",
                    f"  if akida_pip install --no-cache-dir {package_install}; then",
                    "    return",
                    "  fi",
                    "  fail_install \"The Akida SDK could not be downloaded onto this server. The files kept arriving damaged or incomplete, even after a clean retry. Check this server's internet connection, then run setup again.\"",
                    "}",
                ]
                if package_install
                else []
            ),
            "write_install_status() {",
            '  INSTALL_MODE="$1"',
            '  INSTALL_MESSAGE="$2"',
            '  INSTALL_AUTO_START_SUPPORTED="$3"',
            "  export INSTALL_MODE INSTALL_MESSAGE INSTALL_AUTO_START_SUPPORTED",
            "  export INSTALL_ROOT TOKEN_PATH INSTALL_STATUS_PATH SERVICE_USER VENV_PATH",
            "  export RUNTIME_API_URL CONTROL_API_URL HOST_OS PYTHON_VERSION",
            "  export RUNTIME_LOG_PATH CONTROL_LOG_PATH ARTIFACT_VERSION ARTIFACT_SHA256",
            "  STATUS_JSON=\"$(python3 - <<'PY'",
            "import json",
            "import os",
            "import sys",
            "from pathlib import Path",
            "payload = {",
            '  "installMode": os.environ["INSTALL_MODE"],',
            '  "state": "ready",',
            '  "message": os.environ["INSTALL_MESSAGE"],',
            '  "runtimeApiUrl": os.environ["RUNTIME_API_URL"],',
            '  "controlApiUrl": os.environ["CONTROL_API_URL"],',
            '  "hostOs": os.environ["HOST_OS"],',
            '  "pythonVersion": os.environ["PYTHON_VERSION"],',
            '  "serviceUser": os.environ["SERVICE_USER"],',
            '  "venvPath": os.environ["VENV_PATH"],',
            '  "installRoot": os.environ["INSTALL_ROOT"],',
            '  "tokenPath": os.environ["TOKEN_PATH"],',
            '  "installStatusPath": os.environ["INSTALL_STATUS_PATH"],',
            '  "runtimeLogPath": os.environ.get("RUNTIME_LOG_PATH", ""),',
            '  "controlLogPath": os.environ.get("CONTROL_LOG_PATH", ""),',
            '  "packageVersion": os.environ["ARTIFACT_VERSION"],',
            '  "artifactSha256": os.environ["ARTIFACT_SHA256"],',
            '  "rolledBack": False,',
            '  "autoStartSupported": os.environ["INSTALL_AUTO_START_SUPPORTED"].lower() == "true",',
            "}",
            "print(json.dumps(payload, indent=2, sort_keys=True))",
            "PY",
            ')"',
            '  if [ "$INSTALL_MODE" = "systemd" ]; then',
            '    printf "%s\\n" "$STATUS_JSON" | write_sudo_file "$INSTALL_STATUS_PATH" 0644 "$SERVICE_USER:$SERVICE_USER"',
            "  else",
            '    mkdir -p "$(dirname "$INSTALL_STATUS_PATH")"',
            '    printf "%s\\n" "$STATUS_JSON" > "$INSTALL_STATUS_PATH"',
            "  fi",
            "}",
            "",
            "write_user_space_launchers() {",
            '  cat <<EOF > "$BIN_DIR/launch-runtime.sh"',
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            'set -a; . "$ENV_DIR/$RUNTIME_SERVICE_NAME.env"; set +a',
            'pkill -f "$VENV_PATH/bin/uvicorn neurochip.app.main:app --host 0.0.0.0 --port $RUNTIME_PORT" >/dev/null 2>&1 || true',
            'nohup "$VENV_PATH/bin/uvicorn" neurochip.app.main:app --host 0.0.0.0 --port "$RUNTIME_PORT" >> "$RUNTIME_LOG_PATH" 2>&1 < /dev/null &',
            "EOF",
            '  chmod 0755 "$BIN_DIR/launch-runtime.sh"',
            '  cat <<EOF > "$BIN_DIR/launch-control.sh"',
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            'set -a; . "$ENV_DIR/$CONTROL_SERVICE_NAME.env"; set +a',
            'pkill -f "$BIN_DIR/akida_remote_control_service.py" >/dev/null 2>&1 || true',
            'nohup "$VENV_PATH/bin/python" "$BIN_DIR/akida_remote_control_service.py" >> "$CONTROL_LOG_PATH" 2>&1 < /dev/null &',
            "EOF",
            '  chmod 0755 "$BIN_DIR/launch-control.sh"',
            "}",
            "",
            "wait_for_http() {",
            '  python3 - "$1" "$2" <<\'PY\'',
            "import sys",
            "import time",
            "import urllib.error",
            "import urllib.request",
            "url = sys.argv[1]",
            "header_key = sys.argv[2]",
            "deadline = time.time() + 120.0",
            "headers = {'X-API-Key': header_key} if header_key else {}",
            "while time.time() < deadline:",
            "    request = urllib.request.Request(url, headers=headers)",
            "    try:",
            "        with urllib.request.urlopen(request, timeout=2.0) as response:",
            "            if response.status == 200:",
            "                sys.exit(0)",
            "    except (urllib.error.URLError, TimeoutError):",
            "        time.sleep(1.0)",
            "sys.exit(1)",
            "PY",
            "}",
            "",
            'INSTALL_MODE="systemd"',
            "if sudo_available; then",
            '  log_step "Privileged sudo available; performing systemd install"',
            '  log_step "Installing base packages"',
            "  sudo_cmd apt-get update",
            "  sudo_cmd apt-get install -y python3 python3-venv python3-pip python3-dev curl pciutils usbutils",
            '  log_step "Ensuring service user exists"',
            '  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then',
            '    sudo_cmd useradd --system --create-home --shell /usr/sbin/nologin "$SERVICE_USER"',
            "  fi",
            # Read-only access to the kernel log, so the diagnostics can name a
            # board that is fitted but not answering instead of shrugging. Not
            # every host has this group, and none of this is worth failing an
            # install over.
            '  if getent group systemd-journal >/dev/null 2>&1; then',
            '    sudo_cmd usermod -aG systemd-journal "$SERVICE_USER" || true',
            "  fi",
            '  log_step "Preparing install directories"',
            '  sudo_cmd mkdir -p "$INSTALL_ROOT" "$ENV_DIR" "$BIN_DIR" "$CREDENTIAL_DIR" "$RELEASES_DIR" "$PIP_CACHE_DIR"',
            '  sudo_cmd chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_ROOT"',
            "  prepare_release_paths",
            '  USE_SUDO="1"',
            "  select_python",
            '  log_step "Creating versioned Python virtual environment"',
            '  sudo_cmd rm -rf "$NEXT_VENV_PATH"',
            '  sudo_cmd -u "$SERVICE_USER" "$AKIDA_PYTHON" -m venv "$NEXT_VENV_PATH"',
            '  log_step "Upgrading pip"',
            '  akida_pip install --upgrade pip setuptools wheel',
            '  log_step "Installing Neurochip wheel"',
            '  akida_pip install --force-reinstall "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            *(
                [
                    '  log_step "Installing Akida runtime dependencies"',
                    "  install_akida_packages",
                ]
                if package_install
                else []
            ),
            '  log_step "Validating the staged Neurochip runtime"',
            '  sudo_cmd -u "$SERVICE_USER" "$NEXT_VENV_PATH/bin/python" -c "from importlib import metadata; import neurochip.app.main; assert metadata.version(\'neurochip\') == \'$ARTIFACT_VERSION\'"',
            '  log_step "Installing remote control service script"',
            '  sudo_cmd install -m 0755 "$BUNDLE_DIR/bin/akida_remote_control_service.py" "$BIN_DIR/akida_remote_control_service.py"',
            '  log_step "Generating shared API token"',
            '  if [ ! -s "$TOKEN_PATH" ]; then',
            '    TOKEN_VALUE="$(python3 - <<'
            "'"
            "PY"
            "'"
            '\nimport secrets\nprint(secrets.token_urlsafe(32))\nPY\n)"',
            '    token_tmp="$(mktemp)"',
            '    printf "%s\n" "$TOKEN_VALUE" > "$token_tmp"',
            '    sudo_cmd install -D -m 0600 -o "$SERVICE_USER" -g "$SERVICE_USER" "$token_tmp" "$TOKEN_PATH"',
            '    rm -f "$token_tmp"',
            "  fi",
            '  TOKEN_VALUE="$(sudo_cmd cat "$TOKEN_PATH")"',
            '  if [ -z "$TOKEN_VALUE" ]; then',
            '    printf "%s\\n" "[install-akida-host] API token file was empty after write" >&2',
            "    exit 1",
            "  fi",
            "else",
            '  INSTALL_MODE="user-space"',
            '  CURRENT_USER="$(id -un)"',
            '  CURRENT_HOME="${HOME:-$(getent passwd "$CURRENT_USER" | cut -d: -f6)}"',
            '  if ! mkdir -p "$INSTALL_ROOT" >/dev/null 2>&1; then',
            '    INSTALL_ROOT="$CURRENT_HOME/.local/share/neurochip-akida-host"',
            "  fi",
            '  VENV_PATH="$INSTALL_ROOT/$ORIGINAL_VENV_BASENAME"',
            '  TOKEN_PATH="$INSTALL_ROOT/$TOKEN_PATH_SUFFIX"',
            '  INSTALL_STATUS_PATH="$INSTALL_ROOT/$INSTALL_STATUS_PATH_SUFFIX"',
            '  ENV_DIR="$INSTALL_ROOT/env"',
            '  BIN_DIR="$INSTALL_ROOT/bin"',
            # Must be re-derived with every other INSTALL_ROOT-relative path:
            # this branch runs precisely because the original root is not
            # writable, so a stale value would try to unpack into it and fail.
            '  MANAGED_PYTHON_ROOT="$INSTALL_ROOT/python"',
            '  MANAGED_PYTHON_BIN="$MANAGED_PYTHON_ROOT/bin/python3"',
            '  PIP_CACHE_DIR="$INSTALL_ROOT/cache/pip"',
            '  CREDENTIAL_DIR="$(dirname "$TOKEN_PATH")"',
            '  RUNTIME_LOG_PATH="$INSTALL_ROOT/runtime.log"',
            '  CONTROL_LOG_PATH="$INSTALL_ROOT/control.log"',
            '  SERVICE_USER="$CURRENT_USER"',
            '  log_step "Passwordless sudo unavailable; falling back to user-space install at $INSTALL_ROOT"',
            '  mkdir -p "$INSTALL_ROOT" "$ENV_DIR" "$BIN_DIR" "$CREDENTIAL_DIR" "$PIP_CACHE_DIR"',
            "  prepare_release_paths",
            '  mkdir -p "$RELEASES_DIR"',
            '  USE_SUDO=""',
            "  select_python",
            '  log_step "Creating versioned Python virtual environment"',
            '  rm -rf "$NEXT_VENV_PATH"',
            '  "$AKIDA_PYTHON" -m venv "$NEXT_VENV_PATH"',
            '  log_step "Upgrading pip"',
            '  akida_pip install --upgrade pip setuptools wheel',
            '  log_step "Installing Neurochip wheel"',
            '  akida_pip install --force-reinstall "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            *(
                [
                    '  log_step "Installing Akida runtime dependencies"',
                    "  install_akida_packages",
                ]
                if package_install
                else []
            ),
            '  log_step "Validating the staged Neurochip runtime"',
            "  \"$NEXT_VENV_PATH/bin/python\" -c \"from importlib import metadata; import neurochip.app.main; assert metadata.version('neurochip') == '$ARTIFACT_VERSION'\"",
            '  log_step "Installing remote control service script"',
            '  install -m 0755 "$BUNDLE_DIR/bin/akida_remote_control_service.py" "$BIN_DIR/akida_remote_control_service.py"',
            '  log_step "Generating shared API token"',
            '  if [ ! -s "$TOKEN_PATH" ]; then',
            '    TOKEN_VALUE="$(python3 - <<'
            "'"
            "PY"
            "'"
            '\nimport secrets\nprint(secrets.token_urlsafe(32))\nPY\n)"',
            '    printf "%s\n" "$TOKEN_VALUE" > "$TOKEN_PATH"',
            '    chmod 0600 "$TOKEN_PATH"',
            "  fi",
            '  TOKEN_VALUE="$(cat "$TOKEN_PATH")"',
            "fi",
            'log_step "Activating staged Neurochip runtime"',
            'ACTIVATION_PENDING="1"',
            "trap rollback_on_error EXIT",
            "activate_release",
            'HOST_ADDR="${HOST_ADDR:-$(hostname -f 2>/dev/null || hostname)}"',
            'RUNTIME_API_URL="http://${HOST_ADDR}:${RUNTIME_PORT}"',
            'CONTROL_API_URL="http://${HOST_ADDR}:${CONTROL_PORT}"',
            'PYTHON_VERSION="$("$VENV_PATH/bin/python" -c "import platform; print(platform.python_version())")"',
            'HOST_OS="$("$VENV_PATH/bin/python" -c "import platform; print(platform.system().lower())")"',
            'log_step "Writing service environment files"',
            'if [ "$INSTALL_MODE" = "systemd" ]; then',
            '  cat <<EOF | write_sudo_file "$ENV_DIR/$RUNTIME_SERVICE_NAME.env" 0640 "$SERVICE_USER:$SERVICE_USER"',
            "NEUROCHIP_AUTH_ENABLED=true",
            "NEUROCHIP_API_KEY=${TOKEN_VALUE}",
            "NEUROCHIP_AKIDA_MODEL_DIR=${INSTALL_ROOT}/data/akida-models",
            "EOF",
            '  cat <<EOF | write_sudo_file "$ENV_DIR/$CONTROL_SERVICE_NAME.env" 0640 "$SERVICE_USER:$SERVICE_USER"',
            "NEUROCHIP_REMOTE_CONTROL_HOST=0.0.0.0",
            "NEUROCHIP_REMOTE_CONTROL_PORT=${CONTROL_PORT}",
            "NEUROCHIP_REMOTE_CONTROL_API_KEY=${TOKEN_VALUE}",
            "LOCAL_NEUROCHIP_BASE_URL=http://127.0.0.1:${RUNTIME_PORT}",
            "NEUROCHIP_INSTALL_STATUS_PATH=${INSTALL_STATUS_PATH}",
            "EOF",
            '  log_step "Installing systemd units"',
            '  sudo_cmd install -m 0644 "$BUNDLE_DIR/systemd/$RUNTIME_SERVICE_NAME.service" "/etc/systemd/system/$RUNTIME_SERVICE_NAME.service"',
            '  sudo_cmd install -m 0644 "$BUNDLE_DIR/systemd/$CONTROL_SERVICE_NAME.service" "/etc/systemd/system/$CONTROL_SERVICE_NAME.service"',
            "  sudo_cmd systemctl daemon-reload",
            '  sudo_cmd systemctl enable "$RUNTIME_SERVICE_NAME.service" "$CONTROL_SERVICE_NAME.service"',
            '  sudo_cmd systemctl restart "$RUNTIME_SERVICE_NAME.service" "$CONTROL_SERVICE_NAME.service"',
            "else",
            '  cat <<EOF > "$ENV_DIR/$RUNTIME_SERVICE_NAME.env"',
            "NEUROCHIP_AUTH_ENABLED=true",
            "NEUROCHIP_API_KEY=${TOKEN_VALUE}",
            "NEUROCHIP_AKIDA_MODEL_DIR=${INSTALL_ROOT}/data/akida-models",
            "EOF",
            '  cat <<EOF > "$ENV_DIR/$CONTROL_SERVICE_NAME.env"',
            "NEUROCHIP_REMOTE_CONTROL_HOST=0.0.0.0",
            "NEUROCHIP_REMOTE_CONTROL_PORT=${CONTROL_PORT}",
            "NEUROCHIP_REMOTE_CONTROL_API_KEY=${TOKEN_VALUE}",
            "LOCAL_NEUROCHIP_BASE_URL=http://127.0.0.1:${RUNTIME_PORT}",
            "NEUROCHIP_INSTALL_STATUS_PATH=${INSTALL_STATUS_PATH}",
            "EOF",
            '  chmod 0600 "$ENV_DIR/$RUNTIME_SERVICE_NAME.env" "$ENV_DIR/$CONTROL_SERVICE_NAME.env"',
            '  log_step "Writing user-space launchers"',
            "  write_user_space_launchers",
            '  log_step "Launching user-space runtime and control services"',
            '  "$BIN_DIR/launch-runtime.sh"',
            '  "$BIN_DIR/launch-control.sh"',
            "fi",
            'log_step "Waiting for Neurochip runtime health"',
            'if ! wait_for_http "http://127.0.0.1:${RUNTIME_PORT}/health" "$TOKEN_VALUE"; then',
            '  log_step "New Neurochip runtime failed health verification"',
            "  exit 1",
            "fi",
            'log_step "Waiting for remote control health"',
            'if ! wait_for_http "http://127.0.0.1:${CONTROL_PORT}/health" ""; then',
            '  log_step "New Akida control service failed health verification"',
            "  exit 1",
            "fi",
            'if [ "$INSTALL_MODE" = "systemd" ]; then',
            '  write_install_status "systemd" "Akida host installation completed." "true"',
            '  INSTALL_STATUS_PAYLOAD="$(sudo_cmd cat "$INSTALL_STATUS_PATH")"',
            "else",
            '  write_install_status "user-space" "Akida host installed in user space; auto-start requires privileged setup." "false"',
            '  INSTALL_STATUS_PAYLOAD="$(cat "$INSTALL_STATUS_PATH")"',
            "fi",
            'if [ -z "$INSTALL_STATUS_PAYLOAD" ]; then',
            '  printf "%s\\n" "[install-akida-host] Install status file was empty after write" >&2',
            "  exit 1",
            "fi",
            "cleanup_old_releases",
            'ACTIVATION_PENDING="0"',
            "trap - EXIT",
            'printf "INSTALL_STATUS_JSON=%s\\n" "$INSTALL_STATUS_PAYLOAD"',
            'log_step "Install script completed successfully"',
            "",
        ]
    )


def build_akida_host_bundle(
    bundle_dir: Path,
    *,
    repo_root: Path,
    required_packages: list[str],
    wheel_path: Path | None = None,
    install_root: str = DEFAULT_AKIDA_INSTALL_ROOT,
    service_user: str = DEFAULT_AKIDA_SERVICE_USER,
    venv_path: str = DEFAULT_AKIDA_VENV_PATH,
    runtime_service_name: str = DEFAULT_AKIDA_RUNTIME_SERVICE,
    control_service_name: str = DEFAULT_AKIDA_CONTROL_SERVICE,
    runtime_port: int = DEFAULT_AKIDA_RUNTIME_PORT,
    control_port: int = DEFAULT_AKIDA_CONTROL_PORT,
    token_path: str = DEFAULT_AKIDA_TOKEN_PATH,
    install_status_path: str = DEFAULT_AKIDA_INSTALL_STATUS_PATH,
    python_range: str = DEFAULT_AKIDA_PYTHON_RANGE,
    standalone_python: dict[str, Any] | None = None,
) -> dict[str, Any]:
    bundle_dir.mkdir(parents=True, exist_ok=True)
    wheels_dir = bundle_dir / "wheels"
    systemd_dir = bundle_dir / "systemd"
    bin_dir = bundle_dir / "bin"
    wheels_dir.mkdir(parents=True, exist_ok=True)
    systemd_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)

    resolved_wheel_path = wheel_path or ensure_agent_wheel(repo_root)
    artifact = inspect_neurochip_runtime_artifact(resolved_wheel_path)
    copied_wheel = wheels_dir / artifact.wheel_path.name
    shutil.copy2(artifact.wheel_path, copied_wheel)

    active_venv_path = f"{install_root.rstrip('/')}/current"
    runtime_unit = systemd_dir / f"{runtime_service_name}.service"
    runtime_unit.write_text(
        _akida_runtime_unit_text(
            install_root=install_root,
            venv_path=active_venv_path,
            service_user=service_user,
            runtime_service_name=runtime_service_name,
            runtime_port=runtime_port,
        ),
        encoding="utf-8",
    )

    control_unit = systemd_dir / f"{control_service_name}.service"
    control_unit.write_text(
        _akida_control_unit_text(
            install_root=install_root,
            venv_path=active_venv_path,
            service_user=service_user,
            control_service_name=control_service_name,
        ),
        encoding="utf-8",
    )

    control_script = bin_dir / "akida_remote_control_service.py"
    control_script.write_text(_remote_control_script_text(), encoding="utf-8")
    control_script.chmod(control_script.stat().st_mode | stat.S_IXUSR)

    install_script = bundle_dir / "install-akida-host.sh"
    install_script.write_text(
        _akida_install_script_text(
            install_root=install_root,
            service_user=service_user,
            venv_path=venv_path,
            runtime_service_name=runtime_service_name,
            control_service_name=control_service_name,
            runtime_port=runtime_port,
            control_port=control_port,
            token_path=token_path,
            install_status_path=install_status_path,
            wheel_name=copied_wheel.name,
            artifact_version=artifact.version,
            artifact_sha256=artifact.sha256,
            required_packages=required_packages,
            python_range=python_range,
            standalone_python=standalone_python,
        ),
        encoding="utf-8",
    )
    install_script.chmod(install_script.stat().st_mode | stat.S_IXUSR)

    manifest = {
        "installRoot": install_root,
        "serviceUser": service_user,
        "venvPath": active_venv_path,
        "runtimeServiceName": runtime_service_name,
        "controlServiceName": control_service_name,
        "runtimePort": runtime_port,
        "controlPort": control_port,
        "requiredPackages": required_packages,
        "artifactVersion": artifact.version,
        "artifactSha256": artifact.sha256,
        "tokenPath": token_path,
        "installStatusPath": install_status_path,
        "bundleContents": [
            os.path.relpath(copied_wheel, bundle_dir),
            os.path.relpath(runtime_unit, bundle_dir),
            os.path.relpath(control_unit, bundle_dir),
            os.path.relpath(control_script, bundle_dir),
            os.path.relpath(install_script, bundle_dir),
        ],
    }
    (bundle_dir / "bundle-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return manifest
