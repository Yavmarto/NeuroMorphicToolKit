"""Launcher-owned provisioning bundle helpers.

These helpers intentionally mirror the minimal Neurochip remote-install
artifacts the launcher needs so launcher runtime behavior does not depend on
importing or loading checked-out Neurochip package internals.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import stat
import subprocess
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

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
DEFAULT_AKIDA_CONTROL_PORT = 8090
DEFAULT_AKIDA_TOKEN_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/credentials/api-token"
DEFAULT_AKIDA_INSTALL_STATUS_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/install-status.json"


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


def build_pynq_user_space_agent_launch_command(
    *,
    agent_executable: str,
    pynq_python_path: str,
    install_status_path: str,
    overlay_dir: str,
    runtime_log_path: str,
    shell_safe_values: bool = False,
) -> str:
    """Build a durable shell command for launching the PYNQ agent in user space."""
    env_assignments = " ".join(
        [
            f"NEUROCHIP_PYNQ_PYTHON={_shell_value(pynq_python_path, shell_safe_values=shell_safe_values)}",
            'NEUROCHIP_PYNQ_INSTALL_MODE="user-space"',
            f"NEUROCHIP_PYNQ_INSTALL_STATUS_PATH={_shell_value(install_status_path, shell_safe_values=shell_safe_values)}",
            f"NEUROCHIP_PYNQ_OVERLAY_DIR={_shell_value(overlay_dir, shell_safe_values=shell_safe_values)}",
        ]
    )
    executable = _shell_value(agent_executable, shell_safe_values=shell_safe_values)
    runtime_log = _shell_value(runtime_log_path, shell_safe_values=shell_safe_values)
    launch_payload = (
        f"exec env {env_assignments} {executable} "
        f">{runtime_log} 2>&1 </dev/null"
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
            'write_install_status() {',
            '  python3 - "$INSTALL_STATUS_PATH" "$1" "$2" "$SERVICE_NAME" "$AGENT_VENV_PATH" "$PYNQ_VENV_PATH" "$RUNTIME_LOG_PATH" "$EFFECTIVE_PYNQ_PYTHON" "$PYNQ_RUNTIME_SOURCE" "$AGENT_PACKAGE_VERSION" "$AGENT_WHEEL_NAME" <<'"'"'PY'"'"'',
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
            'detect_pynq_runtime() {',
            '  if [ -x "$CANONICAL_PYNQ_PYTHON" ] && \\',
            '     "$CANONICAL_PYNQ_PYTHON" -c "import pynq; import pyxrt" >/dev/null 2>&1; then',
            '    EFFECTIVE_PYNQ_PYTHON="$CANONICAL_PYNQ_PYTHON"',
            '    PYNQ_RUNTIME_SOURCE="canonical"',
            '    return 0',
            '  fi',
            '  return 1',
            '}',
            "",
            'wait_for_health() {',
            '  python3 - "$AGENT_HOST" "$AGENT_PORT" <<'"'"'PY'"'"'',
            "import sys",
            "import time",
            "import urllib.error",
            "import urllib.request",
            "",
            "host = sys.argv[1]",
            "port = int(sys.argv[2])",
            'url = f"http://{host}:{port}/health"',
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
            'if detect_pynq_runtime; then',
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
            '  "$AGENT_VENV_PATH/bin/python" - <<'"'"'PY'"'"'',
            "from importlib import metadata",
            "try:",
            '    print(metadata.version("neurochip"))',
            "except metadata.PackageNotFoundError:",
            '    print("")',
            "PY",
            ')"',
            'log_step "Checking passwordless sudo access for system service install"',
            'if sudo -n true >/dev/null 2>&1; then',
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
            '  write_install_status "user-space" "Runtime installed in user space; auto-start and launcher restart require privileged setup."',
            '  pkill -f "$AGENT_VENV_PATH/bin/$AGENT_EXECUTABLE_NAME" >/dev/null 2>&1 || true',
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
    resolved_install_status_path = install_status_path or f"{install_root}/install-status.json"
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
    return r'''#!/usr/bin/env python3
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
CONTROL_PORT = int(os.getenv("NEUROCHIP_REMOTE_CONTROL_PORT", "8090"))
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

    sdk_status = str(runtime_status.get("sdk_status") or "").strip().lower()
    runtime_target = str(runtime_status.get("runtime_target") or "").strip().lower()
    if runtime_health_status != 200:
        preflight_status = "failed"
        preflight_message = "Neurochip runtime health check failed"
    elif sdk_status == "deployable" and runtime_target == "hardware":
        preflight_status = "ok"
        preflight_message = "Akida hardware runtime is ready."
    elif runtime_status_status == 200:
        preflight_status = "degraded"
        preflight_message = str(
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
            "lspci": _run_probe(["lspci"]),
            "lsusb": _run_probe(["lsusb"]),
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
'''


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
    required_packages: list[str],
) -> str:
    package_install = " ".join(required_packages)
    return "\n".join(
        [
            "#!/usr/bin/env bash",
            "set -euo pipefail",
            "",
            'log_step() { printf "[install-akida-host] %s\\n" "$1"; }',
            "",
            'BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
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
            "",
            "write_install_status() {",
            '  python3 - "$INSTALL_STATUS_PATH" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" <<'"'"'PY'"'"'',
            "import json",
            "import sys",
            "from pathlib import Path",
            "payload = {",
            '  "state": sys.argv[2],',
            '  "message": sys.argv[3],',
            '  "runtimeApiUrl": sys.argv[4],',
            '  "controlApiUrl": sys.argv[5],',
            '  "hostOs": sys.argv[6],',
            '  "pythonVersion": sys.argv[7],',
            '  "serviceUser": sys.argv[8],',
            '  "venvPath": sys.argv[9],',
            "}",
            'Path(sys.argv[1]).write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")',
            "PY",
            "}",
            "",
            "wait_for_http() {",
            '  python3 - "$1" "$2" <<'"'"'PY'"'"'',
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
            'log_step "Checking sudo access"',
            "sudo -n true >/dev/null 2>&1",
            'log_step "Installing base packages"',
            "sudo -n apt-get update",
            "sudo -n apt-get install -y python3 python3-venv python3-pip python3-dev curl pciutils usbutils",
            'log_step "Ensuring service user exists"',
            'if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then',
            '  sudo -n useradd --system --create-home --shell /usr/sbin/nologin "$SERVICE_USER"',
            "fi",
            'log_step "Preparing install directories"',
            'sudo -n mkdir -p "$INSTALL_ROOT" "$ENV_DIR" "$BIN_DIR" "$CREDENTIAL_DIR"',
            'sudo -n chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_ROOT"',
            'log_step "Creating Python virtual environment"',
            'sudo -n -u "$SERVICE_USER" python3 -m venv "$VENV_PATH"',
            'log_step "Upgrading pip"',
            'sudo -n -u "$SERVICE_USER" "$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel',
            'log_step "Installing Neurochip wheel"',
            'sudo -n -u "$SERVICE_USER" "$VENV_PATH/bin/pip" install "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            'log_step "Installing Akida runtime dependencies"',
            f'sudo -n -u "$SERVICE_USER" "$VENV_PATH/bin/pip" install {package_install}',
            'log_step "Installing remote control service script"',
            'sudo -n install -m 0755 "$BUNDLE_DIR/bin/akida_remote_control_service.py" "$BIN_DIR/akida_remote_control_service.py"',
            'log_step "Generating shared API token"',
            'if [ ! -f "$TOKEN_PATH" ]; then',
            '  TOKEN_VALUE="$(python3 - <<'"'"'PY'"'"'\nimport secrets\nprint(secrets.token_urlsafe(32))\nPY\n)"',
            '  printf "%s\n" "$TOKEN_VALUE" | sudo -n tee "$TOKEN_PATH" >/dev/null',
            '  sudo -n chown "$SERVICE_USER:$SERVICE_USER" "$TOKEN_PATH"',
            '  sudo -n chmod 0600 "$TOKEN_PATH"',
            "fi",
            'TOKEN_VALUE="$(sudo -n cat "$TOKEN_PATH")"',
            'HOST_ADDR="${HOST_ADDR:-$(hostname -f 2>/dev/null || hostname)}"',
            'RUNTIME_API_URL="http://${HOST_ADDR}:${RUNTIME_PORT}"',
            'CONTROL_API_URL="http://${HOST_ADDR}:${CONTROL_PORT}"',
            'PYTHON_VERSION="$("$VENV_PATH/bin/python" -c "import platform; print(platform.python_version())")"',
            'HOST_OS="$("$VENV_PATH/bin/python" -c "import platform; print(platform.system().lower())")"',
            'log_step "Writing service environment files"',
            'cat <<EOF | sudo -n tee "$ENV_DIR/$RUNTIME_SERVICE_NAME.env" >/dev/null',
            "NEUROCHIP_AUTH_ENABLED=true",
            'NEUROCHIP_API_KEY=${TOKEN_VALUE}',
            "EOF",
            'cat <<EOF | sudo -n tee "$ENV_DIR/$CONTROL_SERVICE_NAME.env" >/dev/null',
            "NEUROCHIP_REMOTE_CONTROL_HOST=0.0.0.0",
            'NEUROCHIP_REMOTE_CONTROL_PORT=${CONTROL_PORT}',
            'NEUROCHIP_REMOTE_CONTROL_API_KEY=${TOKEN_VALUE}',
            'LOCAL_NEUROCHIP_BASE_URL=http://127.0.0.1:${RUNTIME_PORT}',
            'NEUROCHIP_INSTALL_STATUS_PATH=${INSTALL_STATUS_PATH}',
            "EOF",
            'sudo -n chown "$SERVICE_USER:$SERVICE_USER" "$ENV_DIR/$RUNTIME_SERVICE_NAME.env" "$ENV_DIR/$CONTROL_SERVICE_NAME.env"',
            'sudo -n chmod 0640 "$ENV_DIR/$RUNTIME_SERVICE_NAME.env" "$ENV_DIR/$CONTROL_SERVICE_NAME.env"',
            'log_step "Installing systemd units"',
            'sudo -n install -m 0644 "$BUNDLE_DIR/systemd/$RUNTIME_SERVICE_NAME.service" "/etc/systemd/system/$RUNTIME_SERVICE_NAME.service"',
            'sudo -n install -m 0644 "$BUNDLE_DIR/systemd/$CONTROL_SERVICE_NAME.service" "/etc/systemd/system/$CONTROL_SERVICE_NAME.service"',
            "sudo -n systemctl daemon-reload",
            'sudo -n systemctl enable "$RUNTIME_SERVICE_NAME.service" "$CONTROL_SERVICE_NAME.service"',
            'sudo -n systemctl restart "$RUNTIME_SERVICE_NAME.service" "$CONTROL_SERVICE_NAME.service"',
            'log_step "Waiting for Neurochip runtime health"',
            'wait_for_http "http://127.0.0.1:${RUNTIME_PORT}/health" "$TOKEN_VALUE"',
            'log_step "Waiting for remote control health"',
            'wait_for_http "http://127.0.0.1:${CONTROL_PORT}/health" ""',
            'write_install_status "ready" "Akida host installation completed." "$RUNTIME_API_URL" "$CONTROL_API_URL" "$HOST_OS" "$PYTHON_VERSION" "$SERVICE_USER" "$VENV_PATH"',
            'printf "INSTALL_STATUS_JSON=%s\\n" "$(cat "$INSTALL_STATUS_PATH")"',
            'log_step "Install script completed successfully"',
            "",
        ]
    )


def build_akida_host_bundle(
    bundle_dir: Path,
    *,
    repo_root: Path,
    required_packages: list[str],
    install_root: str = DEFAULT_AKIDA_INSTALL_ROOT,
    service_user: str = DEFAULT_AKIDA_SERVICE_USER,
    venv_path: str = DEFAULT_AKIDA_VENV_PATH,
    runtime_service_name: str = DEFAULT_AKIDA_RUNTIME_SERVICE,
    control_service_name: str = DEFAULT_AKIDA_CONTROL_SERVICE,
    runtime_port: int = DEFAULT_AKIDA_RUNTIME_PORT,
    control_port: int = DEFAULT_AKIDA_CONTROL_PORT,
    token_path: str = DEFAULT_AKIDA_TOKEN_PATH,
    install_status_path: str = DEFAULT_AKIDA_INSTALL_STATUS_PATH,
) -> dict[str, Any]:
    bundle_dir.mkdir(parents=True, exist_ok=True)
    wheels_dir = bundle_dir / "wheels"
    systemd_dir = bundle_dir / "systemd"
    bin_dir = bundle_dir / "bin"
    wheels_dir.mkdir(parents=True, exist_ok=True)
    systemd_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)

    wheel_path = ensure_agent_wheel(repo_root)
    copied_wheel = wheels_dir / wheel_path.name
    shutil.copy2(wheel_path, copied_wheel)

    runtime_unit = systemd_dir / f"{runtime_service_name}.service"
    runtime_unit.write_text(
        _akida_runtime_unit_text(
            install_root=install_root,
            venv_path=venv_path,
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
            venv_path=venv_path,
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
            required_packages=required_packages,
        ),
        encoding="utf-8",
    )
    install_script.chmod(install_script.stat().st_mode | stat.S_IXUSR)

    manifest = {
        "installRoot": install_root,
        "serviceUser": service_user,
        "venvPath": venv_path,
        "runtimeServiceName": runtime_service_name,
        "controlServiceName": control_service_name,
        "runtimePort": runtime_port,
        "controlPort": control_port,
        "requiredPackages": required_packages,
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
