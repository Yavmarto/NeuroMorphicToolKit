"""Host-side launcher control service for desktop and web launcher clients."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse, urlunparse
from uuid import uuid4

import tomllib

from packaging.specifiers import SpecifierSet
from packaging.version import InvalidVersion
from packaging.version import Version
from packaging.version import parse as parse_version

from .deployment_service import DeploymentService
from .deployment_store import DeploymentStore, FileBackedSecretStore
from .http_server import LauncherControlHandler
from .workspace_service import WorkspaceStateMixin
from .provisioning_helpers import (
    build_akida_host_bundle,
    build_pynq_agent_bundle,
    build_pynq_user_space_agent_launch_command,
)
from .runtime_contracts import (
    AkidaLauncherRuntimeContract as _AkidaLauncherRuntimeContract,
    NeurochipLauncherRuntimeContract as _NeurochipLauncherRuntimeContract,
    PynqLauncherRuntimeContract as _PynqLauncherRuntimeContract,
    load_neurochip_launcher_runtime_contract,
)
from .runtime_errors import RuntimeRequestError as _RuntimeRequestError
from .runtime_shared import (
    _build_password_askpass_env,
    _module_root,
    _neurochip_module_root,
    _read_json_file,
    _runtime_request_error_kind,
    _write_json_file,
)

from .config import (
    REPO_ROOT,
    MODULES_MANIFEST,
    STATE_FILE,
    SETTINGS_FILE,
    WORKSPACE_FILE,
    DEPLOYMENT_STATE_FILE,
    DEPLOYMENT_SECRET_FILE,
    SUITE_API_ENV_ROOT,
)

STATUS_INDEX: dict[str, int] = {
    "notInstalled": 0,
    "installing": 1,
    "installed": 2,
    "starting": 3,
    "running": 4,
    "stopping": 5,
    "error": 6,
    "degraded": 7,
    "updating": 8,
}

DEFAULT_CONTROL_LOG_LEVEL = "info"
HEALTH_POLL_SECONDS = 5.0
STARTUP_GRACE_SECONDS = 12.0
LOG_LINE_LIMIT = 400
PREFLIGHT_OK = "ok"
PREFLIGHT_DEGRADED = "degraded"
PREFLIGHT_FAILED = "failed"
SUPPORTED_INSTALL_STRATEGIES = {"pip"}
SUPPORTED_START_STRATEGIES = {"uvicorn", "none"}
PREFLIGHT_SENTINEL = "NMTK_PREFLIGHT_JSON="
INSTALL_STATUS_SENTINEL = "INSTALL_STATUS_JSON="
DEFAULT_AKIDA_HOST_PORT = 8002
DEFAULT_AKIDA_CONTROL_PORT = 8091
DEFAULT_AKIDA_HOST_SSH_PORT = 22
DEFAULT_PYNQ_BOARD_PORT = 8002
DEFAULT_PYNQ_BOARD_SSH_PORT = 22
# 60s was too tight: a cold provision on a Pynq-Z2 regularly needs 90-100s for
# pip resolution, wheel install, systemctl restart, and uvicorn cold-start on
# ARM. 120s is the new default; operators can still tune via
# NEUROCHIP_PYNQ_HEALTH_TIMEOUT_SECONDS up to the upper bound.
DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS = 120.0
PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS = (5.0, 600.0)
PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS = 15.0
DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS = 45.0
PYNQ_PREFLIGHT_TIMEOUT_BOUNDS = (5.0, 300.0)
PYNQ_PREFLIGHT_RETRY_COUNT = 3
PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS = 2.0
# PYNQ inference (DMA transfer + SNN worker subprocess) on real Z2 hardware
# regularly exceeds the 15s _runtime_json_request default. 60s covers
# typical SNN workloads; operators can tune via NEUROCHIP_PYNQ_RUN_TIMEOUT_SECONDS.
DEFAULT_PYNQ_RUN_TIMEOUT_SECONDS = 60.0
PYNQ_RUN_TIMEOUT_BOUNDS = (15.0, 300.0)
PYNQ_RUNTIME_LOG_TAIL_LINES = 80
DEFAULT_STAGED_OVERLAY_DIRNAME = "overlay_staging"
DEFAULT_STAGED_OVERLAY_TARGET = "pynq_z2"
DEFAULT_STAGED_OVERLAY_MANIFEST = "overlay_manifest.json"
DEFAULT_STAGED_PYNQ_BITSTREAM_NAME = "snn_overlay.bit"
DEFAULT_STAGED_PYNQ_HWH_NAME = "snn_overlay.hwh"
DEFAULT_PYNQ_BOARD_USERNAME = "xilinx"
DEFAULT_PYNQ_BOARD_STATE = "unpaired"
DEFAULT_PYNQ_AUTH_MODE = "password"
DEFAULT_AKIDA_HOST_STATE = "unknown"
DEFAULT_AKIDA_AUTH_MODE = "password"
DEFAULT_AKIDA_SERVICE_USER = "neurochip"
DEFAULT_AKIDA_REMOTE_INSTALL_ROOT = "/opt/neurochip-akida-host"
DEFAULT_AKIDA_RUNTIME_SERVICE_NAME = "neurochip"
DEFAULT_AKIDA_CONTROL_SERVICE_NAME = "neurochip-akida-control"
DEFAULT_AKIDA_REMOTE_VENV_PATH = f"{DEFAULT_AKIDA_REMOTE_INSTALL_ROOT}/venv"
DEFAULT_AKIDA_TOKEN_PATH = f"{DEFAULT_AKIDA_REMOTE_INSTALL_ROOT}/credentials/api-token"
AKIDA_RUNTIME_MODES = {
    "local_sdk",
    "remote_sdk",
    "simulator_only",
    "unknown",
}
AKIDA_HOST_AUTH_MODES = {
    "none",
    "password",
    "ssh_key",
    "basic",
    "bearer_token",
}
BENIGN_SSH_WARNING_PREFIXES = ("Warning: Permanently added ",)
PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE = (
    "Overlay files were uploaded, but the user-space runtime did not become healthy. "
    "Restart the board or run restart-runtime manually, then check readiness again."
)
LEGACY_PYNQ_REMOTE_INSTALL_ROOT = "/opt/neurochip-pynq-agent"
LEGACY_PYNQ_REMOTE_VENV_PATH = f"{LEGACY_PYNQ_REMOTE_INSTALL_ROOT}/venv"
DEFAULT_PYNQ_REMOTE_PYNQ_VENV_DIRNAME = "pynq-venv"
LEGACY_PYNQ_REMOTE_OVERLAY_DIR = f"{LEGACY_PYNQ_REMOTE_INSTALL_ROOT}/overlays"
PYNQ_BOARD_STATES = {
    "unpaired",
    "reachable",
    "provisioning",
    "provision_failed",
    "runtime_installed",
    "overlay_missing",
    "ready",
    "degraded_optional_capability",
    "preflight_failed",
    "error",
}
AKIDA_HOST_STATES = {
    "unknown",
    "unpaired",
    "pending",
    "reachable",
    "bootstrapping",
    "installing_runtime",
    "verifying_sdk",
    "ready",
    "degraded",
    "degraded_optional_capability",
    "simulator_only",
    "blocked",
    "preflight_failed",
    "provision_failed",
    "error",
}
IMPORT_PROBE_SCRIPT = textwrap.dedent(
    f"""
    import importlib
    import json
    import sys

    required = json.loads(sys.argv[1])
    optional = json.loads(sys.argv[2])
    results = {{"required": [], "optional": []}}

    for bucket, imports in (("required", required), ("optional", optional)):
        for name in imports:
            outcome = {{"import": name, "ok": True}}
            try:
                importlib.import_module(name)
            except ModuleNotFoundError as exc:
                outcome = {{
                    "import": name,
                    "ok": False,
                    "kind": "missing",
                    "missing": exc.name,
                }}
            except Exception as exc:  # noqa: BLE001
                outcome = {{
                    "import": name,
                    "ok": False,
                    "kind": "error",
                    "error": f"{{type(exc).__name__}}: {{exc}}",
                }}
            results[bucket].append(outcome)

    print("{PREFLIGHT_SENTINEL}" + json.dumps(results, sort_keys=True))
    """
).strip()

#: The overlay the backend ships and the board is expected to run.
#:
#: Overlay-v1 is deliberately *not* accepted. It could not compute: its weight
#: port was never connected to anything in the block design, so every weight
#: the engine read was zero and the board returned silence that the app
#: displayed as a successful hardware run. A board still carrying v1 is told to
#: reinstall rather than allowed to produce meaningless results.
EXPECTED_PYNQ_OVERLAY_MANIFEST: dict[str, Any] = {
    "overlay_id": "snn_overlay_v2",
    "overlay_version": "2.0.0",
    "target_part": "xc7z020clg400-1",
    "supported_neuron_models": ("LIF",),
    "supported_weight_bit_widths": (8,),
    "max_neurons": 4096,
    "max_neurons_per_layer": 1024,
    "max_synapses": 262144,
    "max_populations": 4,
    "max_layers": 4,
    "dma_ip_name": "axi_dma_0",
    "snn_ip_name": "snn_engine_0",
    "register_map": {
        "dma_channel": "axi_dma_0",
    },
    "weight_layout": {
        "storage": "dma_ddr",
        "max_entries": 262144,
    },
    "layer_config_layout": {
        "words_per_layer": 8,
        "max_layers": 4,
    },
}

#: Overlay ids this launcher knows about but refuses, with the reason a user
#: should see. Keyed by overlay_id.
KNOWN_UNUSABLE_PYNQ_OVERLAYS: dict[str, str] = {
    "snn_overlay_v1": (
        "This board has overlay v1 installed, which cannot run a network: its "
        "weight memory was never wired to the compute engine, so it always "
        "returns empty output. Install the overlay again to replace it with v2."
    ),
}


# Compatibility aliases keep existing imports and monkey-patches working while
# the manifest contract implementation lives outside the server façade.
PynqLauncherRuntimeContract = _PynqLauncherRuntimeContract
AkidaLauncherRuntimeContract = _AkidaLauncherRuntimeContract
NeurochipLauncherRuntimeContract = _NeurochipLauncherRuntimeContract


def _load_neurochip_launcher_runtime_contract() -> NeurochipLauncherRuntimeContract:
    return load_neurochip_launcher_runtime_contract(MODULES_MANIFEST)


def _validate_pynq_overlay_manifest(payload: Any) -> None:
    if not isinstance(payload, dict):
        raise ValueError("manifest must be a JSON object")

    expected = EXPECTED_PYNQ_OVERLAY_MANIFEST

    overlay_id = payload.get("overlay_id")
    if isinstance(overlay_id, str) and overlay_id in KNOWN_UNUSABLE_PYNQ_OVERLAYS:
        raise ValueError(KNOWN_UNUSABLE_PYNQ_OVERLAYS[overlay_id])

    for key in (
        "overlay_id",
        "overlay_version",
        "target_part",
        "max_neurons",
        "max_neurons_per_layer",
        "max_synapses",
        "max_populations",
        "max_layers",
        "dma_ip_name",
        "snn_ip_name",
    ):
        if payload.get(key) != expected[key]:
            raise ValueError(f"{key} must be {expected[key]!r}")

    supported_models = tuple(payload.get("supported_neuron_models") or ())
    if supported_models != expected["supported_neuron_models"]:
        raise ValueError("supported_neuron_models must match the overlay contract")

    supported_weight_bit_widths = tuple(
        payload.get("supported_weight_bit_widths") or ()
    )
    if supported_weight_bit_widths != expected["supported_weight_bit_widths"]:
        raise ValueError("supported_weight_bit_widths must match the overlay contract")

    register_map = payload.get("register_map")
    if not isinstance(register_map, dict):
        raise ValueError("register_map must be an object")
    if register_map.get("dma_channel") != payload.get("dma_ip_name"):
        raise ValueError("register_map.dma_channel must match dma_ip_name")

    weight_layout = payload.get("weight_layout")
    if not isinstance(weight_layout, dict):
        raise ValueError("weight_layout must be an object")
    if weight_layout.get("storage") != expected["weight_layout"]["storage"]:
        raise ValueError(
            "weight_layout.storage must be 'dma_ddr'; the overlay-v1 MMIO weight "
            "window was never connected to the engine"
        )
    if (
        int(weight_layout.get("max_entries", -1))
        != expected["weight_layout"]["max_entries"]
    ):
        raise ValueError("weight_layout.max_entries must match max_synapses")

    layer_config_layout = payload.get("layer_config_layout")
    if not isinstance(layer_config_layout, dict):
        raise ValueError("layer_config_layout must be an object")
    for key, expected_value in expected["layer_config_layout"].items():
        if int(layer_config_layout.get(key, -1)) != expected_value:
            raise ValueError(f"layer_config_layout.{key} must be {expected_value}")


def _inspect_staged_pynq_overlay_package(staging_dir: Path) -> dict[str, Any]:
    base_dir = staging_dir.resolve()
    bitstream_path = base_dir / DEFAULT_STAGED_PYNQ_BITSTREAM_NAME
    hwh_path = base_dir / DEFAULT_STAGED_PYNQ_HWH_NAME
    manifest_path = base_dir / DEFAULT_STAGED_OVERLAY_MANIFEST

    issues: list[str] = []
    if not base_dir.exists():
        issues.append(f"staged overlay package directory not found at {base_dir}")
    if not bitstream_path.exists():
        issues.append(f"missing staged overlay bitstream at {bitstream_path}")
    if not hwh_path.exists():
        issues.append(f"missing staged overlay hardware handoff file at {hwh_path}")

    manifest_present = manifest_path.exists()
    manifest_valid = True
    if not manifest_present:
        manifest_valid = False
        issues.append(f"missing staged overlay manifest at {manifest_path}")
    else:
        try:
            decoded = json.loads(manifest_path.read_text(encoding="utf-8"))
            _validate_pynq_overlay_manifest(decoded)
        except (json.JSONDecodeError, ValueError, TypeError) as exc:
            manifest_valid = False
            issues.append(f"overlay manifest is invalid: {exc}")

    return {
        "stagingDir": str(base_dir),
        "bitstreamPath": str(bitstream_path),
        "hwhPath": str(hwh_path),
        "manifestPath": str(manifest_path),
        "bitstreamExists": bitstream_path.exists(),
        "hwhExists": hwh_path.exists(),
        "manifestPresent": manifest_present,
        "manifestValid": manifest_valid,
        "ready": not issues,
        "issues": issues,
    }


def _status_name(index: int) -> str:
    for name, value in STATUS_INDEX.items():
        if value == index:
            return name
    return "notInstalled"


def _normalize_pynq_board_state(value: Any, default_state: str) -> str:
    candidate = str(value or default_state).strip().lower()
    normalized_default = default_state.strip().lower() or "unpaired"
    return candidate if candidate in PYNQ_BOARD_STATES else normalized_default


def _normalize_akida_host_state(value: Any, default_state: str) -> str:
    candidate = str(value or default_state).strip().lower()
    normalized_default = default_state.strip().lower() or "unknown"
    return candidate if candidate in AKIDA_HOST_STATES else normalized_default


def _normalize_akida_runtime_mode(value: Any) -> str:
    candidate = str(value or "unknown").strip().lower()
    return candidate if candidate in AKIDA_RUNTIME_MODES else "unknown"


def _normalize_akida_host_auth_mode(value: Any, default_auth_mode: str) -> str:
    candidate = str(value or default_auth_mode).strip().lower()
    normalized_default = default_auth_mode.strip().lower() or "password"
    return candidate if candidate in AKIDA_HOST_AUTH_MODES else normalized_default


def _normalize_auth_mode(value: Any, default_auth_mode: str) -> str:
    candidate = str(value or default_auth_mode).strip().lower()
    normalized_default = default_auth_mode.strip().lower() or "password"
    return candidate if candidate in {"password", "ssh_key"} else normalized_default


def _default_akida_base_url(host: str, port: int | None = None) -> str:
    resolved_port = (
        port
        if port is not None
        else _load_neurochip_launcher_runtime_contract().akida.runtime_port
    )
    return f"http://{host}:{resolved_port}"


def _default_akida_control_url(host: str, port: int | None = None) -> str:
    resolved_port = (
        port
        if port is not None
        else _load_neurochip_launcher_runtime_contract().akida.control_port
    )
    return f"http://{host}:{resolved_port}"


def _default_runtime_api_url(host: str, port: int | None = None) -> str:
    resolved_port = (
        port
        if port is not None
        else _load_neurochip_launcher_runtime_contract().pynq.runtime_port
    )
    return f"http://{host}:{resolved_port}"


def _normalize_base_url(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""
    candidate = raw if "://" in raw else f"http://{raw}"
    parsed = urlparse(candidate)
    if not parsed.scheme or not parsed.netloc:
        return raw.rstrip("/")
    return parsed._replace(params="", query="", fragment="").geturl().rstrip("/")


def _normalize_runtime_api_url_override(
    host: str,
    raw: dict[str, Any],
    runtime_port: int,
) -> str:
    default_url = _default_runtime_api_url(host, runtime_port) if host else ""
    explicit_override = raw.get("runtimeApiUrlOverride")
    if explicit_override is not None:
        override = str(explicit_override).strip()
        return "" if not override or override == default_url else override

    legacy_runtime_api_url = str(raw.get("runtimeApiUrl") or "").strip()
    if legacy_runtime_api_url and legacy_runtime_api_url != default_url:
        return legacy_runtime_api_url
    return ""


def _effective_runtime_api_url(
    host: str,
    runtime_api_url_override: str,
    runtime_port: int,
) -> str:
    normalized_override = str(runtime_api_url_override or "").strip()
    if normalized_override:
        return normalized_override
    normalized_host = host.strip()
    return (
        _default_runtime_api_url(normalized_host, runtime_port)
        if normalized_host
        else ""
    )


def _pynq_user_space_upgrade_message(username: str) -> str:
    contract = _load_neurochip_launcher_runtime_contract().pynq
    normalized_username = username.strip() or contract.default_username
    return (
        "Runtime is installed in user space. "
        f"Enable passwordless sudo for '{normalized_username}', then re-run Provision "
        "Runtime to upgrade the board to systemd auto-start and launcher-managed restarts."
    )


def _akida_user_space_upgrade_message(username: str) -> str:
    normalized_username = username.strip() or "the configured SSH user"
    return (
        "Runtime is installed in user space. "
        f"Enable passwordless sudo for '{normalized_username}', then re-run Provision "
        "Runtime to upgrade the host to systemd auto-start and launcher-managed restarts."
    )


def _resolve_pynq_agent_health_timeout() -> float:
    raw = os.getenv("NEUROCHIP_PYNQ_HEALTH_TIMEOUT_SECONDS", "").strip()
    if not raw:
        return DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS
    try:
        parsed = float(raw)
    except ValueError:
        return DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS
    lower, upper = PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS
    return max(lower, min(upper, parsed))


def _resolve_pynq_preflight_timeout() -> float:
    raw = os.getenv("NEUROCHIP_PYNQ_PREFLIGHT_TIMEOUT_SECONDS", "").strip()
    if not raw:
        return DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS
    try:
        parsed = float(raw)
    except ValueError:
        return DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS
    lower, upper = PYNQ_PREFLIGHT_TIMEOUT_BOUNDS
    return max(lower, min(upper, parsed))


def _resolve_pynq_run_timeout() -> float:
    raw = os.getenv("NEUROCHIP_PYNQ_RUN_TIMEOUT_SECONDS", "").strip()
    if not raw:
        return DEFAULT_PYNQ_RUN_TIMEOUT_SECONDS
    try:
        parsed = float(raw)
    except ValueError:
        return DEFAULT_PYNQ_RUN_TIMEOUT_SECONDS
    lower, upper = PYNQ_RUN_TIMEOUT_BOUNDS
    return max(lower, min(upper, parsed))


def _default_pynq_remote_install_root(username: str) -> str:
    return _load_neurochip_launcher_runtime_contract().pynq.install_root_for(username)


def _normalize_pynq_board(raw: dict[str, Any]) -> dict[str, Any]:
    contract = _load_neurochip_launcher_runtime_contract().pynq
    host = str(raw.get("host", "")).strip()
    runtime_api_url_override = _normalize_runtime_api_url_override(
        host,
        raw,
        contract.runtime_port,
    )
    ssh_port = raw.get("sshPort", contract.ssh_port)
    if not isinstance(ssh_port, int):
        ssh_port = contract.ssh_port
    username = (
        str(raw.get("username") or contract.default_username).strip()
        or contract.default_username
    )
    remote_install_root = str(raw.get("remoteInstallRoot") or "").strip()
    if not remote_install_root or remote_install_root == contract.legacy_install_root:
        remote_install_root = contract.install_root_for(username)

    remote_venv_path = str(raw.get("remoteVenvPath") or "").strip()
    if not remote_venv_path or remote_venv_path == contract.legacy_venv_path():
        remote_venv_path = contract.agent_venv_path_for(remote_install_root)

    remote_pynq_venv_path = str(raw.get("remotePynqVenvPath") or "").strip()
    if not remote_pynq_venv_path:
        remote_pynq_venv_path = contract.runtime_venv_path_for(remote_install_root)

    remote_overlay_dir = str(raw.get("remoteOverlayDir") or "").strip()
    if not remote_overlay_dir or remote_overlay_dir == contract.legacy_overlay_dir():
        remote_overlay_dir = contract.overlay_dir_for(remote_install_root)

    remote_install_status_path = str(raw.get("remoteInstallStatusPath") or "").strip()
    if not remote_install_status_path:
        remote_install_status_path = contract.install_status_path_for(
            remote_install_root
        )

    remote_runtime_log_path = str(raw.get("remoteRuntimeLogPath") or "").strip()
    if not remote_runtime_log_path:
        remote_runtime_log_path = contract.runtime_log_path_for(remote_install_root)

    board = {
        "id": str(raw.get("id") or uuid4()),
        "displayName": str(raw.get("displayName") or host or "PYNQ Board").strip(),
        "host": host,
        "sshPort": ssh_port,
        "username": username,
        "authMode": _normalize_auth_mode(
            raw.get("authMode"),
            contract.default_auth_mode,
        ),
        "credentialRef": str(raw.get("credentialRef") or "").strip(),
        "password": str(raw.get("password") or ""),
        "sshKeyPath": str(raw.get("sshKeyPath") or "").strip(),
        "runtimeApiUrl": _effective_runtime_api_url(
            host,
            runtime_api_url_override,
            contract.runtime_port,
        ),
        "runtimeApiUrlOverride": runtime_api_url_override,
        "overlayVersion": str(raw.get("overlayVersion") or "").strip(),
        "state": _normalize_pynq_board_state(
            raw.get("state"),
            contract.default_state,
        ),
        "lastPreflightStatus": str(raw.get("lastPreflightStatus") or "").strip(),
        "lastPreflightMessage": str(raw.get("lastPreflightMessage") or "").strip(),
        "lastRuntimeMode": str(raw.get("lastRuntimeMode") or "").strip(),
        "lastStatus": raw.get("lastStatus")
        if isinstance(raw.get("lastStatus"), dict)
        else None,
        "remoteInstallRoot": remote_install_root,
        "remoteVenvPath": remote_venv_path,
        "remotePynqVenvPath": remote_pynq_venv_path,
        "remoteOverlayDir": remote_overlay_dir,
        "remoteInstallStatusPath": remote_install_status_path,
        "remoteRuntimeLogPath": remote_runtime_log_path,
        "remoteServiceName": str(
            raw.get("remoteServiceName") or contract.service_name
        ).strip(),
        "agentExecutableName": str(
            raw.get("agentExecutableName") or contract.agent_executable_name
        ).strip(),
        "isDefault": bool(raw.get("isDefault")),
    }
    return board


def _serialize_pynq_board(board: dict[str, Any]) -> dict[str, Any]:
    payload = dict(board)
    payload["runtimeApiUrlOverride"] = str(
        payload.get("runtimeApiUrlOverride") or ""
    ).strip()
    payload["runtimeApiUrl"] = _effective_runtime_api_url(
        str(payload.get("host") or "").strip(),
        str(payload.get("runtimeApiUrlOverride") or "").strip(),
        _load_neurochip_launcher_runtime_contract().pynq.runtime_port,
    )
    payload.pop("password", None)
    payload["hasPassword"] = bool(board.get("password"))
    return payload


def _ssh_failure_message(stdout_lines: list[str], stderr_lines: list[str]) -> str:
    non_benign_stderr = [
        line for line in stderr_lines if not _is_benign_ssh_warning_line(line)
    ]
    if non_benign_stderr:
        return "\n".join(non_benign_stderr).strip()
    if stdout_lines:
        return "\n".join(stdout_lines).strip()
    return "ssh command failed"


def _extract_install_status_from_output(output: str) -> dict[str, Any] | None:
    lines = output.splitlines()
    decoder = json.JSONDecoder()
    for index in range(len(lines) - 1, -1, -1):
        line = lines[index]
        if not line.startswith(INSTALL_STATUS_SENTINEL):
            continue
        raw_payload = line.removeprefix(INSTALL_STATUS_SENTINEL).strip()
        if not raw_payload:
            continue
        candidate = "\n".join([raw_payload, *lines[index + 1 :]]).strip()
        payload, _end = decoder.raw_decode(candidate)
        if not isinstance(payload, dict):
            raise RuntimeError("Install status sentinel must decode to an object")
        return payload
    return None


def _resolved_pynq_runtime_api_url(board: dict[str, Any]) -> str:
    return _effective_runtime_api_url(
        str(board.get("host") or "").strip(),
        str(board.get("runtimeApiUrlOverride") or "").strip(),
        _load_neurochip_launcher_runtime_contract().pynq.runtime_port,
    )


def _resolved_akida_base_url(host: dict[str, Any]) -> str:
    contract = _load_neurochip_launcher_runtime_contract().akida
    base_url = _normalize_base_url(host.get("baseUrl"))
    if base_url:
        return base_url
    normalized_host = str(host.get("host") or "").strip()
    if not normalized_host:
        return ""
    port = host.get("port", contract.runtime_port)
    if not isinstance(port, int):
        port = contract.runtime_port
    return _default_akida_base_url(normalized_host, port)


def _resolved_akida_control_api_url(host: dict[str, Any]) -> str:
    contract = _load_neurochip_launcher_runtime_contract().akida
    control_api_url = _normalize_base_url(host.get("controlApiUrl"))
    if control_api_url:
        return control_api_url
    normalized_host = str(host.get("host") or "").strip()
    if not normalized_host:
        return ""
    port = host.get("controlPort", contract.control_port)
    if not isinstance(port, int):
        port = contract.control_port
    return _default_akida_control_url(normalized_host, port)


# Keep the server import path stable while runtime clients and transport share
# one error type without importing this compatibility façade.
RuntimeRequestError = _RuntimeRequestError


def _describe_akida_preflight(verification: dict[str, Any]) -> str:
    sdk_status = str(verification.get("sdk_status") or "").strip().lower()
    bool(verification.get("sdk_available"))
    sdk_issue_detail = str(verification.get("sdk_issue_detail") or "").strip()
    raw_sdk_issues = verification.get("sdk_issues", [])
    if not isinstance(raw_sdk_issues, list):
        raw_sdk_issues = []
    sdk_issues = [str(issue).strip() for issue in raw_sdk_issues if str(issue).strip()]
    if _akida_hardware_runtime_ready(verification):
        return "Akida runtime mapping is ready."
    if sdk_issue_detail:
        return sdk_issue_detail
    if sdk_issues:
        return "Optional capability unavailable: " + ", ".join(sdk_issues)
    if sdk_status:
        return f"Optional capability unavailable: {sdk_status}"
    return "Optional capability unavailable on remote Akida host."


def _akida_hardware_runtime_ready(verification: dict[str, Any]) -> bool:
    sdk_status = str(verification.get("sdk_status") or "").strip().lower()
    runtime_target = str(verification.get("runtime_target") or "").strip().lower()
    raw_sdk_issues = verification.get("sdk_issues", [])
    if not isinstance(raw_sdk_issues, list):
        raw_sdk_issues = []
    return (
        bool(verification.get("sdk_available"))
        and runtime_target == "hardware"
        and (sdk_status == "deployable" or not raw_sdk_issues)
    )


def _preflight_status_for_akida_verification(verification: dict[str, Any]) -> str:
    if _akida_hardware_runtime_ready(verification):
        return PREFLIGHT_OK
    return PREFLIGHT_DEGRADED


def _akida_host_state_for_status(
    host: dict[str, Any],
    status: dict[str, Any],
) -> str:
    job_state = str(status.get("state") or "").strip().lower()
    last_preflight_status = str(host.get("lastPreflightStatus") or "").strip().lower()
    if job_state in {"running", "mapped", "constructed"}:
        return "ready"
    if job_state == "failed":
        return "error"
    if job_state in {"sdk_loading", "model_mapping"}:
        return "reachable"
    if last_preflight_status == PREFLIGHT_OK:
        return "ready"
    if last_preflight_status == PREFLIGHT_DEGRADED:
        return "degraded_optional_capability"
    return "reachable"


def _normalize_akida_capability_snapshot(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    return {
        "hostSupported": bool(
            raw.get("hostSupported", raw.get("host_supported", False))
        ),
        "pythonSupported": bool(
            raw.get("pythonSupported", raw.get("python_supported", False))
        ),
        "tensorflowAvailable": bool(
            raw.get("tensorflowAvailable", raw.get("tensorflow_available", False))
        ),
        "cnn2snnAvailable": bool(
            raw.get("cnn2snnAvailable", raw.get("cnn2snn_available", False))
        ),
        "akidaModelsAvailable": bool(
            raw.get("akidaModelsAvailable", raw.get("akida_models_available", False))
        ),
        "recommendedRuntime": _normalize_akida_runtime_mode(
            raw.get("recommendedRuntime", raw.get("recommended_runtime"))
        ),
    }


def _default_akida_host_display_name(runtime_api_url: str) -> str:
    parsed = urlparse(runtime_api_url)
    label = parsed.netloc.strip() or parsed.path.strip()
    return label or "Akida Host"


def _normalize_akida_host(raw: dict[str, Any]) -> dict[str, Any]:
    contract = _load_neurochip_launcher_runtime_contract().akida
    runtime_api_url = _normalize_base_url(raw.get("runtimeApiUrl"))
    control_api_url = _normalize_base_url(raw.get("controlApiUrl"))
    base_url = _normalize_base_url(raw.get("baseUrl"))
    host = str(raw.get("host") or "").strip()
    port = raw.get("port", contract.runtime_port)
    if not isinstance(port, int):
        port = contract.runtime_port
    ssh_port = raw.get("sshPort", contract.ssh_port)
    if not isinstance(ssh_port, int):
        ssh_port = contract.ssh_port
    control_port = raw.get("controlPort", contract.control_port)
    if not isinstance(control_port, int):
        control_port = contract.control_port
    parsed_control_url = urlparse(control_api_url) if control_api_url else None
    try:
        parsed_control_port = (
            parsed_control_url.port if parsed_control_url is not None else None
        )
    except ValueError:
        parsed_control_port = None
    if parsed_control_url is not None and parsed_control_port == 8090:
        # Studio briefly stored the suite launcher port as the paired host's
        # Akida control endpoint. 8090 is owned by launcher-control; paired
        # Akida hosts use the manifest-backed control port (currently 8091).
        control_api_url = _default_akida_control_url(
            parsed_control_url.hostname or host,
            control_port,
        )
    if not base_url and runtime_api_url:
        base_url = runtime_api_url
    if not runtime_api_url and base_url:
        runtime_api_url = base_url
    parsed_base_url = urlparse(base_url) if base_url else None
    if parsed_base_url is not None and parsed_base_url.hostname:
        if raw.get("baseUrl") is not None:
            host = parsed_base_url.hostname
        else:
            host = host or parsed_base_url.hostname
        if not isinstance(raw.get("port"), int) and parsed_base_url.port is not None:
            port = parsed_base_url.port
    elif host and not base_url:
        base_url = _default_akida_base_url(host, port)
        runtime_api_url = runtime_api_url or base_url
    if not control_api_url and host:
        control_api_url = _default_akida_control_url(host, control_port)
    remote_install_root = str(
        raw.get("remoteInstallRoot") or contract.install_root
    ).strip()
    capability_snapshot = _normalize_akida_capability_snapshot(
        raw.get("capabilitySnapshot", raw.get("capability_snapshot"))
    )
    runtime_mode = _normalize_akida_runtime_mode(
        raw.get("runtimeMode") or (capability_snapshot or {}).get("recommendedRuntime")
    )
    password = str(raw.get("password") or "")
    auth_mode = _normalize_akida_host_auth_mode(
        raw.get("authMode"),
        contract.default_auth_mode,
    )
    if password and auth_mode not in {"password", "ssh_key"}:
        auth_mode = "password"
    return {
        "id": str(raw.get("id") or uuid4()),
        "displayName": str(
            raw.get("displayName")
            or _default_akida_host_display_name(runtime_api_url or base_url)
        ).strip(),
        "host": host,
        "port": port,
        "sshPort": ssh_port,
        "controlPort": control_port,
        "username": str(raw.get("username") or "").strip(),
        "baseUrl": base_url,
        "runtimeApiUrl": runtime_api_url,
        "controlApiUrl": control_api_url,
        "authMode": auth_mode,
        "credentialRef": str(raw.get("credentialRef") or "").strip(),
        "password": password,
        "sshKeyPath": str(raw.get("sshKeyPath") or "").strip(),
        "remoteInstallRoot": remote_install_root,
        "remoteVenvPath": str(
            raw.get("remoteVenvPath") or contract.venv_path_for(remote_install_root)
        ).strip(),
        "serviceUser": str(raw.get("serviceUser") or contract.service_user).strip(),
        "runtimeServiceName": str(
            raw.get("runtimeServiceName") or contract.runtime_service_name
        ).strip(),
        "controlServiceName": str(
            raw.get("controlServiceName") or contract.control_service_name
        ).strip(),
        "tokenPath": str(
            raw.get("tokenPath") or contract.token_path_for(remote_install_root)
        ).strip(),
        "installStatusPath": str(
            raw.get("installStatusPath")
            or contract.install_status_path_for(remote_install_root)
        ).strip(),
        "hostOs": str(raw.get("hostOs") or "").strip(),
        "pythonVersion": str(raw.get("pythonVersion") or "").strip(),
        "runtimeMode": runtime_mode,
        "state": _normalize_akida_host_state(
            raw.get("state"),
            contract.default_state,
        ),
        "lastPreflightStatus": str(raw.get("lastPreflightStatus") or "").strip(),
        "lastPreflightMessage": str(raw.get("lastPreflightMessage") or "").strip(),
        "lastSdkStatus": str(raw.get("lastSdkStatus") or "").strip(),
        "lastRuntimeTarget": str(raw.get("lastRuntimeTarget") or "").strip(),
        "lastStatus": raw.get("lastStatus")
        if isinstance(raw.get("lastStatus"), dict)
        else None,
        "lastReadinessMessage": str(raw.get("lastReadinessMessage") or "").strip(),
        "lastVerifiedAt": str(raw.get("lastVerifiedAt") or "").strip(),
        "lastInstallStatus": raw.get("lastInstallStatus")
        if isinstance(raw.get("lastInstallStatus"), dict)
        else None,
        "installedRuntimeVersion": str(
            raw.get("installedRuntimeVersion")
            or (
                raw.get("lastInstallStatus", {}).get("packageVersion")
                if isinstance(raw.get("lastInstallStatus"), dict)
                else ""
            )
        ).strip(),
        "availableRuntimeVersion": str(
            raw.get("availableRuntimeVersion") or ""
        ).strip(),
        "runtimeArtifactSha256": str(raw.get("runtimeArtifactSha256") or "").strip(),
        "runtimeUpdateState": str(raw.get("runtimeUpdateState") or "").strip(),
        "lastRuntimeUpdateJob": raw.get("lastRuntimeUpdateJob")
        if isinstance(raw.get("lastRuntimeUpdateJob"), dict)
        else None,
        "capabilitySnapshot": capability_snapshot,
        "isDefault": bool(raw.get("isDefault")),
        "autoDiscovered": bool(raw.get("autoDiscovered", False)),
        # The card is on the same physical machine as launcher-control itself. SSH
        # from inside the container to the host's own LAN IP is refused (hairpin
        # NAT), so connections must instead go through the docker/podman gateway
        # alias — see `_akida_ssh_connect_host` in akida_host_service.py.
        "sameHostAsBackend": bool(raw.get("sameHostAsBackend")),
    }


def _serialize_akida_host(host: dict[str, Any]) -> dict[str, Any]:
    payload = dict(host)
    capability_snapshot = payload.get("capabilitySnapshot")
    payload["capabilitySnapshot"] = (
        dict(capability_snapshot) if isinstance(capability_snapshot, dict) else None
    )
    payload["baseUrl"] = _resolved_akida_base_url(payload)
    payload["runtimeApiUrl"] = str(
        payload.get("runtimeApiUrl") or _resolved_akida_base_url(payload)
    ).strip()
    payload["controlApiUrl"] = str(
        payload.get("controlApiUrl") or _resolved_akida_control_api_url(payload)
    ).strip()
    payload["host"] = str(
        payload.get("host") or urlparse(payload["baseUrl"]).hostname or ""
    ).strip()
    payload["hasPassword"] = bool(payload.get("password"))
    payload.pop("password", None)
    return payload


def _mujoco_available() -> bool:
    return any(
        (REPO_ROOT / candidate).exists()
        for candidate in (
            ".mujoco",
            "mujoco",
        )
    ) or any(
        os.path.exists(candidate)
        for candidate in (
            os.path.expanduser("~/.mujoco"),
            "/Applications/MuJoCo.app",
        )
    )


def _describe_pynq_preflight(preflight: dict[str, Any]) -> str:
    status = str(preflight.get("preflight_status") or "").strip().lower()
    message = str(preflight.get("preflight_message") or "").strip()
    overlay_assets = preflight.get("overlay_assets")
    if status == PREFLIGHT_OK:
        return "preflight ready"
    if status == PREFLIGHT_DEGRADED:
        return (
            f"degraded optional capability: {message}"
            if message
            else "degraded optional capability"
        )
    if isinstance(overlay_assets, dict) and not overlay_assets.get(
        "ready_for_hardware", False
    ):
        return (
            f"preflight failed: overlay assets missing; {message}"
            if message
            else "preflight failed: overlay assets missing; install overlay assets next"
        )
    return f"preflight failed: {message}" if message else "preflight failed"


def _running_in_bundled_mode() -> bool:
    return str(os.environ.get("NMTK_BUNDLED_MODE") or "").strip().lower() in {
        "1",
        "true",
        "yes",
    }


def _default_user_data_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "NeuroToolkit"
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
        if base:
            return Path(base) / "NeuroToolkit"
        return Path.home() / "AppData" / "Local" / "NeuroToolkit"
    xdg_data_home = str(os.environ.get("XDG_DATA_HOME") or "").strip()
    if xdg_data_home:
        return Path(xdg_data_home) / "NeuroToolkit"
    return Path.home() / ".local" / "share" / "NeuroToolkit"


DEFAULT_LAVA_BACKEND_PORT = 8012


def _lava_backend_base_url() -> str:
    explicit = (
        str(os.environ.get("NEUROCNL_LAVA_WORKER_URL") or "").strip()
        or str(os.environ.get("LAVA_BACKEND_URL") or "").strip()
    )
    if explicit:
        return explicit.rstrip("/")
    port = str(os.environ.get("LAVA_BACKEND_PORT") or DEFAULT_LAVA_BACKEND_PORT).strip()
    return f"http://127.0.0.1:{port}"


def _lava_backend_reachable(base_url: str | None = None) -> bool:
    health_url = f"{(base_url or _lava_backend_base_url()).rstrip('/')}/health"
    try:
        with urllib.request.urlopen(health_url, timeout=2.0) as response:
            if int(response.status) != HTTPStatus.OK:
                return False
            body = response.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, socket.timeout, ValueError):
        return False
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return True
    if isinstance(payload, dict) and "lava_importable" in payload:
        return bool(payload.get("lava_importable"))
    return True


def _resolved_lava_worker_url() -> str | None:
    explicit = str(os.environ.get("NEUROCNL_LAVA_WORKER_URL") or "").strip()
    if explicit:
        return explicit.rstrip("/")
    local_url = f"http://127.0.0.1:{DEFAULT_LAVA_BACKEND_PORT}"
    if _lava_backend_reachable(local_url):
        return local_url
    return None


def _is_benign_ssh_warning_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    return any(stripped.startswith(prefix) for prefix in BENIGN_SSH_WARNING_PREFIXES)


from .suite_api_service import (
    DEFAULT_SUITE_API_PORT,
    SUITE_API_STARTUP_TIMEOUT_SECONDS,
    SUITE_API_STATUS_DISABLED,
    SUITE_API_STATUS_PREFLIGHT_FAILED,
    SUITE_API_STATUS_READY,
    SUITE_API_STATUS_STARTING,
    SuiteApiServiceMixin,
    _suite_api_dev_install_paths,
    _suite_api_env_dir,
    _suite_api_env_fingerprint,
    _suite_api_env_python,
    _suite_api_env_stamp,
    _suite_api_pythonpath,
)
from .module_environment import (
    _candidate_environment_files,
    _current_platform_key,
    _effective_port,
    _external_service_health_url,
    _is_externally_managed_service,
    _missing_python_message,
    _module_environment_exists,
    _module_install_dir,
    _module_install_extras,
    _module_install_strategy,
    _module_optional_imports,
    _module_pyproject_path,
    _module_python_path,
    _module_required_imports,
    _module_run_dir,
    _module_start_strategy,
    _module_uses_poetry,
    _module_venv_pip,
    _module_venv_python,
    _normalize_akida_runtime_config,
    _normalize_akida_runtime_state,
    _normalized_import_list,
    _poetry_command,
    _poetry_env_python,
    _poetry_fallback_env_root,
    _uvicorn_host,
    _version_matches_range,
)
from .process_supervision import (
    ManagedProcess,
    ProcessSupervisionMixin,
    _dedupe_messages,
    _message_from_probe_outcome,
    _status_for_health_response,
)
from .doctor_service import _render_doctor_report
from .module_install import ModuleInstallMixin
from .module_lifecycle import ModuleLifecycleMixin
from .module_registry import ModuleRegistryMixin, _resolve_remote_module_version
from .akida_host_service import AkidaServiceMixin
from .akida_runtime_update_jobs import AkidaRuntimeUpdateJobsMixin
from .pynq_service import PynqServiceMixin
from .settings_service import SettingsServiceMixin
from .preflight_types import PreflightResult


class LauncherControlState(
    AkidaRuntimeUpdateJobsMixin,
    AkidaServiceMixin,
    ModuleInstallMixin,
    ModuleLifecycleMixin,
    ModuleRegistryMixin,
    ProcessSupervisionMixin,
    PynqServiceMixin,
    SettingsServiceMixin,
    SuiteApiServiceMixin,
    WorkspaceStateMixin,
):
    """In-memory state and lifecycle orchestration for module control."""

    def __init__(
        self,
        remote_version_resolver: Callable[[dict[str, Any]], str | None] | None = None,
        *,
        manage_suite_api: bool = False,
        external_probe_host: str | None = None,
    ) -> None:
        self._lock = threading.RLock()
        self._terminal_lock = threading.Lock()
        self._remote_version_resolver = (
            remote_version_resolver or _resolve_remote_module_version
        )
        self._manage_suite_api = manage_suite_api
        self._external_probe_host = external_probe_host or "127.0.0.1"
        self._suite_api_status = (
            SUITE_API_STATUS_STARTING if manage_suite_api else SUITE_API_STATUS_DISABLED
        )
        self._suite_api_message: str | None = None
        self._suite_api_process: subprocess.Popen[str] | None = None
        self._suite_api_logs: collections.deque[str] = collections.deque(
            maxlen=LOG_LINE_LIMIT
        )
        # Akida runtime process managed separately from module processes so that
        # shutdown() can terminate it without going through stop_module().
        self._akida_runtime_process: subprocess.Popen[str] | None = None
        self._modules = self._load_modules()
        self._processes: dict[str, ManagedProcess] = {}
        self._logs: dict[str, collections.deque[str]] = collections.defaultdict(
            lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
        )
        self._tasks: dict[str, threading.Thread] = {}
        self._settings = self._load_settings()
        self._workspace_file = WORKSPACE_FILE
        self._workspace = self._load_workspace()
        self._deployment = DeploymentService(
            store=DeploymentStore(
                DEPLOYMENT_STATE_FILE,
                FileBackedSecretStore(DEPLOYMENT_SECRET_FILE),
            ),
            repo_root=REPO_ROOT,
        )
        self._shutdown = threading.Event()
        self._hardware_discovery_done: bool = False
        self._hardware_discovery_lock = threading.Lock()
        self._health_thread = threading.Thread(
            target=self._health_poll_loop,
            name="launcher-control-health",
            daemon=True,
        )
        self._health_thread.start()
        threading.Thread(
            target=self._auto_discover_local_hardware,
            name="launcher-hardware-discovery",
            daemon=True,
        ).start()
        if self._manage_suite_api:
            threading.Thread(
                target=self._ensure_suite_api_ready,
                name="launcher-control-suite-api",
                daemon=True,
            ).start()

    def shutdown(self) -> None:
        self._shutdown.set()
        with self._lock:
            module_ids = list(self._processes.keys())
        for module_id in module_ids:
            self.stop_module(module_id)
        if (
            self._suite_api_process is not None
            and self._suite_api_process.poll() is None
        ):
            self._suite_api_process.terminate()
            try:
                self._suite_api_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._suite_api_process.kill()
                self._suite_api_process.wait(timeout=5)
        if (
            self._akida_runtime_process is not None
            and self._akida_runtime_process.poll() is None
        ):
            self._akida_runtime_process.terminate()
            try:
                self._akida_runtime_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._akida_runtime_process.kill()
                self._akida_runtime_process.wait(timeout=5)

    def get_settings(self) -> dict[str, Any]:
        with self._lock:
            artifact = None
            if str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip():
                try:
                    artifact = self._neurochip_runtime_artifact()
                except (FileNotFoundError, RuntimeError, ValueError):
                    artifact = None
            if artifact is not None:
                for host in self._settings["akidaHosts"]:
                    host["availableRuntimeVersion"] = artifact.version
            return {
                "logLevel": self._settings["logLevel"],
                "mujocoAvailable": self._settings["mujocoAvailable"],
                "pythonAvailable": self._settings["pythonAvailable"],
                "suiteApiStatus": self._suite_api_status,
                "suiteApiMessage": self._suite_api_message,
                "backendDeploymentReady": self._deployment.is_ready(),
                "selectedBackendDeploymentTarget": self._deployment.selected_target(),
                "pynqBoards": [
                    _serialize_pynq_board(board)
                    for board in self._settings["pynqBoards"]
                ],
                "akidaHosts": [
                    _serialize_akida_host(host) for host in self._settings["akidaHosts"]
                ],
                "selectedAkidaHostId": self._settings["selectedAkidaHostId"],
                "selectedPynqBoardId": self._settings["selectedPynqBoardId"],
            }

    # ------------------------------------------------------------------
    # Hardware auto-discovery
    # ------------------------------------------------------------------

    def _purge_auto_discovered_hosts(self) -> None:
        """Remove auto-discovered host entries so stale entries from a previous session
        never appear as failures before the current session's discovery has run."""
        with self._lock:
            before = self._settings.get("akidaHosts", [])
            after = [h for h in before if not h.get("autoDiscovered")]
            if len(after) != len(before):
                self._settings["akidaHosts"] = after
                self._persist_settings()

    def _auto_discover_local_hardware(self) -> None:
        """Probe local hardware runtime services and auto-register detected hosts.

        Probes each hardware type's runtime service directly on its well-known port
        (e.g. Akida on port 8002) without routing through the Neurochip FastAPI layer.
        Retries for up to ~30 s to allow services that start concurrently with the
        launcher to become ready.  Called from a daemon thread at startup and from
        POST /api/launcher/hardware/discover.
        """
        with self._hardware_discovery_lock:
            if self._hardware_discovery_done:
                return
            self._hardware_discovery_done = True

        try:
            self._auto_discover_local_hardware_impl()
        except Exception as exc:  # noqa: BLE001
            print(
                f"[hardware-discovery] Unexpected error during hardware discovery: {exc}",
                file=sys.stderr,
                flush=True,
            )

    def _auto_discover_local_hardware_impl(self) -> None:
        """Implementation body for _auto_discover_local_hardware."""
        # Purge stale auto-discovered entries from a previous session first so
        # they never show as "connection refused" before re-validation completes.
        self._purge_auto_discovered_hosts()

        contract = _load_neurochip_launcher_runtime_contract()
        probe_host = self._external_probe_host

        # --- Akida: probe the neurochip-akida-host runtime service on its own port ---
        akida_runtime_port = contract.akida.runtime_port  # 8002

        # Prefer the Docker-internal service URL when NEUROCHIP_HW_WORKER_URL is
        # configured. This may point at either the containerized stub worker
        # (no Akida SDK, always simulator-absent) or, on boxes with a real card,
        # the native neurochip.service via host.docker.internal (see
        # docker-compose.akida-native.yml) — either way it may legitimately be
        # hardware or the SDK's own AKD1000() simulator fallback, so both should
        # register (require_hardware=False below).
        # When the env var is absent we are in local-dev mode: construct the URL
        # from external_probe_host and try to auto-start the venv if present.
        _docker_worker_url = os.environ.get("NEUROCHIP_HW_WORKER_URL", "").strip()
        _worker_api_key = os.environ.get("NEUROCHIP_HW_WORKER_API_KEY", "").strip()
        if _docker_worker_url:
            akida_base_url = _docker_worker_url.rstrip("/")
            # Lava-backend has a 120 s start_period that gates neurochip-hw-worker;
            # allow up to 2 min of retries so Docker mode always survives a cold start.
            _probe_attempts = 24
        else:
            akida_base_url = f"http://{probe_host}:{akida_runtime_port}"
            _probe_attempts = 6  # 30 s — sufficient for local dev
            # Auto-start the local venv only when no Docker worker URL is configured.
            with self._lock:
                runtime_already_managed = self._akida_runtime_process is not None
            neurochip_module = self._modules.get("Neurochip")
            if neurochip_module is not None and not runtime_already_managed:
                self._start_local_akida_runtime(neurochip_module, akida_runtime_port)

        akida_status_url = f"{akida_base_url}/api/neurochip/akida/status"

        for _attempt in range(_probe_attempts):
            if self._shutdown.is_set():
                return
            try:
                _req = urllib.request.Request(
                    akida_status_url,
                    headers={"X-API-Key": _worker_api_key} if _worker_api_key else {},
                )
                with urllib.request.urlopen(_req, timeout=5) as resp:
                    body: dict[str, Any] = json.loads(
                        resp.read().decode("utf-8", errors="replace")
                    )
                    self._maybe_register_local_akida(
                        akida_base_url,
                        body,
                        require_hardware=not bool(_docker_worker_url),
                    )
                    break
            except urllib.error.HTTPError:
                # Service is up but returned an error — hardware likely unavailable.
                break
            except (urllib.error.URLError, OSError, TimeoutError):
                # Service not yet up — wait and retry.
                self._shutdown.wait(5.0)

    def _start_local_akida_runtime(
        self, neurochip_module: dict[str, Any], runtime_port: int
    ) -> None:
        """Spawn the Neurochip Akida runtime service locally on *runtime_port*.

        Called during hardware auto-discovery when Neurochip is installed and
        the runtime is not yet listening.  The process is stored in
        self._akida_runtime_process and terminated by shutdown().

        stdout/stderr are discarded to prevent pipe-buffer stalls; uvicorn
        writes its own structured logs internally.
        """
        python_path = _module_venv_python(neurochip_module)
        if not python_path.exists():
            print(
                "[akida-runtime] Neurochip venv not found — skipping auto-start.",
                flush=True,
            )
            return
        run_dir = _module_run_dir(neurochip_module)
        log_level = str(self._settings.get("logLevel", "info"))
        command = [
            str(python_path),
            "-m",
            "uvicorn",
            "neurochip.app.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(runtime_port),
            "--log-level",
            log_level,
        ]
        try:
            process = subprocess.Popen(
                command,
                cwd=str(run_dir),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
            )
            with self._lock:
                self._akida_runtime_process = process
            print(
                f"[akida-runtime] Started Neurochip Akida runtime on port {runtime_port} "
                f"(pid {process.pid}).",
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001
            print(f"[akida-runtime] Failed to start: {exc}", flush=True)

    def _maybe_register_local_akida(
        self,
        runtime_base_url: str,
        status: dict[str, Any],
        require_hardware: bool = True,
    ) -> None:
        """Auto-register a local Akida host entry.

        Uses the runtime service URL directly so that preflight checks hit the
        same service that was probed. The Akida host control service remains on
        its manifest-backed port, independently of launcher-control's host port.

        *require_hardware* — when True (local-dev default) only registers if
        the runtime reports physical hardware.  Set to False in Docker mode so
        that simulator containers are also registered as connectable hosts.
        """
        if require_hardware and status.get("runtimeTarget") != "hardware":
            return

        auto_id = "local-akida-auto"
        with self._lock:
            existing = self._settings.get("akidaHosts", [])
            if any(h["id"] == auto_id for h in existing):
                return
            is_first = len(existing) == 0

        device_info = str(status.get("deviceInfo") or "BrainChip Akida").strip()
        try:
            self.create_akida_host(
                {
                    "id": auto_id,
                    "displayName": f"Local Akida — {device_info}",
                    "runtimeApiUrl": runtime_base_url,
                    "controlApiUrl": "",
                    "autoDiscovered": True,
                    "isDefault": is_first,
                }
            )
            print(
                f"[hardware-discovery] Auto-registered local Akida host: {device_info}",
                flush=True,
            )
        except ValueError:
            pass  # Already registered via a concurrent call or duplicate id.

    def list_pynq_boards(self) -> list[dict[str, Any]]:
        with self._lock:
            boards = self._settings.get("pynqBoards", [])
            return [_serialize_pynq_board(board) for board in boards]

    def get_pynq_board(self, board_id: str) -> dict[str, Any]:
        with self._lock:
            board = self._get_pynq_board(board_id)
            return _serialize_pynq_board(board)

    def create_pynq_board(self, payload: dict[str, Any]) -> dict[str, Any]:
        board = _normalize_pynq_board(payload)
        if not board["host"]:
            raise ValueError("PYNQ board host is required")
        with self._lock:
            boards = self._settings["pynqBoards"]
            if any(existing["id"] == board["id"] for existing in boards):
                raise ValueError(f"PYNQ board '{board['id']}' already exists")
            if board.get("isDefault"):
                for existing in boards:
                    existing["isDefault"] = False
            boards.append(board)
            if not self._settings.get("selectedPynqBoardId"):
                self._settings["selectedPynqBoardId"] = board["id"]
            self._persist_settings()
            return _serialize_pynq_board(board)

    def update_pynq_board(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        with self._lock:
            board = self._get_pynq_board(board_id)
            normalized = self._normalize_updated_pynq_board(
                board, {"id": board_id, **payload}
            )
            if normalized.get("isDefault"):
                for existing in self._settings.get("pynqBoards", []):
                    if existing["id"] != board_id:
                        existing["isDefault"] = False
            board.clear()
            board.update(normalized)
            self._persist_settings()
            return _serialize_pynq_board(board)

    def delete_pynq_board(self, board_id: str) -> None:
        with self._lock:
            boards = self._settings["pynqBoards"]
            next_boards = [board for board in boards if board["id"] != board_id]
            if len(next_boards) == len(boards):
                raise KeyError(f"Unknown PYNQ board '{board_id}'")
            self._settings["pynqBoards"] = next_boards
            if self._settings.get("selectedPynqBoardId") == board_id:
                self._settings["selectedPynqBoardId"] = (
                    next_boards[0]["id"] if next_boards else None
                )
            self._persist_settings()

    def _get_pynq_board(self, board_id: str) -> dict[str, Any]:
        for board in self._settings.get("pynqBoards", []):
            if board["id"] == board_id:
                return board
        raise KeyError(f"Unknown PYNQ board '{board_id}'")

    def _update_pynq_board_fields(self, board_id: str, **fields: Any) -> dict[str, Any]:
        with self._lock:
            board = self._get_pynq_board(board_id)
            normalized = self._normalize_updated_pynq_board(
                board, {"id": board_id, **fields}
            )
            board.clear()
            board.update(normalized)
            self._persist_settings()
            return dict(board)

    def _normalize_updated_pynq_board(
        self,
        board: dict[str, Any],
        updates: dict[str, Any],
    ) -> dict[str, Any]:
        merged = dict(board)
        merged.update(updates)
        if (
            "runtimeApiUrlOverride" not in updates
            and "runtimeApiUrl" not in updates
            and not str(board.get("runtimeApiUrlOverride") or "").strip()
        ):
            merged.pop("runtimeApiUrl", None)
        return _normalize_pynq_board(merged)

    def list_deployment_targets(self) -> list[dict[str, Any]]:
        return self._deployment.list_targets()

    def create_deployment_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.create_target(payload)

    def update_deployment_target(
        self, target_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._deployment.update_target(target_id, payload)

    def delete_deployment_target(self, target_id: str) -> None:
        self._deployment.delete_target(target_id)

    def deployment_preflight(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.preflight(payload)

    def bootstrap_remote_deploy_user(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.bootstrap_remote_user(payload)

    def create_deployment_job(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.create_job(payload)

    def get_deployment_job(self, job_id: str) -> dict[str, Any]:
        return self._deployment.get_job(job_id)

    def cancel_deployment_job(self, job_id: str) -> dict[str, Any]:
        return self._deployment.cancel_job(job_id)

    def retry_deployment_job(self, job_id: str) -> dict[str, Any]:
        return self._deployment.retry_job(job_id)

    def deployment_job_events(self, job_id: str) -> list[str]:
        return self._deployment.job_events(job_id)


class LauncherControlServer(ThreadingHTTPServer):
    """HTTP server bound to a shared launcher state."""

    daemon_threads = True

    def __init__(
        self,
        server_address: tuple[str, int],
        manage_suite_api: bool = True,
        external_probe_host: str | None = None,
    ) -> None:
        self.state = LauncherControlState(
            manage_suite_api=manage_suite_api, external_probe_host=external_probe_host
        )
        super().__init__(server_address, LauncherControlHandler)

    def server_close(self) -> None:
        self.state.shutdown()
        super().server_close()


def create_server(
    host: str,
    port: int,
    manage_suite_api: bool = True,
    external_probe_host: str | None = None,
) -> LauncherControlServer:
    return LauncherControlServer(
        (host, port),
        manage_suite_api=manage_suite_api,
        external_probe_host=external_probe_host,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Launcher control service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8091)
    parser.add_argument(
        "--doctor",
        action="store_true",
        help="Run a non-mutating launcher environment diagnostic and exit",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit doctor output as JSON when used with --doctor",
    )
    parser.add_argument(
        "--manage-suite-api",
        action="store_true",
        default=True,
        help="Manage the suite_api lifecycle (default: True)",
    )
    parser.add_argument(
        "--no-manage-suite-api",
        action="store_false",
        dest="manage_suite_api",
        help="Do not manage the suite_api lifecycle",
    )
    parser.add_argument(
        "--external-probe-host",
        default=None,
        help="Hostname or IP to use when probing externally managed services (e.g. Jupyter on a remote host). Defaults to 127.0.0.1.",
    )
    args = parser.parse_args(argv)
    os.environ.setdefault("NMTK_UVICORN_HOST", str(args.host).strip() or "0.0.0.0")

    if args.doctor:
        state = LauncherControlState()
        try:
            report = state.doctor_report()
        finally:
            state.shutdown()
        if args.json:
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            print(_render_doctor_report(report))
        return 1 if report["fatalCount"] else 0

    server = create_server(
        args.host,
        args.port,
        manage_suite_api=args.manage_suite_api,
        external_probe_host=args.external_probe_host,
    )
    print(f"Launcher control service listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
