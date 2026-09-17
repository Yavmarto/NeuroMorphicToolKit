"""Build a provisioning bundle for a remote Akida-capable Neurochip host."""

from __future__ import annotations

import json
import os
import shutil
import stat
from pathlib import Path
from typing import Any

from .pynq_agent_bundle import ensure_agent_wheel

DEFAULT_AKIDA_INSTALL_ROOT = "/opt/neurochip-akida-host"
DEFAULT_AKIDA_SERVICE_USER = "neurochip"
DEFAULT_AKIDA_VENV_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/venv"
DEFAULT_AKIDA_RUNTIME_SERVICE = "neurochip"
DEFAULT_AKIDA_CONTROL_SERVICE = "neurochip-akida-control"
DEFAULT_AKIDA_RUNTIME_PORT = 8002
DEFAULT_AKIDA_CONTROL_PORT = 8090
DEFAULT_AKIDA_TOKEN_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/credentials/api-token"
DEFAULT_AKIDA_INSTALL_STATUS_PATH = f"{DEFAULT_AKIDA_INSTALL_ROOT}/install-status.json"


def _runtime_unit_text(
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


def _control_unit_text(
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
    except Exception as exc:  # noqa: BLE001
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

    def do_GET(self) -> None:  # noqa: N802
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


def _install_script_text(
    *,
    install_root: str,
    service_user: str,
    venv_path: str,
    runtime_service_name: str,
    control_service_name: str,
    runtime_port: int,
    control_port: int,
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
            f'TOKEN_PATH="${{TOKEN_PATH:-{DEFAULT_AKIDA_TOKEN_PATH}}}"',
            f'INSTALL_STATUS_PATH="${{INSTALL_STATUS_PATH:-{DEFAULT_AKIDA_INSTALL_STATUS_PATH}}}"',
            'ENV_DIR="${INSTALL_ROOT}/env"',
            'BIN_DIR="${INSTALL_ROOT}/bin"',
            'CREDENTIAL_DIR="$(dirname "$TOKEN_PATH")"',
            f'WHEEL_NAME="${{WHEEL_NAME:-{wheel_name}}}"',
            "",
            "write_install_status() {",
            '  STATUS_JSON="$(python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" <<\'PY\'',
            "import json",
            "import sys",
            "from pathlib import Path",
            "payload = {",
            '  "state": sys.argv[1],',
            '  "message": sys.argv[2],',
            '  "runtimeApiUrl": sys.argv[3],',
            '  "controlApiUrl": sys.argv[4],',
            '  "hostOs": sys.argv[5],',
            '  "pythonVersion": sys.argv[6],',
            '  "serviceUser": sys.argv[7],',
            '  "venvPath": sys.argv[8],',
            "}",
            "print(json.dumps(payload, indent=2, sort_keys=True))",
            "PY",
            ')"',
            '  sudo -n mkdir -p "$(dirname "$INSTALL_STATUS_PATH")"',
            '  printf "%s\\n" "$STATUS_JSON" | sudo -n tee "$INSTALL_STATUS_PATH" >/dev/null',
            '  sudo -n chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_STATUS_PATH"',
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
            'sudo -n -u "$SERVICE_USER" "$VENV_PATH/bin/pip" install --force-reinstall --no-deps "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            'log_step "Installing Akida runtime dependencies"',
            f'sudo -n -u "$SERVICE_USER" "$VENV_PATH/bin/pip" install {package_install}',
            'log_step "Installing remote control service script"',
            'sudo -n install -m 0755 "$BUNDLE_DIR/bin/akida_remote_control_service.py" "$BIN_DIR/akida_remote_control_service.py"',
            'log_step "Generating shared API token"',
            'if [ ! -f "$TOKEN_PATH" ]; then',
            '  TOKEN_VALUE="$(python3 - <<'
            "'"
            "PY"
            "'"
            '\nimport secrets\nprint(secrets.token_urlsafe(32))\nPY\n)"',
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
            "NEUROCHIP_API_KEY=${TOKEN_VALUE}",
            "EOF",
            'cat <<EOF | sudo -n tee "$ENV_DIR/$CONTROL_SERVICE_NAME.env" >/dev/null',
            "NEUROCHIP_REMOTE_CONTROL_HOST=0.0.0.0",
            "NEUROCHIP_REMOTE_CONTROL_PORT=${CONTROL_PORT}",
            "NEUROCHIP_REMOTE_CONTROL_API_KEY=${TOKEN_VALUE}",
            "LOCAL_NEUROCHIP_BASE_URL=http://127.0.0.1:${RUNTIME_PORT}",
            "NEUROCHIP_INSTALL_STATUS_PATH=${INSTALL_STATUS_PATH}",
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
            'printf "INSTALL_STATUS_JSON=%s\\n" "$(sudo -n cat "$INSTALL_STATUS_PATH")"',
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
        _runtime_unit_text(
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
        _control_unit_text(
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
        _install_script_text(
            install_root=install_root,
            service_user=service_user,
            venv_path=venv_path,
            runtime_service_name=runtime_service_name,
            control_service_name=control_service_name,
            runtime_port=runtime_port,
            control_port=control_port,
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
        "tokenPath": DEFAULT_AKIDA_TOKEN_PATH,
        "installStatusPath": DEFAULT_AKIDA_INSTALL_STATUS_PATH,
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
