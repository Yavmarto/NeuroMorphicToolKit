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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse, urlunparse
from uuid import uuid4

import tomllib

from .deployment_service import DeploymentService
from .deployment_store import DeploymentStore, FileBackedSecretStore
from .provisioning_helpers import (
    build_akida_host_bundle,
    build_pynq_agent_bundle,
    build_pynq_user_space_agent_launch_command,
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

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULES_MANIFEST = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
STATE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "module_states.json"
SETTINGS_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
WORKSPACE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "workspace_state.json"
DEPLOYMENT_STATE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "deployment_state.json"
DEPLOYMENT_SECRET_FILE = REPO_ROOT / ".nmtk" / "deployment_secrets.json"

DEFAULT_CONTROL_LOG_LEVEL = "info"
DEFAULT_SUITE_API_PORT = 9000
HEALTH_POLL_SECONDS = 5.0
STARTUP_GRACE_SECONDS = 12.0
SUITE_API_STARTUP_TIMEOUT_SECONDS = 120.0
LOG_LINE_LIMIT = 400
PREFLIGHT_OK = "ok"
PREFLIGHT_DEGRADED = "degraded"
PREFLIGHT_FAILED = "failed"
SUITE_API_STATUS_DISABLED = "disabled"
SUITE_API_STATUS_STARTING = "starting"
SUITE_API_STATUS_READY = "ready"
SUITE_API_STATUS_PREFLIGHT_FAILED = "preflight_failed"
SUPPORTED_INSTALL_STRATEGIES = {"pip"}
SUPPORTED_START_STRATEGIES = {"uvicorn", "none"}
PREFLIGHT_SENTINEL = "NMTK_PREFLIGHT_JSON="
INSTALL_STATUS_SENTINEL = "INSTALL_STATUS_JSON="
DEFAULT_AKIDA_HOST_PORT = 8002
DEFAULT_AKIDA_CONTROL_PORT = 8090
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
GITHUB_API_PAGE_SIZE = 100
GITHUB_API_TIMEOUT_SECONDS = 3.0
GITHUB_API_ACCEPT = "application/vnd.github+json"
GITHUB_USER_AGENT = "NeuroMorphicToolkit-LauncherControl"
GITHUB_API_BASE = "https://api.github.com"
GITHUB_HTML_BASE = "https://github.com"
PRERELEASE_VERSION_PATTERN = re.compile(
    r"(?:^|[.\-])(alpha|beta|rc|dev|nightly|snapshot|canary|preview)(?:[.\-\d]|$)",
    re.IGNORECASE,
)
SUITE_API_ENV_ROOT = REPO_ROOT / ".nmtk" / "suite_api_env"
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

EXPECTED_PYNQ_OVERLAY_MANIFEST = {
    "overlay_id": "snn_overlay_v1",
    "overlay_version": "1.0.1",
    "target_part": "xc7z020clg400-1",
    "supported_neuron_models": ("LIF",),
    "supported_weight_bit_widths": (8,),
    "max_neurons": 256,
    "max_synapses": 15360,
    "max_populations": 2,
    "dma_ip_name": "axi_dma_0",
    "snn_ip_name": "snn_engine_0",
    "register_map": {
        "weight_base_offset": 0x1000,
        "dma_channel": "axi_dma_0",
    },
    "weight_layout": {
        "base_offset": 0x1000,
        "stride_bytes": 4,
        "max_entries": 15360,
    },
    "threshold_layout": {
        "base_offset": 0x100,
        "stride_bytes": 4,
        "max_entries": 2,
    },
}


def _read_json_file(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def _write_json_file(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


@dataclass(frozen=True)
class PynqLauncherRuntimeContract:
    runtime_port: int = 8002
    ssh_port: int = 22
    default_username: str = "xilinx"
    default_state: str = "unpaired"
    default_auth_mode: str = "password"
    legacy_install_root: str = "/opt/neurochip-pynq-agent"
    install_root_template: str = "/home/{username}/.local/share/neurochip-pynq-agent"
    agent_venv_dir_name: str = "venv"
    runtime_venv_dir_name: str = "pynq-venv"
    overlay_dir_name: str = "overlays"
    service_name: str = "neurochip-pynq-agent"
    agent_executable_name: str = "neurochip-pynq-agent"
    install_status_filename: str = "install-status.json"
    runtime_log_filename: str = "runtime.log"
    overlay_staging_subdir: str = "overlay_staging/pynq_z2"

    def install_root_for(self, username: str) -> str:
        normalized_username = username.strip() or self.default_username
        return self.install_root_template.replace("{username}", normalized_username)

    def legacy_venv_path(self) -> str:
        return f"{self.legacy_install_root}/{self.agent_venv_dir_name}"

    def legacy_overlay_dir(self) -> str:
        return f"{self.legacy_install_root}/{self.overlay_dir_name}"

    def agent_venv_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.agent_venv_dir_name}"

    def runtime_venv_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.runtime_venv_dir_name}"

    def overlay_dir_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.overlay_dir_name}"

    def install_status_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.install_status_filename}"

    def runtime_log_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.runtime_log_filename}"

    def overlay_staging_dir_for(self, module_root: Path) -> Path:
        return (module_root / self.overlay_staging_subdir).resolve()


@dataclass(frozen=True)
class AkidaLauncherRuntimeContract:
    runtime_port: int = 8002
    control_port: int = 8090
    ssh_port: int = 22
    default_state: str = "unknown"
    default_auth_mode: str = "password"
    install_root: str = "/opt/neurochip-akida-host"
    service_user: str = "neurochip"
    venv_dir_name: str = "venv"
    runtime_service_name: str = "neurochip"
    control_service_name: str = "neurochip-akida-control"
    token_relative_path: str = "credentials/api-token"
    install_status_relative_path: str = "install-status.json"

    def venv_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.venv_dir_name}"

    def token_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.token_relative_path}"

    def install_status_path_for(self, install_root: str) -> str:
        return f"{install_root.rstrip('/')}/{self.install_status_relative_path}"


@dataclass(frozen=True)
class NeurochipLauncherRuntimeContract:
    pynq: PynqLauncherRuntimeContract = field(default_factory=PynqLauncherRuntimeContract)
    akida: AkidaLauncherRuntimeContract = field(
        default_factory=AkidaLauncherRuntimeContract
    )


def _contract_string(value: Any, default: str) -> str:
    normalized = str(value or "").strip()
    return normalized or default


def _contract_int(value: Any, default: int) -> int:
    return value if isinstance(value, int) else default


def _load_neurochip_launcher_runtime_contract() -> NeurochipLauncherRuntimeContract:
    manifest = _read_json_file(MODULES_MANIFEST, [])
    launcher_runtime: dict[str, Any] = {}
    if isinstance(manifest, list):
        for raw in manifest:
            if (
                isinstance(raw, dict)
                and str(raw.get("id") or "").strip() == "Neurochip"
                and isinstance(raw.get("launcherRuntime"), dict)
            ):
                launcher_runtime = raw["launcherRuntime"]
                break

    pynq_raw = launcher_runtime.get("pynq", {})
    if not isinstance(pynq_raw, dict):
        pynq_raw = {}
    akida_raw = launcher_runtime.get("akida", {})
    if not isinstance(akida_raw, dict):
        akida_raw = {}

    default_pynq = PynqLauncherRuntimeContract()
    default_akida = AkidaLauncherRuntimeContract()
    return NeurochipLauncherRuntimeContract(
        pynq=PynqLauncherRuntimeContract(
            runtime_port=_contract_int(
                pynq_raw.get("runtimePort"),
                default_pynq.runtime_port,
            ),
            ssh_port=_contract_int(pynq_raw.get("sshPort"), default_pynq.ssh_port),
            default_username=_contract_string(
                pynq_raw.get("defaultUsername"),
                default_pynq.default_username,
            ),
            default_state=_contract_string(
                pynq_raw.get("defaultState"),
                default_pynq.default_state,
            ),
            default_auth_mode=_contract_string(
                pynq_raw.get("defaultAuthMode"),
                default_pynq.default_auth_mode,
            ),
            legacy_install_root=_contract_string(
                pynq_raw.get("legacyInstallRoot"),
                default_pynq.legacy_install_root,
            ),
            install_root_template=_contract_string(
                pynq_raw.get("installRootTemplate"),
                default_pynq.install_root_template,
            ),
            agent_venv_dir_name=_contract_string(
                pynq_raw.get("agentVenvDirName"),
                default_pynq.agent_venv_dir_name,
            ),
            runtime_venv_dir_name=_contract_string(
                pynq_raw.get("runtimeVenvDirName"),
                default_pynq.runtime_venv_dir_name,
            ),
            overlay_dir_name=_contract_string(
                pynq_raw.get("overlayDirName"),
                default_pynq.overlay_dir_name,
            ),
            service_name=_contract_string(
                pynq_raw.get("serviceName"),
                default_pynq.service_name,
            ),
            agent_executable_name=_contract_string(
                pynq_raw.get("agentExecutableName"),
                default_pynq.agent_executable_name,
            ),
            install_status_filename=_contract_string(
                pynq_raw.get("installStatusFilename"),
                default_pynq.install_status_filename,
            ),
            runtime_log_filename=_contract_string(
                pynq_raw.get("runtimeLogFilename"),
                default_pynq.runtime_log_filename,
            ),
            overlay_staging_subdir=_contract_string(
                pynq_raw.get("overlayStagingSubdir"),
                default_pynq.overlay_staging_subdir,
            ),
        ),
        akida=AkidaLauncherRuntimeContract(
            runtime_port=_contract_int(
                akida_raw.get("runtimePort"),
                default_akida.runtime_port,
            ),
            control_port=_contract_int(
                akida_raw.get("controlPort"),
                default_akida.control_port,
            ),
            ssh_port=_contract_int(
                akida_raw.get("sshPort"),
                default_akida.ssh_port,
            ),
            default_state=_contract_string(
                akida_raw.get("defaultState"),
                default_akida.default_state,
            ),
            default_auth_mode=_contract_string(
                akida_raw.get("defaultAuthMode"),
                default_akida.default_auth_mode,
            ),
            install_root=_contract_string(
                akida_raw.get("installRoot"),
                default_akida.install_root,
            ),
            service_user=_contract_string(
                akida_raw.get("serviceUser"),
                default_akida.service_user,
            ),
            venv_dir_name=_contract_string(
                akida_raw.get("venvDirName"),
                default_akida.venv_dir_name,
            ),
            runtime_service_name=_contract_string(
                akida_raw.get("runtimeServiceName"),
                default_akida.runtime_service_name,
            ),
            control_service_name=_contract_string(
                akida_raw.get("controlServiceName"),
                default_akida.control_service_name,
            ),
            token_relative_path=_contract_string(
                akida_raw.get("tokenRelativePath"),
                default_akida.token_relative_path,
            ),
            install_status_relative_path=_contract_string(
                akida_raw.get("installStatusRelativePath"),
                default_akida.install_status_relative_path,
            ),
        ),
    )


def _validate_pynq_overlay_manifest(payload: Any) -> None:
    if not isinstance(payload, dict):
        raise ValueError("manifest must be a JSON object")

    expected = EXPECTED_PYNQ_OVERLAY_MANIFEST
    for key in (
        "overlay_id",
        "overlay_version",
        "target_part",
        "max_neurons",
        "max_synapses",
        "max_populations",
        "dma_ip_name",
        "snn_ip_name",
    ):
        if payload.get(key) != expected[key]:
            raise ValueError(f"{key} must be {expected[key]!r}")

    supported_models = tuple(payload.get("supported_neuron_models") or ())
    if supported_models != expected["supported_neuron_models"]:
        raise ValueError(
            "supported_neuron_models must match the fixed overlay-v1 contract"
        )

    supported_weight_bit_widths = tuple(payload.get("supported_weight_bit_widths") or ())
    if supported_weight_bit_widths != expected["supported_weight_bit_widths"]:
        raise ValueError(
            "supported_weight_bit_widths must match the fixed overlay-v1 contract"
        )

    register_map = payload.get("register_map")
    if not isinstance(register_map, dict):
        raise ValueError("register_map must be an object")
    if register_map.get("dma_channel") != payload.get("dma_ip_name"):
        raise ValueError("register_map.dma_channel must match dma_ip_name")
    if int(register_map.get("weight_base_offset", -1)) != expected["register_map"][
        "weight_base_offset"
    ]:
        raise ValueError(
            "register_map.weight_base_offset must match the fixed overlay-v1 contract"
        )

    weight_layout = payload.get("weight_layout")
    if not isinstance(weight_layout, dict):
        raise ValueError("weight_layout must be an object")
    if int(weight_layout.get("base_offset", -1)) != int(
        register_map.get("weight_base_offset", -1)
    ):
        raise ValueError(
            "weight_layout.base_offset must match register_map.weight_base_offset"
        )
    if int(weight_layout.get("stride_bytes", -1)) != expected["weight_layout"][
        "stride_bytes"
    ]:
        raise ValueError(
            "weight_layout.stride_bytes must match overlay-v1 word-MMIO stride"
        )
    if int(weight_layout.get("max_entries", -1)) != expected["weight_layout"][
        "max_entries"
    ]:
        raise ValueError("weight_layout.max_entries must match max_synapses")
    if (
        int(weight_layout["base_offset"])
        + int(weight_layout["stride_bytes"]) * int(weight_layout["max_entries"])
        > 0x10000
    ):
        raise ValueError("weight_layout exceeds the SNN IP MMIO window")

    threshold_layout = payload.get("threshold_layout")
    if not isinstance(threshold_layout, dict):
        raise ValueError("threshold_layout must be an object")
    for key, expected_value in expected["threshold_layout"].items():
        if int(threshold_layout.get(key, -1)) != expected_value:
            raise ValueError(f"threshold_layout.{key} must be {expected_value}")


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


@dataclass(frozen=True)
class ParsedVersion:
    core: tuple[int, ...]
    prerelease: tuple[str, ...] = field(default_factory=tuple)


def _normalize_version_string(raw: str) -> str:
    normalized = raw.strip()
    if normalized.startswith("refs/tags/"):
        normalized = normalized.removeprefix("refs/tags/")
    if normalized.lower().startswith("v") and len(normalized) > 1:
        next_character = normalized[1]
        if next_character.isdigit():
            normalized = normalized[1:]
    return normalized


def _parse_version(raw: str) -> ParsedVersion | None:
    normalized = _normalize_version_string(raw).split("+", 1)[0]
    if not normalized:
        return None
    core_text, separator, prerelease_text = normalized.partition("-")
    core_parts = core_text.split(".")
    if not core_parts or any(not part.isdigit() for part in core_parts):
        return None
    prerelease_parts = (
        tuple(part for part in prerelease_text.split(".") if part)
        if separator
        else ()
    )
    return ParsedVersion(
        core=tuple(int(part) for part in core_parts),
        prerelease=prerelease_parts,
    )


def _compare_prerelease_identifiers(
    left: tuple[str, ...],
    right: tuple[str, ...],
) -> int:
    for left_identifier, right_identifier in zip(left, right):
        left_is_number = left_identifier.isdigit()
        right_is_number = right_identifier.isdigit()
        if left_is_number and right_is_number:
            left_number = int(left_identifier)
            right_number = int(right_identifier)
            if left_number != right_number:
                return 1 if left_number > right_number else -1
            continue
        if left_is_number != right_is_number:
            return -1 if left_is_number else 1
        if left_identifier != right_identifier:
            return 1 if left_identifier > right_identifier else -1
    if len(left) == len(right):
        return 0
    return 1 if len(left) > len(right) else -1


def _compare_versions(left: str, right: str) -> int:
    left_parsed = _parse_version(left)
    right_parsed = _parse_version(right)
    if left_parsed is None or right_parsed is None:
        normalized_left = _normalize_version_string(left)
        normalized_right = _normalize_version_string(right)
        if normalized_left == normalized_right:
            return 0
        return 1 if normalized_left > normalized_right else -1

    max_length = max(len(left_parsed.core), len(right_parsed.core))
    for index in range(max_length):
        left_value = left_parsed.core[index] if index < len(left_parsed.core) else 0
        right_value = (
            right_parsed.core[index] if index < len(right_parsed.core) else 0
        )
        if left_value != right_value:
            return 1 if left_value > right_value else -1

    if not left_parsed.prerelease and not right_parsed.prerelease:
        return 0
    if not left_parsed.prerelease:
        return 1
    if not right_parsed.prerelease:
        return -1
    return _compare_prerelease_identifiers(
        left_parsed.prerelease,
        right_parsed.prerelease,
    )


def _is_newer_version(current: str, candidate: str) -> bool:
    return _compare_versions(candidate, current) > 0


def _coerce_remote_update_version(current: str, candidate: str | None) -> str:
    if candidate is not None and _is_newer_version(current, candidate):
        return _normalize_version_string(candidate)
    return current


def _is_prerelease_version(version: str) -> bool:
    parsed = _parse_version(version)
    if parsed is not None and parsed.prerelease:
        return True
    return PRERELEASE_VERSION_PATTERN.search(_normalize_version_string(version)) is not None


def _normalize_github_repo_api_url(remote_url: str) -> str | None:
    parsed = urlparse(remote_url)
    if parsed.scheme not in {"http", "https"}:
        return None
    path = parsed.path.rstrip("/")
    if parsed.netloc == "api.github.com" and path.startswith("/repos/"):
        return f"{GITHUB_API_BASE}{path}"
    if parsed.netloc == "github.com":
        parts = [part for part in path.split("/") if part]
        if len(parts) < 2:
            return None
        owner, repo = parts[0], parts[1].removesuffix(".git")
        return f"{GITHUB_API_BASE}/repos/{owner}/{repo}"
    return None


def _github_repo_html_url(remote_url: str) -> str | None:
    api_url = _normalize_github_repo_api_url(remote_url)
    if api_url is None:
        return None
    parsed = urlparse(api_url)
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 3 or parts[0] != "repos":
        return None
    return f"{GITHUB_HTML_BASE}/{parts[1]}/{parts[2]}"


def _github_api_headers() -> dict[str, str]:
    headers = {
        "Accept": GITHUB_API_ACCEPT,
        "User-Agent": GITHUB_USER_AGENT,
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _read_json_url(url: str) -> Any | None:
    request = urllib.request.Request(url, headers=_github_api_headers())
    try:
        with urllib.request.urlopen(
            request,
            timeout=GITHUB_API_TIMEOUT_SECONDS,
        ) as response:
            return json.loads(response.read().decode("utf-8"))
    except (json.JSONDecodeError, TimeoutError, urllib.error.HTTPError, urllib.error.URLError):
        return None


def _resolve_latest_stable_tag_version(remote_url: str) -> str | None:
    repo_api_url = _normalize_github_repo_api_url(remote_url)
    if repo_api_url is None:
        return None
    payload = _read_json_url(f"{repo_api_url}/tags?per_page={GITHUB_API_PAGE_SIZE}")
    if not isinstance(payload, list):
        return None

    best_version: str | None = None
    for item in payload:
        if not isinstance(item, dict):
            continue
        raw_name = item.get("name")
        if not isinstance(raw_name, str):
            continue
        normalized = _normalize_version_string(raw_name)
        if _parse_version(normalized) is None or _is_prerelease_version(normalized):
            continue
        if best_version is None or _is_newer_version(best_version, normalized):
            best_version = normalized
    return best_version


def _resolve_remote_module_version(module: dict[str, Any]) -> str | None:
    remote_url = module.get("remoteUrl")
    if not isinstance(remote_url, str) or not remote_url.strip():
        return None
    return _resolve_latest_stable_tag_version(remote_url)


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
    if (
        not remote_install_root
        or remote_install_root == contract.legacy_install_root
    ):
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


def _build_password_askpass_env(
    *,
    password: str,
    env_key: str,
    prefix: str,
) -> tuple[dict[str, str], Callable[[], None]]:
    askpass_handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=prefix,
        delete=False,
    )
    askpass_handle.write("#!/bin/sh\n")
    askpass_handle.write(f"printf '%s\\n' \"${env_key}\"\n")
    askpass_handle.close()
    os.chmod(askpass_handle.name, 0o700)

    env = os.environ.copy()
    env[env_key] = password
    env["SSH_ASKPASS"] = askpass_handle.name
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env.setdefault("DISPLAY", "nmtk-launcher-control:0")

    def _cleanup_askpass() -> None:
        try:
            os.unlink(askpass_handle.name)
        except FileNotFoundError:
            return None

    return env, _cleanup_askpass


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


class RuntimeRequestError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        kind: str,
        url: str,
        status_code: int | None = None,
        response_body: str = "",
    ) -> None:
        super().__init__(message)
        self.kind = kind
        self.url = url
        self.status_code = status_code
        self.response_body = response_body


def _runtime_request_error_kind(exc: Exception) -> str:
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return "timeout"
    if isinstance(exc, urllib.error.URLError) and isinstance(
        exc.reason, (TimeoutError, socket.timeout)
    ):
        return "timeout"
    return "unreachable"


def _describe_akida_preflight(verification: dict[str, Any]) -> str:
    sdk_status = str(verification.get("sdk_status") or "").strip().lower()
    sdk_available = bool(verification.get("sdk_available"))
    sdk_issue_detail = str(verification.get("sdk_issue_detail") or "").strip()
    raw_sdk_issues = verification.get("sdk_issues", [])
    if not isinstance(raw_sdk_issues, list):
        raw_sdk_issues = []
    sdk_issues = [
        str(issue).strip()
        for issue in raw_sdk_issues
        if str(issue).strip()
    ]
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


def _module_root(module: dict[str, Any]) -> Path:
    install_path = module.get("installPath") or module.get("directory") or ""
    return (REPO_ROOT / install_path).resolve()


def _neurochip_module_root() -> Path:
    manifest = _read_json_file(MODULES_MANIFEST, [])
    if isinstance(manifest, list):
        for raw in manifest:
            if (
                isinstance(raw, dict)
                and str(raw.get("id") or "").strip() == "Neurochip"
            ):
                return _module_root(raw)
    return (REPO_ROOT / "Neurochip").resolve()


def _module_install_dir(module: dict[str, Any]) -> Path:
    source_path = module.get("sourcePath") or "."
    return (_module_root(module) / source_path).resolve()


def _module_run_dir(module: dict[str, Any]) -> Path:
    run_path = module.get("runPath") or module.get("sourcePath") or "."
    return (_module_root(module) / run_path).resolve()


def _module_venv_python(module: dict[str, Any]) -> Path:
    """Return the python path, checking .venv (poetry in-project) before venv."""
    install_dir = _module_install_dir(module)
    if os.name == "nt":
        dotenv = install_dir / ".venv" / "Scripts" / "python.exe"
        return (
            dotenv
            if dotenv.exists()
            else install_dir / "venv" / "Scripts" / "python.exe"
        )
    dotenv = install_dir / ".venv" / "bin" / "python"
    return dotenv if dotenv.exists() else install_dir / "venv" / "bin" / "python"


def _module_venv_pip(module: dict[str, Any]) -> Path:
    install_dir = _module_install_dir(module)
    if os.name == "nt":
        dotenv = install_dir / ".venv" / "Scripts" / "pip.exe"
        return (
            dotenv if dotenv.exists() else install_dir / "venv" / "Scripts" / "pip.exe"
        )
    dotenv = install_dir / ".venv" / "bin" / "pip"
    return dotenv if dotenv.exists() else install_dir / "venv" / "bin" / "pip"


def _module_pyproject_path(module: dict[str, Any]) -> Path | None:
    install_dir = _module_install_dir(module)
    module_root = _module_root(module)
    for candidate in (
        install_dir / "pyproject.toml",
        module_root / "pyproject.toml",
    ):
        if candidate.exists():
            return candidate
    return None


def _module_uses_poetry(module: dict[str, Any]) -> bool:
    pyproject_path = _module_pyproject_path(module)
    if pyproject_path is None:
        return False

    try:
        pyproject = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return False

    build_backend = str(
        pyproject.get("build-system", {}).get("build-backend", "")
    ).strip()
    tool_table = pyproject.get("tool", {})
    return build_backend == "poetry.core.masonry.api" or "poetry" in tool_table


def _poetry_fallback_env_root(module: dict[str, Any]) -> Path:
    module_id = str(module.get("id") or "").strip()
    return REPO_ROOT / ".poetry-envs" / module_id


def _poetry_command() -> str | None:
    found = shutil.which("poetry")
    if found:
        return found
    # Poetry is commonly installed outside the system PATH.
    # Probe well-known locations so the control service works even when
    # launched by Flutter (which inherits a minimal environment).
    candidates = [
        Path.home() / ".local" / "bin" / "poetry",
        Path.home() / ".poetry" / "bin" / "poetry",
        # pipx default bin dir
        Path.home() / ".local" / "pipx" / "venvs" / "poetry" / "bin" / "poetry",
    ]
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _poetry_env_python(module: dict[str, Any]) -> Path | None:
    if not _module_uses_poetry(module):
        return None

    install_dir = _module_install_dir(module)

    # Check in-project .venv first (set by poetry config virtualenvs.in-project true).
    # This is the most reliable path and requires no subprocess call.
    if os.name == "nt":
        inproject_python = install_dir / ".venv" / "Scripts" / "python.exe"
    else:
        inproject_python = install_dir / ".venv" / "bin" / "python"
    if inproject_python.exists():
        return inproject_python

    fallback_env_root = _poetry_fallback_env_root(module)
    if os.name == "nt":
        fallback_python = fallback_env_root / "Scripts" / "python.exe"
    else:
        fallback_python = fallback_env_root / "bin" / "python"
    if fallback_python.exists():
        return fallback_python

    poetry = _poetry_command()
    if poetry is None:
        return None

    result = subprocess.run(
        [poetry, "env", "info", "--path"],
        cwd=install_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    env_path = Path((result.stdout or "").strip())
    if result.returncode != 0 or not env_path:
        return None

    if os.name == "nt":
        python_path = env_path / "Scripts" / "python.exe"
    else:
        python_path = env_path / "bin" / "python"
    return python_path if python_path.exists() else None


def _module_python_path(module: dict[str, Any]) -> Path:
    return _poetry_env_python(module) or _module_venv_python(module)


def _missing_python_message(module: dict[str, Any], python_path: Path) -> str:
    if _module_uses_poetry(module):
        return f"Module python missing at {python_path}"
    return f"Virtualenv python missing at {python_path}"


def _module_environment_exists(module: dict[str, Any]) -> bool:
    return _module_python_path(module).exists()


def _effective_port(module: dict[str, Any]) -> int | None:
    custom = module.get("customPort")
    if isinstance(custom, int):
        return custom
    port = module.get("port")
    return port if isinstance(port, int) else None


def _current_platform_key() -> str:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform.startswith(("win32", "cygwin")):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return sys.platform


def _normalize_akida_runtime_config(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    return {
        "supportedPlatforms": [
            str(value).strip()
            for value in raw.get("supportedPlatforms", [])
            if str(value).strip()
        ],
        "pythonRange": str(raw.get("pythonRange") or ">=3.10,<3.13").strip(),
        "requiredPackages": [
            str(value).strip()
            for value in raw.get("requiredPackages", [])
            if str(value).strip()
        ],
        "docsUrl": str(raw.get("docsUrl") or "").strip(),
        "localModeFallback": str(raw.get("localModeFallback") or "simulator_only").strip(),
    }


def _normalize_akida_runtime_state(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    status = str(raw.get("status") or "").strip()
    if not status:
        return None
    return {
        "status": status,
        "message": str(raw.get("message") or "").strip() or None,
        "preparedAt": str(raw.get("preparedAt") or "").strip() or None,
    }


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
        raw.get("runtimeMode")
        or (capability_snapshot or {}).get("recommendedRuntime")
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
        "capabilitySnapshot": capability_snapshot,
        "isDefault": bool(raw.get("isDefault")),
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


def _parse_version_tuple(version: str) -> tuple[int, int, int] | None:
    parts = [part.strip() for part in version.split(".") if part.strip()]
    if len(parts) < 2:
        return None
    try:
        parsed = [int(part) for part in parts[:3]]
    except ValueError:
        return None
    while len(parsed) < 3:
        parsed.append(0)
    return parsed[0], parsed[1], parsed[2]


def _version_matches_range(version: str, version_range: str) -> bool:
    parsed_version = _parse_version_tuple(version)
    if parsed_version is None:
        return False
    for raw_part in version_range.split(","):
        part = raw_part.strip()
        if not part:
            continue
        if part.startswith(">="):
            minimum = _parse_version_tuple(part[2:])
            if minimum is None or parsed_version < minimum:
                return False
            continue
        if part.startswith("<"):
            maximum = _parse_version_tuple(part[1:])
            if maximum is None or parsed_version >= maximum:
                return False
    return True


def _uvicorn_host() -> str:
    host = os.environ.get("NMTK_UVICORN_HOST", "0.0.0.0").strip()
    return host or "0.0.0.0"


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


def _module_install_strategy(module: dict[str, Any]) -> str:
    strategy = str(module.get("installStrategy", "pip")).strip().lower()
    return strategy or "pip"


def _module_start_strategy(module: dict[str, Any]) -> str:
    if not module.get("uvicornTarget"):
        return "none"
    strategy = str(module.get("startStrategy", "uvicorn")).strip().lower()
    return strategy or "uvicorn"


def _normalized_import_list(raw: Any) -> list[str]:
    if not isinstance(raw, list):
        return []
    imports: list[str] = []
    for item in raw:
        if isinstance(item, str):
            value = item.strip()
            if value:
                imports.append(value)
    return imports


def _module_required_imports(module: dict[str, Any]) -> list[str]:
    imports = _normalized_import_list(module.get("requiredImports"))
    uvicorn_target = str(module.get("uvicornTarget", "")).strip()
    app_module = uvicorn_target.split(":", 1)[0] if uvicorn_target else ""
    if app_module and app_module not in imports:
        imports.append(app_module)
    return imports


def _module_optional_imports(module: dict[str, Any]) -> list[str]:
    return _normalized_import_list(module.get("optionalImports"))


def _module_install_extras(module: dict[str, Any]) -> list[str]:
    return _normalized_import_list(module.get("installExtras"))


def _candidate_environment_files(module: dict[str, Any]) -> list[Path]:
    module_root = _module_root(module)
    install_dir = _module_install_dir(module)
    candidates = [
        install_dir / "pyproject.toml",
        module_root / "pyproject.toml",
        install_dir / "poetry.lock",
        module_root / "poetry.lock",
        install_dir / "requirements.txt",
        module_root / "requirements.txt",
        module_root / "backend" / "requirements.txt",
        install_dir / "requirements-dev.txt",
        module_root / "requirements-dev.txt",
    ]
    seen: set[Path] = set()
    existing: list[Path] = []
    for candidate in candidates:
        if candidate.exists() and candidate not in seen:
            seen.add(candidate)
            existing.append(candidate)
    return existing


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _status_for_health_response(
    status_code: int,
    preflight_status: str,
) -> int:
    if (
        status_code == HTTPStatus.SERVICE_UNAVAILABLE
        or preflight_status == PREFLIGHT_DEGRADED
    ):
        return STATUS_INDEX["degraded"]
    return STATUS_INDEX["running"]


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


def _message_from_probe_outcome(
    outcome: dict[str, Any],
    *,
    optional: bool,
) -> str:
    import_name = str(outcome.get("import", "unknown"))
    missing_name = str(outcome.get("missing") or import_name)
    if outcome.get("kind") == "missing":
        if optional:
            return (
                f"Optional capability unavailable: {missing_name} "
                f"(needed by {import_name})"
            )
        if missing_name == import_name:
            return f"Missing required import: {missing_name}"
        return f"Missing required dependency: {missing_name} (needed by {import_name})"

    error = str(outcome.get("error") or "Unknown import failure")
    if optional:
        return f"Optional capability check failed for {import_name}: {error}"
    return f"Required import check failed for {import_name}: {error}"


def _doctor_prefix(status: str) -> str:
    return (
        "preflight failed"
        if status == PREFLIGHT_FAILED
        else "degraded optional capability"
        if status == PREFLIGHT_DEGRADED
        else "OK"
    )


def _flutter_sdk_check() -> dict[str, Any]:
    flutter = shutil.which("flutter")
    if flutter is None:
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": "Flutter executable not found on PATH",
            "capabilityWarnings": [],
        }

    flutter_path = Path(flutter).resolve()
    cache_dir = flutter_path.parent / "cache"
    engine_stamp = cache_dir / "engine.stamp"

    if not cache_dir.exists():
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache directory missing: {cache_dir}",
            "capabilityWarnings": [],
        }

    if not os.access(cache_dir, os.W_OK):
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache is not writable: {cache_dir}",
            "capabilityWarnings": [],
        }

    if engine_stamp.exists() and not os.access(engine_stamp, os.W_OK):
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache stamp is not writable: {engine_stamp}",
            "capabilityWarnings": [],
        }

    return {
        "id": "flutter-sdk",
        "name": "Flutter SDK",
        "preflightStatus": PREFLIGHT_OK,
        "preflightMessage": f"Flutter SDK cache ready: {cache_dir}",
        "capabilityWarnings": [],
    }


def _suite_api_bind_host() -> str:
    return str(os.environ.get("NMTK_UVICORN_HOST") or "127.0.0.1").strip() or "127.0.0.1"


def _suite_api_base_url() -> str:
    return f"http://127.0.0.1:{DEFAULT_SUITE_API_PORT}"


def _suite_api_health_url() -> str:
    return f"{_suite_api_base_url()}/api/suite/health"


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


def _suite_api_env_dir() -> Path:
    explicit = str(os.environ.get("NMTK_SUITE_API_ENV_DIR") or "").strip()
    if explicit:
        return Path(explicit).expanduser()
    if _running_in_bundled_mode():
        return _default_user_data_dir() / "suite_api_env"
    return SUITE_API_ENV_ROOT


def _suite_api_env_python(env_dir: Path) -> Path:
    if os.name == "nt":
        return env_dir / "venv" / "Scripts" / "python.exe"
    return env_dir / "venv" / "bin" / "python"


def _suite_api_env_stamp(env_dir: Path) -> Path:
    return env_dir / "install-fingerprint.json"


def _suite_api_dev_install_paths() -> tuple[Path, ...]:
    return (
        REPO_ROOT / "suite_api",
        REPO_ROOT / "neurocnl",
        REPO_ROOT / "Neuro-Dream-Hand",
        REPO_ROOT / "Neurohub",
        REPO_ROOT / "Neurochip",
        REPO_ROOT / "Neurobench" / "neurobench",
        REPO_ROOT / "Neurosense",
    )


def _suite_api_env_fingerprint_files() -> tuple[Path, ...]:
    return (
        REPO_ROOT / "suite_api" / "pyproject.toml",
        REPO_ROOT / "neurocnl" / "pyproject.toml",
        REPO_ROOT / "Neuro-Dream-Hand" / "pyproject.toml",
        REPO_ROOT / "Neurohub" / "pyproject.toml",
        REPO_ROOT / "Neurochip" / "pyproject.toml",
        REPO_ROOT / "Neurobench" / "neurobench" / "pyproject.toml",
        REPO_ROOT / "Neurosense" / "pyproject.toml",
    )


def _suite_api_env_fingerprint() -> str:
    payload = {
        str(path.relative_to(REPO_ROOT)): _hash_file(path)
        for path in _suite_api_env_fingerprint_files()
        if path.exists()
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True).encode("utf-8")
    ).hexdigest()


def _suite_api_pythonpath_entries() -> list[str]:
    entries = [
        str(REPO_ROOT),
        str(REPO_ROOT / "Neurohub"),
        str(REPO_ROOT / "Neurosense"),
        str(REPO_ROOT / "Neurochip"),
        str(REPO_ROOT / "Neurobench" / "neurobench"),
    ]
    return [entry for entry in entries if Path(entry).exists()]


def _suite_api_pythonpath() -> str:
    entries = _suite_api_pythonpath_entries()
    existing = str(os.environ.get("PYTHONPATH") or "").strip()
    if existing:
        entries.append(existing)
    return os.pathsep.join(entries)


def _suite_api_env_is_bootstrapped(venv_python: Path) -> bool:
    if not venv_python.exists():
        return False

    result = subprocess.run(
        [
            str(venv_python),
            "-c",
            "import fastapi, uvicorn, suite_api.main",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "PYTHONPATH": _suite_api_pythonpath()},
    )
    return result.returncode == 0


def _suite_api_health_probe() -> tuple[bool, str | None]:
    try:
        with urllib.request.urlopen(_suite_api_health_url(), timeout=2.0) as response:
            body = response.read().decode("utf-8", errors="replace")
            if int(response.status) == HTTPStatus.OK:
                return True, body
            return False, body or f"Unexpected status {response.status}"
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return False, body or f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
        return False, str(exc)


def _global_preflight_checks() -> list[dict[str, Any]]:
    return [_flutter_sdk_check()]


def _render_doctor_report(report: dict[str, Any]) -> str:
    summary = (
        "preflight failed"
        if report["fatalCount"] > 0
        else "degraded optional capability"
        if report["degradedCount"] > 0
        else "ok"
    )
    lines = [
        "NMTK launcher doctor",
        f"status={summary}",
        f"fatal={report['fatalCount']} degraded={report['degradedCount']} ok={report['okCount']}",
    ]
    for check in report.get("globalChecks", []):
        lines.append(
            f"{_doctor_prefix(str(check['preflightStatus']))} {check['id']}: "
            f"{check['preflightMessage'] or 'ready'}"
        )
        for warning in check.get("capabilityWarnings", []):
            lines.append(f"  - {warning}")
    for module in report["modules"]:
        lines.append(
            f"{_doctor_prefix(str(module['preflightStatus']))} {module['id']}: "
            f"{module['preflightMessage'] or 'ready'}"
        )
        for warning in module.get("capabilityWarnings", []):
            lines.append(f"  - {warning}")
    return "\n".join(lines)


def _dedupe_messages(messages: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for message in messages:
        if message not in seen:
            seen.add(message)
            deduped.append(message)
    return deduped


def _is_benign_ssh_warning_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    return any(stripped.startswith(prefix) for prefix in BENIGN_SSH_WARNING_PREFIXES)


@dataclass
class ManagedProcess:
    """Represents a launched module process and its recent logs."""

    process: subprocess.Popen[str]
    logs: collections.deque[str] = field(
        default_factory=lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
    )


@dataclass
class PreflightResult:
    """Outcome of a non-network module readiness probe."""

    status: str
    message: str | None = None
    capability_warnings: list[str] = field(default_factory=list)
    environment_fingerprint: str | None = None

    def state_fields(self) -> dict[str, Any]:
        return {
            "preflightStatus": self.status,
            "preflightMessage": self.message,
            "capabilityWarnings": list(self.capability_warnings),
            "environmentFingerprint": self.environment_fingerprint,
        }


class LauncherControlState:
    """In-memory state and lifecycle orchestration for module control."""

    def __init__(
        self,
        remote_version_resolver: Callable[[dict[str, Any]], str | None] | None = None,
        *,
        manage_suite_api: bool = False,
    ) -> None:
        self._lock = threading.RLock()
        self._terminal_lock = threading.Lock()
        self._remote_version_resolver = (
            remote_version_resolver or _resolve_remote_module_version
        )
        self._manage_suite_api = manage_suite_api
        self._suite_api_status = (
            SUITE_API_STATUS_STARTING
            if manage_suite_api
            else SUITE_API_STATUS_DISABLED
        )
        self._suite_api_message: str | None = None
        self._suite_api_process: subprocess.Popen[str] | None = None
        self._suite_api_logs: collections.deque[str] = collections.deque(
            maxlen=LOG_LINE_LIMIT
        )
        self._modules = self._load_modules()
        self._processes: dict[str, ManagedProcess] = {}
        self._logs: dict[str, collections.deque[str]] = collections.defaultdict(
            lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
        )
        self._tasks: dict[str, threading.Thread] = {}
        self._settings = self._load_settings()
        self._workspace = self._load_workspace()
        self._deployment = DeploymentService(
            store=DeploymentStore(
                DEPLOYMENT_STATE_FILE,
                FileBackedSecretStore(DEPLOYMENT_SECRET_FILE),
            ),
            repo_root=REPO_ROOT,
        )
        self._shutdown = threading.Event()
        self._health_thread = threading.Thread(
            target=self._health_poll_loop,
            name="launcher-control-health",
            daemon=True,
        )
        self._health_thread.start()
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
        if self._suite_api_process is not None and self._suite_api_process.poll() is None:
            self._suite_api_process.terminate()
            try:
                self._suite_api_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._suite_api_process.kill()
                self._suite_api_process.wait(timeout=5)

    def _set_suite_api_state(self, status: str, message: str | None = None) -> None:
        with self._lock:
            self._suite_api_status = status
            self._suite_api_message = message

    def _suite_api_ready_result(self) -> PreflightResult:
        if not self._manage_suite_api:
            return PreflightResult(status=PREFLIGHT_OK)
        if self._suite_api_status == SUITE_API_STATUS_READY:
            return PreflightResult(status=PREFLIGHT_OK, message="Managed by suite_api")
        if self._suite_api_status == SUITE_API_STATUS_STARTING:
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=self._suite_api_message
                or "suite_api is still starting; wait for the control plane to finish booting",
            )
        return PreflightResult(
            status=PREFLIGHT_FAILED,
            message=self._suite_api_message or "suite_api is unavailable",
        )

    def _suite_api_python(self) -> str:
        if _running_in_bundled_mode():
            return sys.executable

        env_dir = _suite_api_env_dir()
        venv_dir = env_dir / "venv"
        venv_python = _suite_api_env_python(env_dir)
        fingerprint = _suite_api_env_fingerprint()
        stamp_path = _suite_api_env_stamp(env_dir)
        saved_fingerprint = ""
        if stamp_path.exists():
            try:
                saved_fingerprint = str(
                    json.loads(stamp_path.read_text(encoding="utf-8")).get("fingerprint")
                    or ""
                )
            except (json.JSONDecodeError, OSError):
                saved_fingerprint = ""

        env_dir.mkdir(parents=True, exist_ok=True)
        venv_created = False
        if not venv_python.exists():
            result = subprocess.run(
                [sys.executable, "-m", "venv", str(venv_dir)],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "Failed to create suite_api virtual environment"
                )
            venv_created = True

        needs_install = venv_created or saved_fingerprint != fingerprint
        if not needs_install and not _suite_api_env_is_bootstrapped(venv_python):
            needs_install = True

        if needs_install:
            for install_path in _suite_api_dev_install_paths():
                if not install_path.exists():
                    raise RuntimeError(
                        f"suite_api dependency checkout not found: {install_path}"
                    )
                result = subprocess.run(
                    [str(venv_python), "-m", "pip", "install", "-e", str(install_path)],
                    cwd=REPO_ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    raise RuntimeError(
                        result.stderr.strip()
                        or result.stdout.strip()
                        or f"Failed to install {install_path}"
                    )
            stamp_path.write_text(
                json.dumps({"fingerprint": fingerprint}, indent=2, sort_keys=True),
                encoding="utf-8",
            )

        return str(venv_python)

    def _suite_api_environment(self) -> dict[str, str]:
        environment = dict(os.environ)
        environment["PYTHONPATH"] = _suite_api_pythonpath()
        return environment

    def _stream_suite_api_logs(self, process: subprocess.Popen[str]) -> None:
        if process.stdout is None:
            return

        def _pump() -> None:
            assert process.stdout is not None
            for line in process.stdout:
                message = line.rstrip()
                if not message:
                    continue
                self._suite_api_logs.append(message)
                with self._terminal_lock:
                    print(f"[suite_api] {message}")

        threading.Thread(
            target=_pump,
            name="suite-api-stdout",
            daemon=True,
        ).start()

    def _ensure_suite_api_ready(self) -> None:
        if not self._manage_suite_api or self._shutdown.is_set():
            return

        ok, _message = _suite_api_health_probe()
        if ok:
            self._set_suite_api_state(SUITE_API_STATUS_READY, "Managed by suite_api")
            return

        self._set_suite_api_state(
            SUITE_API_STATUS_STARTING,
            "Starting suite_api and provisioning its runtime environment",
        )
        try:
            python_path = self._suite_api_python()
        except RuntimeError as exc:
            self._set_suite_api_state(SUITE_API_STATUS_PREFLIGHT_FAILED, str(exc))
            return

        process = subprocess.Popen(
            [
                python_path,
                "-m",
                "uvicorn",
                "suite_api.main:app",
                "--host",
                _suite_api_bind_host(),
                "--port",
                str(DEFAULT_SUITE_API_PORT),
                "--log-level",
                str(self._settings["logLevel"]),
            ],
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            env=self._suite_api_environment(),
        )
        self._suite_api_process = process
        self._stream_suite_api_logs(process)

        deadline = time.monotonic() + SUITE_API_STARTUP_TIMEOUT_SECONDS
        while time.monotonic() < deadline and not self._shutdown.is_set():
            ok, message = _suite_api_health_probe()
            if ok:
                self._set_suite_api_state(SUITE_API_STATUS_READY, "Managed by suite_api")
                return
            if process.poll() is not None:
                startup_logs = "\n".join(self._suite_api_logs).strip()
                self._set_suite_api_state(
                    SUITE_API_STATUS_PREFLIGHT_FAILED,
                    startup_logs or message or f"suite_api exited with code {process.returncode}",
                )
                return
            time.sleep(0.5)

        self._set_suite_api_state(
            SUITE_API_STATUS_PREFLIGHT_FAILED,
            f"Timed out waiting for suite_api health at {_suite_api_health_url()}",
        )

    def _load_modules(self) -> dict[str, dict[str, Any]]:
        manifest = _read_json_file(MODULES_MANIFEST, [])
        saved_states = _read_json_file(STATE_FILE, {})
        module_map: dict[str, dict[str, Any]] = {}
        for raw in manifest:
            if not isinstance(raw, dict) or "id" not in raw:
                continue
            module_id = str(raw["id"])
            saved = saved_states.get(module_id, {})
            module = dict(raw)
            module["directory"] = str(_module_root(module))
            module["version"] = str(saved.get("version", module.get("version", "0.0.0")))
            module["versionPinned"] = bool(saved.get("versionPinned", False))
            saved_remote_version = str(
                saved.get("remoteVersion", module.get("remoteVersion", module["version"]))
            )
            module["remoteVersion"] = (
                module["version"]
                if module["versionPinned"]
                else _coerce_remote_update_version(
                    module["version"],
                    saved_remote_version,
                )
            )
            module["isEnabled"] = bool(saved.get("isEnabled", True))
            module["customPort"] = saved.get("customPort")
            module["startOnLaunch"] = bool(saved.get("startOnLaunch", False))
            status_index = saved.get("status", STATUS_INDEX["notInstalled"])
            if status_index in (
                STATUS_INDEX["running"],
                STATUS_INDEX["starting"],
                STATUS_INDEX["stopping"],
                STATUS_INDEX["degraded"],
                STATUS_INDEX["error"],
                STATUS_INDEX["updating"],
            ):
                status_index = STATUS_INDEX["installed"]
            if (
                status_index != STATUS_INDEX["notInstalled"]
                and not _module_environment_exists(module)
                and not saved.get("environmentFingerprint")
            ):
                status_index = STATUS_INDEX["notInstalled"]
                module["installProgress"] = 0.0
            module["status"] = status_index
            module["installProgress"] = float(
                module.get("installProgress", saved.get("installProgress", 0.0))
            )
            module["healthStatus"] = saved.get("healthStatus")
            module["requiredImports"] = _module_required_imports(module)
            module["optionalImports"] = _module_optional_imports(module)
            module["installExtras"] = _module_install_extras(module)
            module["installStrategy"] = _module_install_strategy(module)
            module["startStrategy"] = _module_start_strategy(module)
            module["akidaRuntime"] = _normalize_akida_runtime_config(
                module.get("akidaRuntime")
            )
            module["akidaRuntimeState"] = _normalize_akida_runtime_state(
                saved.get("akidaRuntimeState")
            )
            module["preflightStatus"] = str(saved.get("preflightStatus", PREFLIGHT_OK))
            module["preflightMessage"] = saved.get("preflightMessage")
            module["capabilityWarnings"] = _normalized_import_list(
                saved.get("capabilityWarnings", module.get("capabilityWarnings", []))
            )
            module["environmentFingerprint"] = saved.get("environmentFingerprint")
            module_map[module_id] = module
        return module_map

    def refresh_remote_versions(self) -> None:
        with self._lock:
            snapshots = [dict(module) for module in self._modules.values()]

        refreshed_versions: dict[str, str] = {}
        for module in snapshots:
            module_id = str(module["id"])
            current_version = str(module.get("version", "0.0.0"))
            if bool(module.get("versionPinned", False)):
                refreshed_versions[module_id] = current_version
                continue
            existing_remote_version = str(
                module.get("remoteVersion", current_version)
            )
            resolved_version = self._remote_version_resolver(module)
            refreshed_versions[module_id] = _coerce_remote_update_version(
                current_version,
                resolved_version or existing_remote_version,
            )

        with self._lock:
            changed = False
            for module_id, remote_version in refreshed_versions.items():
                module = self._modules.get(module_id)
                if module is None or module.get("remoteVersion") == remote_version:
                    continue
                module["remoteVersion"] = remote_version
                changed = True
            if changed:
                self._persist_states()

    def _load_settings(self) -> dict[str, Any]:
        defaults = {
            "logLevel": DEFAULT_CONTROL_LOG_LEVEL,
            "mujocoAvailable": _mujoco_available(),
            "pythonAvailable": True,
            "akidaHosts": [],
            "pynqBoards": [],
            "selectedAkidaHostId": None,
        }
        stored = _read_json_file(SETTINGS_FILE, {})
        if not isinstance(stored, dict):
            return defaults
        akida_hosts = [
            _normalize_akida_host(host)
            for host in stored.get("akidaHosts", [])
            if isinstance(host, dict)
        ]
        selected_akida_host_id = str(stored.get("selectedAkidaHostId") or "").strip()
        if akida_hosts and not any(
            host["id"] == selected_akida_host_id for host in akida_hosts
        ):
            selected_akida_host_id = akida_hosts[0]["id"]
        if not akida_hosts:
            selected_akida_host_id = ""
        defaults.update(
            {
                "logLevel": stored.get("logLevel", DEFAULT_CONTROL_LOG_LEVEL),
                "mujocoAvailable": _mujoco_available(),
                "pythonAvailable": True,
                "akidaHosts": [
                    _normalize_akida_host(host)
                    for host in stored.get("akidaHosts", [])
                    if isinstance(host, dict)
                ],
                "pynqBoards": [
                    _normalize_pynq_board(board)
                    for board in stored.get("pynqBoards", [])
                    if isinstance(board, dict)
                ],
                "selectedAkidaHostId": selected_akida_host_id or None,
            }
        )
        return defaults

    def _load_workspace(self) -> dict[str, Any]:
        defaults = {
            "sessions": [],
            "focusedModuleId": None,
        }
        stored = _read_json_file(WORKSPACE_FILE, {})
        if not isinstance(stored, dict):
            return defaults
        sessions = [
            self._normalize_workspace_session(session)
            for session in stored.get("sessions", [])
            if isinstance(session, dict)
        ]
        sessions = self._dedupe_workspace_sessions(sessions)
        focused_module_id = str(stored.get("focusedModuleId") or "").strip() or None
        if focused_module_id and not any(
            session["moduleId"] == focused_module_id for session in sessions
        ):
            focused_module_id = sessions[-1]["moduleId"] if sessions else None
        return {
            "sessions": sessions,
            "focusedModuleId": focused_module_id,
        }

    def _normalize_workspace_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        module_id = self._canonicalize_workspace_module_id(
            str(payload.get("moduleId") or "").strip()
        )
        if not module_id:
            raise ValueError("Workspace session moduleId is required")
        if module_id not in self._modules:
            raise KeyError(f"Unknown module '{module_id}'")
        surface_mode = str(payload.get("surfaceMode") or "embedded").strip().lower()
        if surface_mode not in {"embedded", "native"}:
            surface_mode = "embedded"
        readiness_state = str(payload.get("readinessState") or "opening").strip().lower()
        if readiness_state not in {
            "opening",
            "warming_up",
            "ready",
            "degraded",
            "error",
            "restoring_session",
        }:
            readiness_state = "opening"
        deep_link = payload.get("deepLink")
        if deep_link is not None:
            deep_link = str(deep_link).strip() or None
        deep_link = self._canonicalize_workspace_deep_link(module_id, deep_link)
        restore_state = payload.get("restoreState")
        if not isinstance(restore_state, dict):
            restore_state = {}
        return {
            "moduleId": module_id,
            "surfaceMode": surface_mode,
            "deepLink": deep_link,
            "restoreState": restore_state,
            "readinessState": readiness_state,
        }

    def _canonicalize_workspace_module_id(self, module_id: str) -> str:
        if module_id == "Neurosim" and "neurocnl" in self._modules:
            return "neurocnl"
        return module_id

    def _canonicalize_workspace_deep_link(
        self, module_id: str, deep_link: str | None
    ) -> str | None:
        if module_id != "neurocnl":
            return deep_link
        if deep_link is None:
            return deep_link
        uri = urlparse(deep_link)
        if uri.path.startswith("/canvas"):
            return deep_link
        if uri.path in {"/", ""}:
            rewritten_path = "/canvas"
        elif uri.path.startswith("/projects") or uri.path.startswith("/sweep") or uri.path.startswith(
            "/export"
        ):
            rewritten_path = f"/canvas{uri.path}"
        else:
            return deep_link
        return urlunparse(uri._replace(path=rewritten_path))

    def _dedupe_workspace_sessions(
        self, sessions: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        deduped: list[dict[str, Any]] = []
        seen: set[str] = set()
        for session in sessions:
            module_id = session["moduleId"]
            if module_id in seen:
                continue
            deduped.append(session)
            seen.add(module_id)
        return deduped

    def _persist_workspace(self) -> None:
        _write_json_file(WORKSPACE_FILE, self._workspace)

    def get_workspace(self) -> dict[str, Any]:
        with self._lock:
            return {
                "sessions": [dict(session) for session in self._workspace["sessions"]],
                "focusedModuleId": self._workspace["focusedModuleId"],
            }

    def update_workspace(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            sessions = self._workspace["sessions"]
            if "sessions" in payload:
                raw_sessions = payload.get("sessions")
                if not isinstance(raw_sessions, list):
                    raise ValueError("Workspace sessions payload must be a list")
                sessions = self._dedupe_workspace_sessions(
                    [
                        self._normalize_workspace_session(session)
                        for session in raw_sessions
                        if isinstance(session, dict)
                    ]
                )
                self._workspace["sessions"] = sessions
            if "focusedModuleId" in payload:
                focused_module_id = str(payload.get("focusedModuleId") or "").strip() or None
                if focused_module_id and not any(
                    session["moduleId"] == focused_module_id for session in sessions
                ):
                    raise KeyError(f"Unknown workspace session '{focused_module_id}'")
                self._workspace["focusedModuleId"] = focused_module_id
            elif (
                self._workspace["focusedModuleId"] is not None
                and not any(
                    session["moduleId"] == self._workspace["focusedModuleId"]
                    for session in sessions
                )
            ):
                self._workspace["focusedModuleId"] = (
                    sessions[-1]["moduleId"] if sessions else None
                )
            self._persist_workspace()
            return self.get_workspace()

    def create_workspace_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            session = self._normalize_workspace_session(payload)
            sessions = [
                existing
                for existing in self._workspace["sessions"]
                if existing["moduleId"] != session["moduleId"]
            ]
            sessions.append(session)
            self._workspace["sessions"] = sessions
            self._workspace["focusedModuleId"] = session["moduleId"]
            self._persist_workspace()
            return self.get_workspace()

    def delete_workspace_session(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            sessions = [
                session
                for session in self._workspace["sessions"]
                if session["moduleId"] != module_id
            ]
            if len(sessions) == len(self._workspace["sessions"]):
                raise KeyError(f"Unknown workspace session '{module_id}'")
            self._workspace["sessions"] = sessions
            if self._workspace["focusedModuleId"] == module_id:
                self._workspace["focusedModuleId"] = (
                    sessions[-1]["moduleId"] if sessions else None
                )
            self._persist_workspace()
            return self.get_workspace()

    def serialize_modules(self, *, refresh_updates: bool = False) -> list[dict[str, Any]]:
        if refresh_updates:
            self.refresh_remote_versions()
        with self._lock:
            return [self._serialize_module(module) for module in self._modules.values()]

    def serialize_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            return self._serialize_module(module)

    def _serialize_module(self, module: dict[str, Any]) -> dict[str, Any]:
        payload = dict(module)
        payload["directory"] = module["directory"]
        payload["effectivePort"] = _effective_port(module)
        return payload

    def get_settings(self) -> dict[str, Any]:
        with self._lock:
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
                    _serialize_akida_host(host)
                    for host in self._settings["akidaHosts"]
                ],
                "selectedAkidaHostId": self._settings["selectedAkidaHostId"],
            }

    def update_settings(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            log_level = payload.get("logLevel")
            if isinstance(log_level, str) and log_level:
                self._settings["logLevel"] = log_level.lower()
            if "selectedAkidaHostId" in payload:
                selected_akida_host_id = str(
                    payload.get("selectedAkidaHostId") or ""
                ).strip()
                if not selected_akida_host_id:
                    self._settings["selectedAkidaHostId"] = None
                elif any(
                    host["id"] == selected_akida_host_id
                    for host in self._settings.get("akidaHosts", [])
                ):
                    self._settings["selectedAkidaHostId"] = selected_akida_host_id
                else:
                    raise KeyError(f"Unknown Akida host '{selected_akida_host_id}'")
            self._persist_settings()
            return self.get_settings()

    def _persist_settings(self) -> None:
        _write_json_file(SETTINGS_FILE, self._settings)

    def list_akida_hosts(self) -> list[dict[str, Any]]:
        with self._lock:
            hosts = self._settings.get("akidaHosts", [])
            return [_serialize_akida_host(host) for host in hosts]

    def get_akida_host(self, host_id: str) -> dict[str, Any]:
        with self._lock:
            host = self._get_akida_host(host_id)
            return _serialize_akida_host(host)

    def create_akida_host(self, payload: dict[str, Any]) -> dict[str, Any]:
        host = _normalize_akida_host(payload)
        if not _resolved_akida_base_url(host) and not str(host.get("host") or "").strip():
            raise ValueError("Akida host runtimeApiUrl or host is required")
        with self._lock:
            hosts = self._settings["akidaHosts"]
            if any(existing["id"] == host["id"] for existing in hosts):
                raise ValueError(f"Akida host '{host['id']}' already exists")
            if host.get("isDefault"):
                for existing in hosts:
                    existing["isDefault"] = False
            hosts.append(host)
            if not self._settings.get("selectedAkidaHostId"):
                self._settings["selectedAkidaHostId"] = host["id"]
            self._persist_settings()
            return _serialize_akida_host(host)

    def update_akida_host(
        self, host_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        with self._lock:
            host = self._get_akida_host(host_id)
            normalized = self._normalize_updated_akida_host(host, {"id": host_id, **payload})
            if normalized.get("isDefault"):
                for existing in self._settings.get("akidaHosts", []):
                    if existing["id"] != host_id:
                        existing["isDefault"] = False
            host.clear()
            host.update(normalized)
            self._persist_settings()
            return _serialize_akida_host(host)

    def delete_akida_host(self, host_id: str) -> None:
        with self._lock:
            hosts = self._settings["akidaHosts"]
            next_hosts = [host for host in hosts if host["id"] != host_id]
            if len(next_hosts) == len(hosts):
                raise KeyError(f"Unknown Akida host '{host_id}'")
            self._settings["akidaHosts"] = next_hosts
            if self._settings.get("selectedAkidaHostId") == host_id:
                self._settings["selectedAkidaHostId"] = (
                    next_hosts[0]["id"] if next_hosts else None
                )
            self._persist_settings()

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
            self._persist_settings()

    def _get_pynq_board(self, board_id: str) -> dict[str, Any]:
        for board in self._settings.get("pynqBoards", []):
            if board["id"] == board_id:
                return board
        raise KeyError(f"Unknown PYNQ board '{board_id}'")

    def _get_akida_host(self, host_id: str) -> dict[str, Any]:
        for host in self._settings.get("akidaHosts", []):
            if host["id"] == host_id:
                return host
        raise KeyError(f"Unknown Akida host '{host_id}'")

    def _update_akida_host_fields(self, host_id: str, **fields: Any) -> dict[str, Any]:
        with self._lock:
            host = self._get_akida_host(host_id)
            normalized = self._normalize_updated_akida_host(
                host, {"id": host_id, **fields}
            )
            host.clear()
            host.update(normalized)
            self._persist_settings()
            return dict(host)

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

    def _normalize_updated_akida_host(
        self,
        host: dict[str, Any],
        updates: dict[str, Any],
    ) -> dict[str, Any]:
        merged = dict(host)
        merged.update(updates)
        if "password" in updates and not str(updates.get("password") or ""):
            merged["password"] = str(host.get("password") or "")
        if str(merged.get("password") or "") and "authMode" not in updates:
            merged["authMode"] = "password"
        if "baseUrl" in updates and "runtimeApiUrl" not in updates:
            merged.pop("runtimeApiUrl", None)
        if "baseUrl" in updates and "port" not in updates:
            merged.pop("port", None)
        return _normalize_akida_host(merged)

    def _emit_pynq_terminal_log(
        self, board: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        stream = sys.stderr if stderr else sys.stdout
        board_label = str(
            board.get("displayName") or board.get("host") or board.get("id") or "pynq"
        )
        print(f"[pynq:{board_label}] {message}", file=stream, flush=True)

    def _prepare_ssh_invocation(
        self,
        board: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        prefix: list[str] = []
        env: dict[str, str] | None = None
        cleanup: Callable[[], None] | None = None
        auth_mode = str(board.get("authMode", DEFAULT_PYNQ_AUTH_MODE))
        if auth_mode == "password":
            password = str(board.get("password") or "")
            if not password:
                raise RuntimeError(
                    "No SSH password is configured for this PYNQ board"
                )
            sshpass = shutil.which("sshpass")
            if sshpass is not None:
                prefix.extend([sshpass, "-p", password])
            else:
                env, cleanup = _build_password_askpass_env(
                    password=password,
                    env_key="NMTK_PYNQ_PASSWORD",
                    prefix="nmtk-pynq-askpass-",
                )
        command = ["scp"] if copy_mode else ["ssh"]
        port_flag = "-P" if copy_mode else "-p"
        command.extend(
            [
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "UserKnownHostsFile=/dev/null",
                port_flag,
                str(
                    board.get("sshPort")
                    or _load_neurochip_launcher_runtime_contract().pynq.ssh_port
                ),
            ]
        )
        if auth_mode == "password":
            command.extend(
                [
                    "-o",
                    "PreferredAuthentications=password",
                    "-o",
                    "PubkeyAuthentication=no",
                    "-o",
                    "NumberOfPasswordPrompts=1",
                ]
            )
        if auth_mode == "ssh_key":
            ssh_key_path = str(board.get("sshKeyPath") or "").strip()
            if not ssh_key_path:
                raise RuntimeError("SSH-key authentication requires sshKeyPath")
            command.extend(["-i", ssh_key_path])
        return prefix + command, env, cleanup

    def _run_ssh(self, board: dict[str, Any], remote_command: str) -> str:
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self._prepare_ssh_invocation(board)
        command.extend([target, remote_command])
        self._emit_pynq_terminal_log(board, f"ssh -> {target}: {remote_command}")
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                stdin=subprocess.DEVNULL,
            )
            stdout_lines: list[str] = []
            stderr_lines: list[str] = []

            def _pump(stream: Any, sink: list[str], *, stderr: bool = False) -> None:
                for raw_line in iter(stream.readline, ""):
                    line = raw_line.rstrip()
                    if not line:
                        continue
                    sink.append(line)
                    self._emit_pynq_terminal_log(board, line, stderr=stderr)
                stream.close()

            stdout_thread = threading.Thread(
                target=_pump,
                args=(process.stdout, stdout_lines),
                name=f"pynq-ssh-stdout-{board['id']}",
            )
            stderr_thread = threading.Thread(
                target=_pump,
                args=(process.stderr, stderr_lines),
                kwargs={"stderr": True},
                name=f"pynq-ssh-stderr-{board['id']}",
            )
            stdout_thread.start()
            stderr_thread.start()
            return_code = process.wait()
            stdout_thread.join()
            stderr_thread.join()
        finally:
            if cleanup is not None:
                cleanup()
        if return_code != 0:
            message = _ssh_failure_message(stdout_lines, stderr_lines)
            raise RuntimeError(message)
        self._emit_pynq_terminal_log(board, "ssh step completed")
        return "\n".join(stdout_lines).strip()

    def _remote_pynq_install_status_path(self, board: dict[str, Any]) -> str:
        return str(
            board.get("remoteInstallStatusPath")
            or _load_neurochip_launcher_runtime_contract().pynq.install_status_path_for(
                str(board["remoteInstallRoot"])
            )
        )

    def _read_remote_pynq_install_status(self, board: dict[str, Any]) -> dict[str, Any]:
        raw = self._run_ssh(
            board,
            f"cat {self._remote_pynq_install_status_path(board)}",
        )
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Remote install status is not valid JSON: {raw}"
            ) from exc
        if not isinstance(decoded, dict):
            raise RuntimeError("Remote install status must decode to an object")
        return decoded

    def _wait_for_board_agent_health(
        self,
        board: dict[str, Any],
        timeout: float | None = None,
    ) -> None:
        effective_timeout = (
            _resolve_pynq_agent_health_timeout() if timeout is None else float(timeout)
        )
        base_url = _resolved_pynq_runtime_api_url(board).rstrip("/")
        health_url = f"{base_url}/health"
        self._emit_pynq_terminal_log(
            board,
            f"polling agent health at {health_url} (timeout {effective_timeout:.0f}s)",
        )
        start = time.monotonic()
        deadline = start + effective_timeout
        last_exc: Exception | None = None
        heartbeat_emitted = False
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(health_url, timeout=2.0) as resp:
                    if resp.status == 200:
                        self._emit_pynq_terminal_log(board, "agent health check passed")
                        return
            except Exception as exc:
                last_exc = exc
            elapsed = time.monotonic() - start
            if (
                not heartbeat_emitted
                and elapsed >= PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS
            ):
                self._emit_pynq_terminal_log(
                    board, f"still polling /health ({elapsed:.0f}s elapsed)"
                )
                heartbeat_emitted = True
            time.sleep(1.0)
        raise RuntimeError(
            f"Agent at {health_url} did not become healthy within {effective_timeout:.0f}s"
            + (f": {last_exc}" if last_exc else "")
        )

    def _emit_runtime_log_tail(
        self,
        board: dict[str, Any],
        install_status: dict[str, Any],
        *,
        lines: int = PYNQ_RUNTIME_LOG_TAIL_LINES,
    ) -> None:
        runtime_log_path = str(
            install_status.get("runtimeLogPath")
            or board.get("remoteRuntimeLogPath")
            or _load_neurochip_launcher_runtime_contract().pynq.runtime_log_path_for(
                str(board["remoteInstallRoot"])
            )
        )
        self._emit_pynq_terminal_log(
            board, f"fetching last {lines} lines of {runtime_log_path}"
        )
        try:
            tail = self._run_ssh(board, f"tail -n {int(lines)} {runtime_log_path}")
        except Exception as exc:  # noqa: BLE001
            self._emit_pynq_terminal_log(
                board,
                f"could not read remote runtime log at {runtime_log_path}: {exc}",
                stderr=True,
            )
            return
        for line in tail.splitlines() or [tail]:
            if line:
                self._emit_pynq_terminal_log(
                    board, f"runtime.log | {line}", stderr=True
                )

    def _build_remote_pynq_user_space_launch_command(
        self,
        *,
        agent_venv_path: str,
        pynq_venv_path: str,
        install_status_path: str,
        overlay_dir: str,
        runtime_log_path: str,
        agent_executable_name: str,
    ) -> str:
        return build_pynq_user_space_agent_launch_command(
            agent_executable=f"{agent_venv_path}/bin/{agent_executable_name}",
            pynq_python_path=f"{pynq_venv_path}/bin/python",
            install_status_path=install_status_path,
            overlay_dir=overlay_dir,
            runtime_log_path=runtime_log_path,
        )

    def _run_ssh_detached(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        ssh_timeout: float = 15.0,
    ) -> None:
        """Run an SSH command that starts a detached background process.

        sshd keeps the channel open until all its pipe fds reach EOF, which
        prevents the SSH client from exiting even after the remote shell exits.
        We tolerate this by killing the local SSH client after ssh_timeout seconds;
        the remote background process continues running independently.
        """
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self._prepare_ssh_invocation(board)
        command.extend([target, remote_command])
        self._emit_pynq_terminal_log(
            board, f"ssh (detached) -> {target}: {remote_command}"
        )
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=ssh_timeout,
                check=False,
                env=env,
                stdin=subprocess.DEVNULL,
            )
            if result.stdout.strip():
                self._emit_pynq_terminal_log(board, result.stdout.strip())
            if result.stderr.strip():
                self._emit_pynq_terminal_log(board, result.stderr.strip())
            if result.returncode != 0:
                stderr_lines = [
                    line.strip() for line in result.stderr.splitlines() if line.strip()
                ]
                non_benign_stderr = [
                    line
                    for line in stderr_lines
                    if not _is_benign_ssh_warning_line(line)
                ]
                if non_benign_stderr:
                    raise RuntimeError("\n".join(non_benign_stderr))
                stdout_lines = [
                    line.strip() for line in result.stdout.splitlines() if line.strip()
                ]
                if stdout_lines:
                    raise RuntimeError("\n".join(stdout_lines))
                self._emit_pynq_terminal_log(
                    board,
                    "ssh step completed with only benign SSH warnings; proceeding to health check",
                )
                return
            self._emit_pynq_terminal_log(board, "ssh step completed")
        except subprocess.TimeoutExpired:
            self._emit_pynq_terminal_log(
                board,
                f"ssh client timed out after {ssh_timeout:.0f}s; "
                "background agent process was already started — proceeding to health check",
            )
        finally:
            if cleanup is not None:
                cleanup()

    def _restart_user_space_agent(
        self, board: dict[str, Any], install_status: dict[str, Any]
    ) -> None:
        agent_venv_path = str(
            install_status.get("agentVenvPath") or board["remoteVenvPath"]
        )
        pynq_venv_path = str(
            install_status.get("pynqVenvPath") or board["remotePynqVenvPath"]
        )
        runtime_log_path = str(
            install_status.get("runtimeLogPath")
            or board.get("remoteRuntimeLogPath")
            or _load_neurochip_launcher_runtime_contract().pynq.runtime_log_path_for(
                str(board["remoteInstallRoot"])
            )
        )
        install_status_path = self._remote_pynq_install_status_path(board)
        overlay_dir = str(board["remoteOverlayDir"])
        agent_executable_name = str(
            board.get("agentExecutableName")
            or _load_neurochip_launcher_runtime_contract().pynq.agent_executable_name
        )
        self._emit_pynq_terminal_log(
            board,
            f"restarting user-space agent with NEUROCHIP_PYNQ_OVERLAY_DIR={overlay_dir}",
        )
        launch_command = self._build_remote_pynq_user_space_launch_command(
            agent_venv_path=agent_venv_path,
            pynq_venv_path=pynq_venv_path,
            install_status_path=install_status_path,
            overlay_dir=overlay_dir,
            runtime_log_path=runtime_log_path,
            agent_executable_name=agent_executable_name,
        )
        restart_cmd = (
            f'pkill -f "{agent_venv_path}/bin/{agent_executable_name}" >/dev/null 2>&1 || true; '
            f"sleep 1; "
            f"{launch_command}"
        )
        self._run_ssh_detached(board, restart_cmd)
        self._emit_pynq_terminal_log(
            board, "waiting for restarted agent to become healthy"
        )
        self._wait_for_board_agent_health(board)

    def _run_scp(
        self,
        board: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None:
        command, env, cleanup = self._prepare_ssh_invocation(board, copy_mode=True)
        if recursive:
            command.append("-r")
        target = f"{board['username']}@{board['host']}:{remote_path}"
        command.extend([str(local_path), target])
        self._emit_pynq_terminal_log(board, f"scp -> {target} from {local_path}")
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=False,
                env=env,
                stdin=subprocess.DEVNULL,
            )
        finally:
            if cleanup is not None:
                cleanup()
        if result.returncode != 0:
            self._emit_pynq_terminal_log(
                board,
                result.stderr.strip() or result.stdout.strip() or "scp command failed",
                stderr=True,
            )
            raise RuntimeError(
                result.stderr.strip() or result.stdout.strip() or "scp command failed"
            )
        self._emit_pynq_terminal_log(board, "scp step completed")

    def _runtime_json_request(
        self,
        board: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 15.0,
    ) -> dict[str, Any]:
        base_url = _resolved_pynq_runtime_api_url(board).rstrip("/")
        url = f"{base_url}{path}"
        headers = {"Content-Type": "application/json"}
        credential_ref = str(board.get("credentialRef") or "").strip()
        if credential_ref:
            headers["X-API-Key"] = credential_ref
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read().decode("utf-8")
                decoded = json.loads(body) if body else {}
                if not isinstance(decoded, dict):
                    raise RuntimeError(f"Unexpected runtime response from {url}")
                return decoded
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            self._emit_pynq_terminal_log(
                board,
                (
                    f"runtime request failed: {method} {url} returned HTTP {exc.code}"
                    + (f" with body: {error_body}" if error_body else "")
                ),
                stderr=True,
            )
            raise RuntimeRequestError(
                f"Runtime request failed for {method} {url}: HTTP {exc.code}"
                + (f" - {error_body}" if error_body else ""),
                kind="http",
                url=url,
                status_code=exc.code,
                response_body=error_body,
            ) from exc
        except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
            kind = _runtime_request_error_kind(exc)
            if kind == "timeout":
                detail = f"timed out after {timeout:.0f}s"
            else:
                detail = f"could not be reached: {exc}"
            self._emit_pynq_terminal_log(
                board,
                f"runtime request failed: {method} {url} {detail}",
                stderr=True,
            )
            raise RuntimeRequestError(
                (
                    f"Runtime request failed for {method} {url}: {detail}"
                    if kind != "timeout"
                    else f"Runtime request timed out for {method} {url} after {timeout:.0f}s"
                ),
                kind=kind,
                url=url,
            ) from exc

    def _apply_preflight_to_board(
        self,
        board_id: str,
        preflight: dict[str, Any],
        *,
        fallback_error_state: str = "error",
    ) -> dict[str, Any]:
        status = str(preflight.get("preflight_status") or "").strip().lower()
        message = str(preflight.get("preflight_message") or "").strip()
        runtime_mode = str(preflight.get("runtime_mode") or "").strip()
        overlay_assets = preflight.get("overlay_assets")
        board_state = fallback_error_state
        if status == PREFLIGHT_OK:
            board_state = "ready"
        elif status == PREFLIGHT_DEGRADED:
            board_state = "degraded_optional_capability"
        elif status == PREFLIGHT_FAILED:
            if isinstance(overlay_assets, dict) and not overlay_assets.get(
                "ready_for_hardware", False
            ):
                board_state = "overlay_missing"
            else:
                board_state = "preflight_failed"
        return self._update_pynq_board_fields(
            board_id,
            state=board_state,
            lastPreflightStatus=status,
            lastPreflightMessage=message,
            lastRuntimeMode=runtime_mode,
        )

    def test_pynq_board_connection(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "testing SSH connectivity")
        self._run_ssh(board, "python3 --version")
        self._emit_pynq_terminal_log(board, "SSH connectivity succeeded")
        return _serialize_pynq_board(
            self._update_pynq_board_fields(
                board_id, state="reachable", lastPreflightMessage="SSH reachable"
            )
        )

    def fetch_pynq_board_preflight(
        self,
        board_id: str,
        *,
        request_timeout: float | None = None,
    ) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "requesting runtime preflight")
        preflight = self._runtime_json_request(
            board,
            "GET",
            "/hardware/pynq/preflight",
            timeout=(
                _resolve_pynq_preflight_timeout()
                if request_timeout is None
                else float(request_timeout)
            ),
        )
        self._emit_pynq_terminal_log(
            board,
            _describe_pynq_preflight(preflight),
        )
        updated = self._apply_preflight_to_board(board_id, preflight)
        return {
            "board": _serialize_pynq_board(updated),
            "preflight": preflight,
        }

    def _refresh_pynq_board_preflight(self, board_id: str, *, stage: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        request_timeout = _resolve_pynq_preflight_timeout()
        last_error: RuntimeRequestError | None = None
        for attempt in range(1, PYNQ_PREFLIGHT_RETRY_COUNT + 1):
            try:
                return self.fetch_pynq_board_preflight(
                    board_id,
                    request_timeout=request_timeout,
                )
            except RuntimeRequestError as exc:
                last_error = exc
                if exc.kind not in {"timeout", "unreachable"}:
                    raise
                if attempt >= PYNQ_PREFLIGHT_RETRY_COUNT:
                    break
                if exc.kind == "timeout":
                    self._emit_pynq_terminal_log(
                        board,
                        (
                            f"runtime preflight is still running after {request_timeout:.0f}s "
                            f"during {stage}; retrying ({attempt + 1}/{PYNQ_PREFLIGHT_RETRY_COUNT})"
                        ),
                    )
                else:
                    self._emit_pynq_terminal_log(
                        board,
                        (
                            f"runtime preflight could not reach the agent during {stage}; "
                            f"rechecking /health before retry ({attempt + 1}/{PYNQ_PREFLIGHT_RETRY_COUNT})"
                        ),
                    )
                    try:
                        self._wait_for_board_agent_health(
                            board,
                            timeout=min(
                                _resolve_pynq_agent_health_timeout(),
                                request_timeout,
                            ),
                        )
                    except RuntimeError as health_exc:
                        self._emit_pynq_terminal_log(
                            board,
                            f"/health was not stable during {stage}: {health_exc}",
                            stderr=True,
                        )
                time.sleep(PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS)
        if last_error is not None:
            raise last_error
        raise RuntimeError(f"Runtime preflight refresh failed during {stage}")

    def fetch_pynq_board_status(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "requesting runtime status")
        status = self._runtime_json_request(board, "GET", "/hardware/pynq/status")
        updated = self._update_pynq_board_fields(
            board_id,
            lastStatus=status,
            lastRuntimeMode=str(status.get("runtime_mode") or "").strip(),
        )
        return {"board": _serialize_pynq_board(updated), "status": status}

    def _build_local_pynq_bundle(
        self, board: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]:
        neurochip_root = _neurochip_module_root()

        overlay_version = str(board.get("overlayVersion") or "dev")
        return build_pynq_agent_bundle(
            bundle_dir,
            overlay_version=overlay_version,
            repo_root=neurochip_root,
            install_root=str(board["remoteInstallRoot"]),
            agent_venv_path=str(board["remoteVenvPath"]),
            pynq_venv_path=str(board["remotePynqVenvPath"]),
            overlay_dir=str(board["remoteOverlayDir"]),
            service_name=str(board["remoteServiceName"]),
            agent_executable_name=str(board["agentExecutableName"]),
            install_status_path=str(board["remoteInstallStatusPath"]),
            runtime_log_path=str(board["remoteRuntimeLogPath"]),
        )

    def _inspect_local_pynq_overlay_package(self) -> dict[str, Any]:
        neurochip_root = _neurochip_module_root()
        staging_dir = _load_neurochip_launcher_runtime_contract().pynq.overlay_staging_dir_for(
            neurochip_root
        )
        return _inspect_staged_pynq_overlay_package(staging_dir)

    def provision_pynq_board(self, board_id: str) -> dict[str, Any]:
        board = self._update_pynq_board_fields(board_id, state="provisioning")
        self._emit_pynq_terminal_log(board, "starting runtime provisioning")
        install_status: dict[str, Any] = {}
        install_mode = "unknown"
        install_script_started = False
        try:
            with tempfile.TemporaryDirectory(prefix="pynq-agent-bundle-") as tmp_dir:
                bundle_dir = Path(tmp_dir) / "bundle"
                bundle_dir.mkdir(parents=True, exist_ok=True)
                self._emit_pynq_terminal_log(board, "building local PYNQ agent bundle")
                self._build_local_pynq_bundle(board, bundle_dir)
                remote_bundle_parent = "/tmp"
                remote_bundle_dir = f"{remote_bundle_parent}/{bundle_dir.name}"
                self._emit_pynq_terminal_log(
                    board,
                    f"preparing remote install directories at {board['remoteInstallRoot']}",
                )
                self._run_ssh(
                    board,
                    (
                        f"mkdir -p {board['remoteInstallRoot']} {board['remoteOverlayDir']} "
                        f"&& rm -rf {remote_bundle_dir}"
                    ),
                )
                self._emit_pynq_terminal_log(
                    board, f"uploading provisioning bundle to {remote_bundle_parent}"
                )
                self._run_scp(board, bundle_dir, remote_bundle_parent, recursive=True)
                self._emit_pynq_terminal_log(board, "running remote install script")
                install_script_started = True
                self._run_ssh(
                    board,
                    " ".join(
                        [
                            f"INSTALL_ROOT={board['remoteInstallRoot']}",
                            f"AGENT_VENV_PATH={board['remoteVenvPath']}",
                            f"PYNQ_VENV_PATH={board['remotePynqVenvPath']}",
                            f"OVERLAY_DIR={board['remoteOverlayDir']}",
                            f"SERVICE_NAME={board['remoteServiceName']}",
                            f"AGENT_EXECUTABLE_NAME={board['agentExecutableName']}",
                            f"INSTALL_STATUS_PATH={board['remoteInstallStatusPath']}",
                            f"RUNTIME_LOG_PATH={board['remoteRuntimeLogPath']}",
                            f"bash {remote_bundle_dir}/install-pynq-agent.sh",
                        ]
                    ),
                )
                install_status = self._read_remote_pynq_install_status(board)
                install_mode = (
                    str(install_status.get("installMode") or "unknown").strip()
                    or "unknown"
                )
                self._emit_pynq_terminal_log(
                    board,
                    f"runtime install mode resolved to {install_mode}",
                )
            self._update_pynq_board_fields(board_id, state="runtime_installed")
            self._emit_pynq_terminal_log(
                board, "runtime install finished; fetching preflight"
            )
            result = self._refresh_pynq_board_preflight(
                board_id,
                stage="runtime provisioning",
            )
            board_state = str(result.get("board", {}).get("state") or "").strip()
            if board_state == "overlay_missing":
                self._emit_pynq_terminal_log(
                    board,
                    "runtime installed successfully; overlay assets are still missing, so the board is not hardware-ready yet",
                )
            if (
                board_state == "degraded_optional_capability"
                and install_mode == "user-space"
            ):
                guidance = _pynq_user_space_upgrade_message(
                    str(board.get("username") or "")
                )
                updated = self._update_pynq_board_fields(
                    board_id,
                    state="degraded_optional_capability",
                    lastPreflightStatus=PREFLIGHT_DEGRADED,
                    lastPreflightMessage=guidance,
                )
                result["board"] = _serialize_pynq_board(updated)
                preflight = result.get("preflight")
                if isinstance(preflight, dict):
                    preflight["preflight_message"] = guidance
            result["installStatus"] = install_status
            return result
        except Exception as exc:  # noqa: BLE001
            if install_script_started:
                self._emit_runtime_log_tail(board, install_status)
            self._emit_pynq_terminal_log(
                board, f"runtime provisioning failed: {exc}", stderr=True
            )
            updated = self._update_pynq_board_fields(
                board_id,
                state="provision_failed",
                lastPreflightMessage=str(exc),
            )
            return {"board": _serialize_pynq_board(updated), "error": str(exc)}

    def install_pynq_overlay_assets(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "starting overlay asset install")
        overlay_package = self._inspect_local_pynq_overlay_package()
        bitstream = Path(str(overlay_package["bitstreamPath"]))
        hwh = Path(str(overlay_package["hwhPath"]))
        manifest = Path(str(overlay_package["manifestPath"]))
        if not bool(overlay_package.get("ready", False)):
            issues = overlay_package.get("issues", [])
            issues_text = (
                "; ".join(str(issue) for issue in issues)
                if isinstance(issues, list) and issues
                else "staged overlay package is incomplete"
            )
            message = (
                "Local staged overlay package is incomplete. "
                f"Stage externally built snn_overlay.bit and snn_overlay.hwh under "
                f"{overlay_package['stagingDir']}. "
                f"Details: {issues_text}"
            )
            self._emit_pynq_terminal_log(
                board,
                message,
                stderr=True,
            )
            updated = self._update_pynq_board_fields(
                board_id,
                state="overlay_missing",
                lastPreflightMessage=message,
            )
            return {
                "board": _serialize_pynq_board(updated),
                "localOverlayPackage": overlay_package,
            }
        self._emit_pynq_terminal_log(
            board,
            f"using staged overlay package from {overlay_package['stagingDir']}",
        )
        self._emit_pynq_terminal_log(
            board, f"ensuring remote overlay dir {board['remoteOverlayDir']}"
        )
        self._run_ssh(board, f"mkdir -p {board['remoteOverlayDir']}")
        self._emit_pynq_terminal_log(board, "uploading snn_overlay.bit")
        self._run_scp(board, bitstream, f"{board['remoteOverlayDir']}/snn_overlay.bit")
        self._emit_pynq_terminal_log(board, "uploading snn_overlay.hwh")
        self._run_scp(board, hwh, f"{board['remoteOverlayDir']}/snn_overlay.hwh")
        self._emit_pynq_terminal_log(board, "uploading overlay_manifest.json")
        self._run_scp(
            board, manifest, f"{board['remoteOverlayDir']}/overlay_manifest.json"
        )
        self._emit_pynq_terminal_log(
            board, "overlay upload finished; checking install mode"
        )
        try:
            install_status = self._read_remote_pynq_install_status(board)
        except Exception:
            install_status = {}
        install_mode = str(install_status.get("installMode") or "unknown").strip()
        restart_warning: str | None = None
        if install_mode == "user-space":
            try:
                self._restart_user_space_agent(board, install_status)
            except RuntimeError as exc:
                restart_warning = str(exc)
                self._emit_runtime_log_tail(board, install_status)
                self._emit_pynq_terminal_log(
                    board,
                    (
                        f"user-space agent restart did not become healthy: {exc}; "
                        "overlay files are uploaded — restart the board or run "
                        "restart-runtime manually"
                    ),
                    stderr=True,
                )
        self._emit_pynq_terminal_log(board, "fetching preflight")
        try:
            result = self._refresh_pynq_board_preflight(
                board_id,
                stage="overlay install",
            )
        except Exception as exc:
            if install_mode != "user-space":
                raise
            if restart_warning is None:
                restart_warning = (
                    "Follow-up preflight could not reach the runtime after overlay upload: "
                    f"{exc}"
                )
                self._emit_pynq_terminal_log(
                    board,
                    (
                        "readiness refresh after overlay upload did not complete: "
                        f"{exc}; {PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE}"
                    ),
                    stderr=True,
                )
            updated = self._update_pynq_board_fields(
                board_id,
                state="degraded_optional_capability",
                lastPreflightStatus=PREFLIGHT_DEGRADED,
                lastPreflightMessage=PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
            )
            result = {
                "board": _serialize_pynq_board(updated),
                "preflight": {
                    "preflight_status": PREFLIGHT_DEGRADED,
                    "preflight_message": PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
                    "runtime_mode": str(updated.get("lastRuntimeMode") or "unknown"),
                },
            }
        result["localOverlayPackage"] = overlay_package
        if restart_warning is not None:
            result["overlayRestartWarning"] = restart_warning
        return result

    def restart_pynq_runtime(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        install_status = self._read_remote_pynq_install_status(board)
        install_mode = (
            str(install_status.get("installMode") or "unknown").strip() or "unknown"
        )
        if install_mode == "user-space":
            message = _pynq_user_space_upgrade_message(str(board.get("username") or ""))
            updated = self._update_pynq_board_fields(
                board_id,
                state="degraded_optional_capability",
                lastPreflightStatus=PREFLIGHT_DEGRADED,
                lastPreflightMessage=message,
            )
            self._emit_pynq_terminal_log(board, message)
            return {
                "board": _serialize_pynq_board(updated),
                "warning": message,
                "installStatus": install_status,
            }
        self._emit_pynq_terminal_log(
            board, f"restarting systemd service {board['remoteServiceName']}.service"
        )
        self._run_ssh(
            board, f"sudo systemctl restart {board['remoteServiceName']}.service"
        )
        self._emit_pynq_terminal_log(
            board, "waiting for restarted systemd service to become healthy"
        )
        self._wait_for_board_agent_health(board)
        self._emit_pynq_terminal_log(
            board, "runtime restart completed; fetching preflight"
        )
        result = self._refresh_pynq_board_preflight(board_id, stage="runtime restart")
        result["installStatus"] = install_status
        return result

    def proxy_pynq_deploy(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        response = self._runtime_json_request(
            board, "POST", "/hardware/pynq/deploy", payload, timeout=120.0
        )
        return response

    def proxy_pynq_verify(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        return self._runtime_json_request(
            board, "POST", "/hardware/pynq/verify", payload
        )

    def proxy_pynq_run(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        return self._runtime_json_request(
            board, "POST", "/hardware/pynq/run", payload,
            timeout=_resolve_pynq_run_timeout(),
        )

    def proxy_pynq_runtime_status(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        return self._runtime_json_request(board, "GET", "/hardware/pynq/status")

    def proxy_akida_map(
        self,
        host_id: str,
        payload: dict[str, Any],
        *,
        bit_width: int = 4,
    ) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(
            host, f"proxying runtime map request (bit_width={bit_width})"
        )
        status = self._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/map?bit_width={bit_width}",
            payload,
        )
        self._emit_akida_terminal_log(
            host,
            (
                "runtime map completed with target "
                f"{str(status.get('runtime_target') or 'unknown').strip() or 'unknown'}"
            ),
        )
        self._update_akida_host_fields(
            host_id,
            state=_akida_host_state_for_status(host, status),
            lastStatus=status,
        )
        return status

    def proxy_akida_run(self, host_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "proxying runtime inference request")
        result = self._akida_json_request(
            host,
            "POST",
            "/api/neurochip/akida/inference",
            payload,
        )
        self._emit_akida_terminal_log(
            host,
            (
                "runtime inference completed on "
                f"{str(result.get('runtime_target') or 'unknown').strip() or 'unknown'}"
            ),
        )
        return result

    def _emit_akida_terminal_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        stream = sys.stderr if stderr else sys.stdout
        host_label = str(
            host.get("displayName") or host.get("host") or host.get("id") or "akida"
        )
        print(f"[akida:{host_label}] {message}", file=stream, flush=True)

    def _prepare_akida_ssh_invocation(
        self,
        host: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        prefix: list[str] = []
        env: dict[str, str] | None = None
        cleanup: Callable[[], None] | None = None
        auth_mode = str(host.get("authMode", DEFAULT_AKIDA_AUTH_MODE))
        if auth_mode not in {"password", "ssh_key"}:
            raise RuntimeError(
                "Akida host SSH operations require password or SSH-key authentication"
            )
        if auth_mode == "password":
            password = str(host.get("password") or "")
            if not password:
                raise RuntimeError(
                    "No SSH password is configured for this Akida host"
                )
            sshpass = shutil.which("sshpass")
            if sshpass is not None:
                prefix.extend([sshpass, "-p", password])
            else:
                env, cleanup = _build_password_askpass_env(
                    password=password,
                    env_key="NMTK_AKIDA_PASSWORD",
                    prefix="nmtk-akida-askpass-",
                )
        command = ["scp"] if copy_mode else ["ssh"]
        port_flag = "-P" if copy_mode else "-p"
        command.extend(
            [
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "UserKnownHostsFile=/dev/null",
                port_flag,
                str(
                    host.get("sshPort")
                    or _load_neurochip_launcher_runtime_contract().akida.ssh_port
                ),
            ]
        )
        if auth_mode == "password":
            command.extend(
                [
                    "-o",
                    "PreferredAuthentications=password",
                    "-o",
                    "PubkeyAuthentication=no",
                    "-o",
                    "NumberOfPasswordPrompts=1",
                ]
            )
        if auth_mode == "ssh_key":
            ssh_key_path = str(host.get("sshKeyPath") or "").strip()
            if not ssh_key_path:
                raise RuntimeError("SSH-key authentication requires sshKeyPath")
            command.extend(["-i", ssh_key_path])
        return prefix + command, env, cleanup

    def _akida_remote_command_with_sudo_password(
        self,
        host: dict[str, Any],
        remote_command: str,
    ) -> tuple[str, str]:
        password = str(host.get("password") or "")
        if str(host.get("authMode") or "").strip() != "password" or not password:
            return remote_command, remote_command
        return (
            f"NMTK_AKIDA_SUDO_PASSWORD={shlex.quote(password)} {remote_command}",
            f"NMTK_AKIDA_SUDO_PASSWORD=<redacted> {remote_command}",
        )

    def _run_akida_ssh(
        self,
        host: dict[str, Any],
        remote_command: str,
        *,
        display_command: str | None = None,
    ) -> str:
        username = str(host.get("username") or "").strip()
        if not username:
            raise RuntimeError("Akida host username is required for SSH operations")
        target = f"{username}@{host['host']}"
        command, env, cleanup = self._prepare_akida_ssh_invocation(host)
        command.extend([target, remote_command])
        logged_command = display_command if display_command is not None else remote_command
        self._emit_akida_terminal_log(host, f"ssh -> {target}: {logged_command}")
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                stdin=subprocess.DEVNULL,
            )
            stdout_lines: list[str] = []
            stderr_lines: list[str] = []

            def _pump(stream: Any, sink: list[str], *, stderr: bool = False) -> None:
                for raw_line in iter(stream.readline, ""):
                    line = raw_line.rstrip()
                    if not line:
                        continue
                    sink.append(line)
                    self._emit_akida_terminal_log(host, line, stderr=stderr)
                stream.close()

            stdout_thread = threading.Thread(
                target=_pump,
                args=(process.stdout, stdout_lines),
                name=f"akida-ssh-stdout-{host['id']}",
            )
            stderr_thread = threading.Thread(
                target=_pump,
                args=(process.stderr, stderr_lines),
                kwargs={"stderr": True},
                name=f"akida-ssh-stderr-{host['id']}",
            )
            stdout_thread.start()
            stderr_thread.start()
            return_code = process.wait()
            stdout_thread.join()
            stderr_thread.join()
        finally:
            if cleanup is not None:
                cleanup()
        if return_code != 0:
            message = _ssh_failure_message(stdout_lines, stderr_lines)
            raise RuntimeError(message)
        self._emit_akida_terminal_log(host, "ssh step completed")
        return "\n".join(stdout_lines).strip()

    def _run_akida_scp(
        self,
        host: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None:
        username = str(host.get("username") or "").strip()
        if not username:
            raise RuntimeError("Akida host username is required for SCP operations")
        command, env, cleanup = self._prepare_akida_ssh_invocation(host, copy_mode=True)
        if recursive:
            command.append("-r")
        target = f"{username}@{host['host']}:{remote_path}"
        command.extend([str(local_path), target])
        self._emit_akida_terminal_log(host, f"scp -> {target} from {local_path}")
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=False,
                env=env,
                stdin=subprocess.DEVNULL,
            )
        finally:
            if cleanup is not None:
                cleanup()
        if result.returncode != 0:
            self._emit_akida_terminal_log(
                host,
                result.stderr.strip() or result.stdout.strip() or "scp command failed",
                stderr=True,
            )
            raise RuntimeError(
                result.stderr.strip() or result.stdout.strip() or "scp command failed"
            )
        self._emit_akida_terminal_log(host, "scp step completed")

    def _akida_control_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        emit_terminal_errors: bool = True,
    ) -> dict[str, Any]:
        base_url = _resolved_akida_control_api_url(host).rstrip("/")
        if not base_url:
            raise RuntimeError("Akida host controlApiUrl is not configured")
        url = f"{base_url}{path}"
        headers = {"Content-Type": "application/json"}
        credential_ref = str(host.get("credentialRef") or "").strip()
        if credential_ref:
            headers["X-API-Key"] = credential_ref
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=15.0) as response:
                body = response.read().decode("utf-8")
                decoded = json.loads(body) if body else {}
                if not isinstance(decoded, dict):
                    raise RuntimeError(f"Unexpected control response from {url}")
                return decoded
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            if emit_terminal_errors:
                self._emit_akida_terminal_log(
                    host,
                    (
                        f"control request failed: {method} {url} returned HTTP {exc.code}"
                        + (f" with body: {error_body}" if error_body else "")
                    ),
                    stderr=True,
                )
            raise RuntimeRequestError(
                f"Control request failed for {method} {url}: HTTP {exc.code}"
                + (f" — {error_body}" if error_body else ""),
                kind="http",
                url=url,
                status_code=exc.code,
                response_body=error_body,
            ) from exc
        except urllib.error.URLError as exc:
            kind = _runtime_request_error_kind(exc)
            detail = (
                "timed out"
                if kind == "timeout"
                else f"could not be reached: {exc}"
            )
            if emit_terminal_errors:
                self._emit_akida_terminal_log(
                    host,
                    f"control request failed: {method} {url} {detail}",
                    stderr=True,
                )
            raise RuntimeRequestError(
                f"Control request failed for {method} {url}: {detail}",
                kind=kind,
                url=url,
            ) from exc

    def _akida_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        base_url = _resolved_akida_base_url(host).rstrip("/")
        if not base_url:
            raise RuntimeError("Akida host baseUrl is not configured")
        url = f"{base_url}{path}"
        headers = {"Content-Type": "application/json"}
        credential_ref = str(host.get("credentialRef") or "").strip()
        if credential_ref:
            headers["X-API-Key"] = credential_ref
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=15.0) as response:
                body = response.read().decode("utf-8")
                decoded = json.loads(body) if body else {}
                if not isinstance(decoded, dict):
                    raise RuntimeError(f"Unexpected runtime response from {url}")
                return decoded
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            self._emit_akida_terminal_log(
                host,
                (
                    f"runtime request failed: {method} {url} returned HTTP {exc.code}"
                    + (f" with body: {error_body}" if error_body else "")
                ),
                stderr=True,
            )
            raise RuntimeRequestError(
                f"Runtime request failed for {method} {url}: HTTP {exc.code}"
                + (f" — {error_body}" if error_body else ""),
                kind="http",
                url=url,
                status_code=exc.code,
                response_body=error_body,
            ) from exc
        except urllib.error.URLError as exc:
            kind = _runtime_request_error_kind(exc)
            detail = (
                "timed out"
                if kind == "timeout"
                else f"could not be reached: {exc}"
            )
            self._emit_akida_terminal_log(
                host,
                f"runtime request failed: {method} {url} {detail}",
                stderr=True,
            )
            raise RuntimeRequestError(
                f"Runtime request failed for {method} {url}: {detail}",
                kind=kind,
                url=url,
            ) from exc

    def test_akida_host_connection(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        if str(host.get("username") or "").strip():
            self._emit_akida_terminal_log(host, "testing SSH connectivity")
            self._run_akida_ssh(host, "python3 --version")
            self._emit_akida_terminal_log(host, "SSH connectivity succeeded")
            message = "SSH reachable"
        else:
            self._emit_akida_terminal_log(host, "testing HTTP connectivity")
            health = self._akida_json_request(host, "GET", "/health")
            health_status = str(health.get("status") or "ok").strip() or "ok"
            self._emit_akida_terminal_log(host, "HTTP connectivity succeeded")
            message = f"Health reachable: {health_status}"
        return _serialize_akida_host(
            self._update_akida_host_fields(
                host_id,
                state="reachable",
                lastPreflightMessage=message,
            )
        )

    def _build_local_akida_bundle(
        self, host: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]:
        neurochip_module = self._get_module("Neurochip")
        neurochip_root = _module_root(neurochip_module)
        akida_runtime = neurochip_module.get("akidaRuntime", {})
        required_packages = akida_runtime.get("requiredPackages", [])
        if not isinstance(required_packages, list) or not all(
            isinstance(item, str) for item in required_packages
        ):
            raise RuntimeError("Neurochip Akida runtime manifest is invalid")
        akida_contract = _load_neurochip_launcher_runtime_contract().akida
        return build_akida_host_bundle(
            bundle_dir,
            repo_root=neurochip_root,
            required_packages=required_packages,
            install_root=str(host["remoteInstallRoot"]),
            service_user=str(host["serviceUser"]),
            venv_path=str(host["remoteVenvPath"]),
            runtime_service_name=str(host["runtimeServiceName"]),
            control_service_name=str(host["controlServiceName"]),
            runtime_port=int(host.get("port") or akida_contract.runtime_port),
            control_port=int(host.get("controlPort") or akida_contract.control_port),
            token_path=str(host["tokenPath"]),
            install_status_path=str(host["installStatusPath"]),
        )

    def _remote_akida_install_status_path(self, host: dict[str, Any]) -> str:
        return str(
            host.get("installStatusPath")
            or _load_neurochip_launcher_runtime_contract().akida.install_status_path_for(
                str(host["remoteInstallRoot"])
            )
        )

    def _read_remote_akida_install_status(self, host: dict[str, Any]) -> dict[str, Any]:
        raw = self._run_akida_ssh(host, f"cat {self._remote_akida_install_status_path(host)}")
        raw = raw.strip()
        if not raw:
            raise RuntimeError("Remote Akida install status file is empty")
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Remote Akida install status is not valid JSON: {raw}"
            ) from exc
        if not isinstance(decoded, dict):
            raise RuntimeError("Remote Akida install status must decode to an object")
        return decoded

    def _read_remote_akida_token(
        self,
        host: dict[str, Any],
        *,
        install_status: dict[str, Any] | None = None,
    ) -> str:
        token_path = str(
            host.get("tokenPath")
            or _load_neurochip_launcher_runtime_contract().akida.token_path_for(
                str(host["remoteInstallRoot"])
            )
        ).strip()
        install_mode = str(
            (install_status or host.get("lastInstallStatus") or {}).get("installMode")
            or ""
        ).strip()
        username = str(host.get("username") or "").strip()
        service_user = str(host.get("serviceUser") or "").strip()
        command = f"cat {shlex.quote(token_path)}"
        display_command = command
        if install_mode != "user-space" and service_user and service_user != username:
            if (
                str(host.get("authMode") or "").strip() == "password"
                and str(host.get("password") or "")
            ):
                password = str(host.get("password") or "")
                command = (
                    f"printf '%s\\n' {shlex.quote(password)} "
                    f"| sudo -S -p '' {command}"
                )
                display_command = (
                    "printf '%s\\n' <redacted> "
                    f"| sudo -S -p '' cat {shlex.quote(token_path)}"
                )
            else:
                command = f"sudo {command}"
                display_command = command
        return self._run_akida_ssh(
            host,
            command,
            display_command=display_command,
        ).strip()

    def _apply_preflight_to_akida_host(
        self,
        host_id: str,
        preflight: dict[str, Any],
        *,
        runtime_status: dict[str, Any] | None = None,
        install_status: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        status = str(preflight.get("preflight_status") or "").strip().lower()
        message = str(preflight.get("preflight_message") or "").strip()
        runtime_target = str(preflight.get("runtime_target") or "").strip()
        sdk_status = str(preflight.get("sdk_status") or "").strip()
        if status == PREFLIGHT_DEGRADED and runtime_status is not None:
            if _akida_hardware_runtime_ready(runtime_status):
                status = PREFLIGHT_OK
                message = "Akida hardware runtime is ready."
                runtime_target = str(runtime_status.get("runtime_target") or "").strip()
                sdk_status = str(runtime_status.get("sdk_status") or "").strip()
        state = "preflight_failed"
        if status == PREFLIGHT_OK:
            state = "ready" if runtime_target == "hardware" else "degraded_optional_capability"
        elif status == PREFLIGHT_DEGRADED:
            state = (
                "simulator_only"
                if runtime_target in {"software_fallback", "akd1000_simulator"}
                else "degraded_optional_capability"
            )
        install_mode = str((install_status or {}).get("installMode") or "").strip()
        if install_mode == "user-space":
            message = " ".join(
                part
                for part in (
                    message,
                    _akida_user_space_upgrade_message(
                        str(self._get_akida_host(host_id).get("username") or "")
                    ),
                )
                if part
            )
            if state == "ready":
                state = "degraded_optional_capability"
        return self._update_akida_host_fields(
            host_id,
            state=state,
            lastPreflightStatus=status,
            lastPreflightMessage=message,
            lastSdkStatus=sdk_status,
            lastRuntimeTarget=runtime_target,
            lastStatus=runtime_status,
            lastInstallStatus=install_status,
            lastReadinessMessage=message,
            lastVerifiedAt=datetime.now(timezone.utc).isoformat(),
        )

    def provision_akida_host(self, host_id: str) -> dict[str, Any]:
        host = self._update_akida_host_fields(
            host_id,
            state="bootstrapping",
            lastReadinessMessage="Starting blank-host bootstrap.",
        )
        install_status: dict[str, Any] = {}
        try:
            with tempfile.TemporaryDirectory(prefix="akida-host-bundle-") as tmp_dir:
                bundle_dir = Path(tmp_dir) / "bundle"
                bundle_dir.mkdir(parents=True, exist_ok=True)
                self._emit_akida_terminal_log(host, "building local Akida host bundle")
                self._build_local_akida_bundle(host, bundle_dir)
                remote_bundle_parent = "/tmp"
                remote_bundle_dir = f"{remote_bundle_parent}/{bundle_dir.name}"
                self._run_akida_ssh(
                    host,
                    f"rm -rf {remote_bundle_dir}",
                )
                self._emit_akida_terminal_log(host, "uploading provisioning bundle")
                self._run_akida_scp(host, bundle_dir, remote_bundle_parent, recursive=True)
                host = self._update_akida_host_fields(
                    host_id,
                    state="installing_runtime",
                    lastReadinessMessage="Running remote install script.",
                )
                self._emit_akida_terminal_log(host, "running remote install script")
                install_command = " ".join(
                    [
                        f"INSTALL_ROOT={shlex.quote(str(host['remoteInstallRoot']))}",
                        f"SERVICE_USER={shlex.quote(str(host['serviceUser']))}",
                        f"VENV_PATH={shlex.quote(str(host['remoteVenvPath']))}",
                        f"RUNTIME_SERVICE_NAME={shlex.quote(str(host['runtimeServiceName']))}",
                        f"CONTROL_SERVICE_NAME={shlex.quote(str(host['controlServiceName']))}",
                        f"RUNTIME_PORT={shlex.quote(str(host['port']))}",
                        f"CONTROL_PORT={shlex.quote(str(host['controlPort']))}",
                        f"TOKEN_PATH={shlex.quote(str(host['tokenPath']))}",
                        f"bash {shlex.quote(remote_bundle_dir)}/install-akida-host.sh",
                    ]
                )
                install_command, display_install_command = (
                    self._akida_remote_command_with_sudo_password(
                        host,
                        install_command,
                    )
                )
                install_output = self._run_akida_ssh(
                    host,
                    install_command,
                    display_command=display_install_command,
                )
                install_status = _extract_install_status_from_output(install_output) or {}
                if not install_status:
                    install_status = self._read_remote_akida_install_status(host)
                host = self._update_akida_host_fields(
                    host_id,
                    remoteInstallRoot=str(
                        install_status.get("installRoot") or host["remoteInstallRoot"]
                    ).strip(),
                    remoteVenvPath=str(
                        install_status.get("venvPath") or host["remoteVenvPath"]
                    ).strip(),
                    serviceUser=str(
                        install_status.get("serviceUser") or host["serviceUser"]
                    ).strip(),
                    tokenPath=str(
                        install_status.get("tokenPath") or host["tokenPath"]
                    ).strip(),
                    installStatusPath=str(
                        install_status.get("installStatusPath")
                        or host["installStatusPath"]
                    ).strip(),
                    lastInstallStatus=install_status,
                )
                token_value = self._read_remote_akida_token(
                    host,
                    install_status=install_status,
                )
                if not token_value:
                    raise RuntimeError("Remote Akida API token read returned an empty value")
                host = self._update_akida_host_fields(
                    host_id,
                    credentialRef=token_value,
                    runtimeApiUrl=_default_akida_base_url(
                        str(host["host"]), int(host["port"])
                    ),
                    controlApiUrl=_default_akida_control_url(
                        str(host["host"]), int(host["controlPort"])
                    ),
                    hostOs=str(install_status.get("hostOs") or "").strip(),
                    pythonVersion=str(install_status.get("pythonVersion") or "").strip(),
                    state="verifying_sdk",
                    lastInstallStatus=install_status,
                    lastReadinessMessage="Remote install completed; verifying SDK and hardware.",
                )
            result = self.fetch_akida_host_preflight(host_id)
            result["installStatus"] = install_status
            return result
        except Exception as exc:  # noqa: BLE001
            self._emit_akida_terminal_log(
                host, f"runtime provisioning failed: {exc}", stderr=True
            )
            updated = self._update_akida_host_fields(
                host_id,
                state="provision_failed",
                lastPreflightMessage=str(exc),
                lastReadinessMessage=str(exc),
                lastInstallStatus=install_status if install_status else None,
            )
            return {
                "host": _serialize_akida_host(updated),
                "error": str(exc),
                "installStatus": install_status if install_status else None,
            }

    def repair_akida_host(self, host_id: str) -> dict[str, Any]:
        return self.provision_akida_host(host_id)

    def restart_akida_host_services(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        install_status = self._read_remote_akida_install_status(host)
        install_mode = (
            str(install_status.get("installMode") or "unknown").strip() or "unknown"
        )
        if install_mode == "user-space":
            message = _akida_user_space_upgrade_message(str(host.get("username") or ""))
            updated = self._update_akida_host_fields(
                host_id,
                state="degraded_optional_capability",
                lastPreflightStatus=PREFLIGHT_DEGRADED,
                lastPreflightMessage=message,
            )
            self._emit_akida_terminal_log(host, message)
            return {
                "host": _serialize_akida_host(updated),
                "warning": message,
                "installStatus": install_status,
            }
        self._emit_akida_terminal_log(host, "restarting remote Akida services")
        self._run_akida_ssh(
            host,
            (
                f"sudo systemctl restart {host['runtimeServiceName']}.service "
                f"{host['controlServiceName']}.service"
            ),
        )
        result = self.fetch_akida_host_preflight(host_id)
        result["installStatus"] = install_status
        return result

    def fetch_akida_host_preflight(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "requesting runtime preflight")
        verification: dict[str, Any] = {}
        runtime_status: dict[str, Any] | None = None
        install_status: dict[str, Any] | None = None
        try:
            if _resolved_akida_control_api_url(host):
                try:
                    doctor = self._akida_control_json_request(
                        host,
                        "GET",
                        "/api/remote-akida/doctor",
                        emit_terminal_errors=False,
                    )
                    preflight = doctor.get("preflight")
                    if isinstance(preflight, dict):
                        verification = preflight
                    runtime_status = (
                        doctor.get("runtimeStatus")
                        if isinstance(doctor.get("runtimeStatus"), dict)
                        else None
                    )
                    install_status = (
                        doctor.get("installStatus")
                        if isinstance(doctor.get("installStatus"), dict)
                        else None
                    )
                except Exception as control_exc:  # noqa: BLE001
                    self._emit_akida_terminal_log(
                        host,
                        (
                            "remote control API unavailable during preflight; "
                            f"falling back to runtime status: {control_exc}"
                        ),
                        stderr=True,
                    )
                    verification = self._akida_json_request(
                        host, "GET", "/api/neurochip/akida/status"
                    )
                    runtime_status = verification
            else:
                verification = self._akida_json_request(
                    host, "GET", "/api/neurochip/akida/status"
                )
                runtime_status = verification
        except Exception as exc:  # noqa: BLE001
            verification = {
                "preflight_status": PREFLIGHT_FAILED,
                "preflight_message": str(exc),
                "sdk_status": "",
                "runtime_target": "",
                "sdk_available": False,
                "sdk_issues": [],
                "sdk_issue_detail": str(exc),
                "environment_checks": None,
            }
        if "preflight_status" not in verification:
            preflight_status = _preflight_status_for_akida_verification(verification)
            verification = {
                "preflight_status": preflight_status,
                "preflight_message": _describe_akida_preflight(verification),
                "sdk_status": str(verification.get("sdk_status") or "").strip(),
                "runtime_target": str(verification.get("runtime_target") or "").strip(),
                "sdk_available": bool(verification.get("sdk_available")),
                "sdk_issues": verification.get("sdk_issues")
                if isinstance(verification.get("sdk_issues"), list)
                else [],
                "sdk_issue_detail": str(verification.get("sdk_issue_detail") or "").strip(),
                "environment_checks": verification.get("environment_checks")
                if isinstance(verification.get("environment_checks"), dict)
                else None,
                "sdk_verification": verification,
            }
        self._emit_akida_terminal_log(
            host,
            f"preflight {verification.get('preflight_status')}: {verification.get('preflight_message')}",
        )
        updated = self._apply_preflight_to_akida_host(
            host_id,
            verification,
            runtime_status=runtime_status,
            install_status=install_status,
        )
        if str(updated.get("hostOs") or "").strip() == "" and install_status:
            updated = self._update_akida_host_fields(
                host_id,
                hostOs=str(install_status.get("hostOs") or "").strip(),
                pythonVersion=str(install_status.get("pythonVersion") or "").strip(),
            )
        return {
            "host": _serialize_akida_host(updated),
            "preflight": verification,
            "status": runtime_status,
            "installStatus": install_status,
        }

    def fetch_akida_host_status(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "requesting runtime status")
        if _resolved_akida_control_api_url(host):
            try:
                doctor = self._akida_control_json_request(
                    host,
                    "GET",
                    "/api/remote-akida/doctor",
                    emit_terminal_errors=False,
                )
                runtime_status = (
                    doctor.get("runtimeStatus")
                    if isinstance(doctor.get("runtimeStatus"), dict)
                    else {}
                )
                preflight = (
                    doctor.get("preflight")
                    if isinstance(doctor.get("preflight"), dict)
                    else {}
                )
                updated = self._apply_preflight_to_akida_host(
                    host_id,
                    preflight,
                    runtime_status=runtime_status,
                    install_status=doctor.get("installStatus")
                    if isinstance(doctor.get("installStatus"), dict)
                    else None,
                )
                return {"host": _serialize_akida_host(updated), "status": runtime_status}
            except Exception as control_exc:  # noqa: BLE001
                self._emit_akida_terminal_log(
                    host,
                    (
                        "remote control API unavailable during status poll; "
                        f"falling back to runtime status: {control_exc}"
                    ),
                    stderr=True,
                )
        status = self._akida_json_request(host, "GET", "/api/neurochip/akida/status")
        updated = self._update_akida_host_fields(
            host_id,
            state=_akida_host_state_for_status(host, status),
            lastStatus=status,
        )
        return {"host": _serialize_akida_host(updated), "status": status}

    def update_module_settings(
        self, module_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if "isEnabled" in payload:
                module["isEnabled"] = bool(payload["isEnabled"])
            if "customPort" in payload:
                custom_port = payload["customPort"]
                module["customPort"] = (
                    custom_port if isinstance(custom_port, int) else None
                )
            if "versionPinned" in payload:
                module["versionPinned"] = bool(payload["versionPinned"])
                if module["versionPinned"]:
                    module["remoteVersion"] = str(module.get("version", "0.0.0"))
            if "startOnLaunch" in payload:
                module["startOnLaunch"] = bool(payload["startOnLaunch"])
            self._persist_states()
            return self._serialize_module(module)

    def install_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["installing"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._install_sync(module_id))
            return self._serialize_module(module)

    def update_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            current_version = str(module.get("version", "0.0.0"))
            remote_version = str(module.get("remoteVersion", current_version))
            if bool(module.get("versionPinned", False)) or not _is_newer_version(
                current_version,
                remote_version,
            ):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["updating"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._update_sync(module_id))
            return self._serialize_module(module)

    def prepare_akida_runtime(self, module_id: str) -> dict[str, Any]:
        module = self._get_module(module_id)
        runtime = _normalize_akida_runtime_config(module.get("akidaRuntime"))
        if runtime is None:
            raise RuntimeError(f"Module '{module_id}' does not define an Akida runtime profile")

        preflight = self._preflight_module(module, allow_repair=False)
        self._update_module_fields(module_id, **preflight.state_fields())
        if preflight.status == PREFLIGHT_FAILED:
            self._update_module_fields(
                module_id,
                akidaRuntimeState={
                    "status": "error",
                    "message": preflight.message or "Module preflight failed",
                    "preparedAt": None,
                },
            )
            return self.serialize_module(module_id)

        platform_key = _current_platform_key()
        if platform_key not in runtime["supportedPlatforms"]:
            self._update_module_fields(
                module_id,
                akidaRuntimeState={
                    "status": "unsupported_host",
                    "message": (
                        "Local Akida SDK install is not supported on this host. "
                        "Use the local simulator and a Linux or Windows Neurochip "
                        "host for SDK verification."
                    ),
                    "preparedAt": None,
                },
            )
            return self.serialize_module(module_id)

        install_dir = _module_install_dir(module)
        python_path = _module_python_path(module)
        python_version_result = self._run_command(
            [
                str(python_path),
                "-c",
                'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")',
            ],
            cwd=install_dir,
            module_id=module_id,
        )
        python_version = str(python_version_result.stdout or "").strip()
        if not _version_matches_range(python_version, runtime["pythonRange"]):
            self._update_module_fields(
                module_id,
                akidaRuntimeState={
                    "status": "unsupported_python",
                    "message": (
                        "Akida SDK installation requires Python "
                        f"{runtime['pythonRange']}; current module env is "
                        f"{python_version or 'unknown'}. Keep scaffold export "
                        "local, then verify through a Linux or Windows "
                        "Neurochip host running Python 3.10-3.12."
                    ),
                    "preparedAt": None,
                },
            )
            return self.serialize_module(module_id)

        self._update_module_fields(
            module_id,
            akidaRuntimeState={
                "status": "preparing",
                "message": "Installing Akida runtime dependencies...",
                "preparedAt": None,
            },
        )

        if _module_uses_poetry(module) and (poetry := _poetry_command()) is not None:
            command = [
                poetry,
                "run",
                "python",
                "-m",
                "pip",
                "install",
                *runtime["requiredPackages"],
            ]
        else:
            command = [
                str(python_path),
                "-m",
                "pip",
                "install",
                *runtime["requiredPackages"],
            ]
        self._run_command(command, cwd=install_dir, module_id=module_id)

        self._update_module_fields(
            module_id,
            akidaRuntimeState={
                "status": "ready",
                "message": "Akida runtime is prepared for local SDK verification.",
                "preparedAt": datetime.now(timezone.utc).isoformat(),
            },
        )
        return self.serialize_module(module_id)

    def start_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["starting"]
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._start_sync(module_id))
            return self._serialize_module(module)

    def stop_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            module["status"] = STATUS_INDEX["stopping"]
            self._persist_states()
        try:
            self._stop_process(module_id)
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["installed"],
                healthStatus=None,
                installProgress=1.0,
            )
        except Exception as exc:  # noqa: BLE001
            self._set_error(module_id, f"Stop failed: {exc}")
        return self.serialize_module(module_id)

    def uninstall_module(self, module_id: str) -> dict[str, Any]:
        self.stop_module(module_id)
        self._cleanup_module_environment(module_id)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["notInstalled"],
            installProgress=0.0,
            healthStatus=None,
            preflightStatus=PREFLIGHT_OK,
            preflightMessage=None,
            capabilityWarnings=[],
            environmentFingerprint=None,
        )
        return self.serialize_module(module_id)

    def get_logs(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            managed = self._processes.get(module_id)
            lines = managed.logs if managed is not None else self._logs[module_id]
            return {"moduleId": module_id, "lines": list(lines)}

    def _task_running(self, module_id: str) -> bool:
        task = self._tasks.get(module_id)
        return task is not None and task.is_alive()

    def _spawn_task(self, module_id: str, target: Callable[[], None]) -> None:
        thread = threading.Thread(
            target=self._run_task, args=(module_id, target), daemon=True
        )
        self._tasks[module_id] = thread
        thread.start()

    def _run_task(self, module_id: str, target: Callable[[], None]) -> None:
        try:
            target()
        except Exception as exc:  # noqa: BLE001
            self._set_error(module_id, str(exc))
        finally:
            with self._lock:
                self._tasks.pop(module_id, None)

    def _module_python_version(self, python_path: Path) -> str:
        result = subprocess.run(
            [str(python_path), "--version"],
            capture_output=True,
            text=True,
            check=False,
        )
        version = (result.stdout or result.stderr).strip()
        if result.returncode != 0 or not version:
            raise RuntimeError(
                result.stderr.strip()
                or f"Failed to inspect Python version at {python_path}"
            )
        return version

    def _compute_environment_fingerprint(self, module: dict[str, Any]) -> str:
        python_path = _module_python_path(module)
        if not python_path.exists():
            raise RuntimeError(_missing_python_message(module, python_path))

        payload = {
            "pythonVersion": self._module_python_version(python_path),
            "pythonPath": str(python_path),
            "installDir": str(_module_install_dir(module)),
            "runDir": str(_module_run_dir(module)),
            "installStrategy": _module_install_strategy(module),
            "installExtras": _module_install_extras(module),
            "startStrategy": _module_start_strategy(module),
            "uvicornTarget": str(module.get("uvicornTarget", "")),
            "files": {
                str(path.relative_to(REPO_ROOT)): _hash_file(path)
                for path in _candidate_environment_files(module)
            },
        }
        return hashlib.sha256(
            json.dumps(payload, sort_keys=True).encode("utf-8")
        ).hexdigest()

    def _cleanup_module_environment(self, module_id: str) -> None:
        with self._lock:
            module = dict(self._get_module(module_id))

        install_dir = _module_install_dir(module)
        for venv_name in (".venv", "venv"):
            venv_path = install_dir / venv_name
            if venv_path.exists():
                shutil.rmtree(venv_path, ignore_errors=True)

        if not _module_uses_poetry(module):
            return

        poetry_toml = install_dir / "poetry.toml"
        if poetry_toml.exists():
            try:
                poetry_toml.unlink()
            except OSError:
                pass

        fallback_env_root = _poetry_fallback_env_root(module)
        if fallback_env_root.exists():
            shutil.rmtree(fallback_env_root, ignore_errors=True)

        poetry = _poetry_command()
        if poetry is None:
            return

        try:
            subprocess.run(
                [poetry, "env", "remove", "--all"],
                cwd=install_dir,
                capture_output=True,
                text=True,
                check=False,
            )
        except Exception:
            pass

    def _run_import_probe(self, module: dict[str, Any]) -> PreflightResult:
        python_path = _module_python_path(module)
        if not python_path.exists():
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=_missing_python_message(module, python_path),
            )

        required_imports = _module_required_imports(module)
        optional_imports = _module_optional_imports(module)
        result = subprocess.run(
            [
                str(python_path),
                "-c",
                IMPORT_PROBE_SCRIPT,
                json.dumps(required_imports),
                json.dumps(optional_imports),
            ],
            cwd=_module_run_dir(module),
            capture_output=True,
            text=True,
            check=False,
        )
        if result.stderr:
            self._append_log(
                module["id"], result.stderr, stderr=True, emit_terminal=True
            )
        if result.stdout:
            for line in result.stdout.splitlines():
                if not line.startswith(PREFLIGHT_SENTINEL):
                    self._append_log(module["id"], line, emit_terminal=True)

        sentinel_line = next(
            (
                line
                for line in result.stdout.splitlines()
                if line.startswith(PREFLIGHT_SENTINEL)
            ),
            "",
        )
        if result.returncode != 0 or not sentinel_line:
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=(
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "Preflight import probe failed"
                ),
            )

        payload = json.loads(sentinel_line.removeprefix(PREFLIGHT_SENTINEL))
        required_failures = [
            outcome for outcome in payload.get("required", []) if not outcome.get("ok")
        ]
        capability_warnings = _dedupe_messages(
            [
                _message_from_probe_outcome(outcome, optional=True)
                for outcome in payload.get("optional", [])
                if not outcome.get("ok")
            ]
        )

        if required_failures:
            failure_messages = _dedupe_messages(
                [
                    _message_from_probe_outcome(outcome, optional=False)
                    for outcome in required_failures
                ]
            )
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message="; ".join(failure_messages),
                capability_warnings=capability_warnings,
            )

        if capability_warnings:
            return PreflightResult(
                status=PREFLIGHT_DEGRADED,
                message=capability_warnings[0],
                capability_warnings=capability_warnings,
            )

        return PreflightResult(status=PREFLIGHT_OK)

    def _preflight_module(
        self, module: dict[str, Any], *, allow_repair: bool
    ) -> PreflightResult:
        module_id = str(module["id"])
        install_dir = _module_install_dir(module)
        run_dir = _module_run_dir(module)

        if not install_dir.exists():
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=f"Module directory not found: {install_dir}",
            )
        if not run_dir.exists():
            return PreflightResult(
                status=PREFLIGHT_FAILED,
                message=f"Run directory not found: {run_dir}",
            )

        python_path = _module_python_path(module)
        if not python_path.exists():
            if not allow_repair:
                return PreflightResult(
                    status=PREFLIGHT_FAILED,
                    message=_missing_python_message(module, python_path),
                )
            if _module_uses_poetry(module):
                self._cleanup_module_environment(module_id)
            self._install_sync(module_id)
            module = self._get_module(module_id)
            python_path = _module_python_path(module)

        fingerprint = self._compute_environment_fingerprint(module)
        saved_fingerprint = str(module.get("environmentFingerprint") or "").strip()
        if saved_fingerprint and saved_fingerprint != fingerprint:
            if (
                _module_uses_poetry(module)
                and str(module.get("preflightStatus", PREFLIGHT_OK)) == PREFLIGHT_FAILED
            ):
                recovered_result = self._run_import_probe(module)
                recovered_result.environment_fingerprint = fingerprint
                if recovered_result.status != PREFLIGHT_FAILED:
                    return recovered_result
            message = (
                "Environment fingerprint changed; reinstall required before launch"
            )
            if not allow_repair:
                return PreflightResult(
                    status=PREFLIGHT_FAILED,
                    message=message,
                    environment_fingerprint=fingerprint,
                )
            self._append_log(module_id, message, emit_terminal=True)
            if _module_uses_poetry(module):
                self._cleanup_module_environment(module_id)
            self._install_sync(module_id)
            module = self._get_module(module_id)
            fingerprint = self._compute_environment_fingerprint(module)

        probe_result = self._run_import_probe(module)
        probe_result.environment_fingerprint = fingerprint
        if probe_result.status != PREFLIGHT_FAILED or not allow_repair:
            return probe_result

        if _module_uses_poetry(module):
            self._append_log(
                module_id,
                "Preflight failed; cleaning and reinstalling once to repair the module environment",
                emit_terminal=True,
            )
            self._cleanup_module_environment(module_id)
        else:
            self._append_log(
                module_id,
                "Preflight failed; reinstalling once to repair the module environment",
                emit_terminal=True,
            )
        self._install_sync(module_id)
        module = self._get_module(module_id)
        repaired_result = self._run_import_probe(module)
        repaired_result.environment_fingerprint = self._compute_environment_fingerprint(
            module
        )
        return repaired_result

    def _install_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        install_dir = _module_install_dir(module)
        if not install_dir.exists():
            raise RuntimeError(f"Module directory not found: {install_dir}")

        install_strategy = _module_install_strategy(module)
        if install_strategy not in SUPPORTED_INSTALL_STRATEGIES:
            raise RuntimeError(
                f"Unsupported install strategy '{install_strategy}' for {module_id}"
            )

        venv_python = _module_venv_python(module)
        poetry = _poetry_command()
        use_poetry = _module_uses_poetry(module) and poetry is not None

        self._update_module_fields(
            module_id, status=STATUS_INDEX["installing"], installProgress=0.1
        )
        if use_poetry:
            # Configure Poetry before any `poetry run ...` command so repairs
            # consistently recreate an in-project `.venv`.
            self._run_command(
                [poetry, "config", "virtualenvs.in-project", "true", "--local"],
                cwd=install_dir,
                module_id=module_id,
            )
        if not use_poetry and not venv_python.exists():
            self._run_command(
                [sys.executable, "-m", "venv", "venv"],
                cwd=install_dir,
                module_id=module_id,
            )
            venv_python = _module_venv_python(module)
        if not use_poetry:
            self._ensure_module_pip(venv_python, install_dir, module_id)

        self._update_module_fields(module_id, installProgress=0.3)
        for dependency in module.get("localDeps", []):
            dep_path = (REPO_ROOT / dependency).resolve()
            if dep_path.exists():
                if use_poetry:
                    self._run_command(
                        [
                            poetry,
                            "run",
                            "python",
                            "-m",
                            "pip",
                            "install",
                            str(dep_path),
                        ],
                        cwd=install_dir,
                        module_id=module_id,
                    )
                else:
                    self._run_command(
                        [str(venv_python), "-m", "pip", "install", str(dep_path)],
                        cwd=install_dir,
                        module_id=module_id,
                    )

        self._update_module_fields(module_id, installProgress=0.6)
        if use_poetry:
            self._run_command(
                [poetry, "lock"],
                cwd=install_dir,
                module_id=module_id,
            )
            self._run_command(
                [poetry, "install", "--no-interaction", "--no-root"],
                cwd=install_dir,
                module_id=module_id,
            )
        else:
            install_extras = _module_install_extras(module)
            install_target = (
                f".[{','.join(install_extras)}]" if install_extras else "."
            )
            self._run_command(
                [str(venv_python), "-m", "pip", "install", install_target],
                cwd=install_dir,
                module_id=module_id,
            )
        environment_fingerprint = self._compute_environment_fingerprint(module)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["installed"],
            installProgress=1.0,
            healthStatus=None,
            preflightStatus=PREFLIGHT_OK,
            preflightMessage=None,
            capabilityWarnings=[],
            environmentFingerprint=environment_fingerprint,
        )

    def _ensure_module_pip(self, python_path: Path, cwd: Path, module_id: str) -> None:
        probe = subprocess.run(
            [str(python_path), "-m", "pip", "--version"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if probe.returncode == 0:
            return

        self._append_log(
            module_id,
            "pip is missing from the module environment; bootstrapping it now",
            emit_terminal=True,
        )
        ensurepip = subprocess.run(
            [str(python_path), "-m", "ensurepip", "--upgrade"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if ensurepip.stdout:
            self._append_log(module_id, ensurepip.stdout, emit_terminal=True)
        if ensurepip.stderr:
            self._append_log(
                module_id, ensurepip.stderr, stderr=True, emit_terminal=True
            )
        if ensurepip.returncode != 0:
            self._append_log(
                module_id,
                "ensurepip unavailable; downloading get-pip.py as a fallback",
                emit_terminal=True,
            )
            with tempfile.NamedTemporaryFile(
                mode="w", suffix="-get-pip.py", delete=False, dir=cwd
            ) as handle:
                temp_path = Path(handle.name)
            try:
                urllib.request.urlretrieve(
                    "https://bootstrap.pypa.io/get-pip.py",
                    temp_path,
                )
                self._run_command(
                    [str(python_path), str(temp_path)],
                    cwd=cwd,
                    module_id=module_id,
                )
            finally:
                try:
                    temp_path.unlink(missing_ok=True)
                except OSError:
                    pass

        final_probe = subprocess.run(
            [str(python_path), "-m", "pip", "--version"],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if final_probe.returncode != 0:
            raise RuntimeError(
                final_probe.stderr.strip()
                or "pip bootstrap failed for the module environment"
            )

    def _update_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        self.stop_module(module_id)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["updating"],
            installProgress=0.2,
            healthStatus=None,
        )
        self._install_sync(module_id)
        with self._lock:
            remote_version = module.get("remoteVersion")
            if isinstance(remote_version, str) and remote_version:
                module["version"] = remote_version
                module["remoteVersion"] = remote_version
                self._persist_states()

    def _start_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        if not module.get("isEnabled", True):
            raise RuntimeError("Module is disabled")

        start_strategy = _module_start_strategy(module)
        if start_strategy == "none":
            suite_api_result = self._suite_api_ready_result()
            self._update_module_fields(module_id, **suite_api_result.state_fields())
            if suite_api_result.status == PREFLIGHT_FAILED:
                self._update_module_fields(
                    module_id,
                    status=STATUS_INDEX["error"],
                    healthStatus=suite_api_result.message,
                )
                raise RuntimeError(suite_api_result.message or "suite_api is unavailable")
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["running"],
                healthStatus="Managed by suite_api",
            )
            return

        preflight = self._preflight_module(module, allow_repair=True)
        self._update_module_fields(module_id, **preflight.state_fields())
        if preflight.status == PREFLIGHT_FAILED:
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["error"],
                healthStatus=preflight.message,
            )
            raise RuntimeError(preflight.message or "Module preflight failed")

        module = self._get_module(module_id)
        if start_strategy not in SUPPORTED_START_STRATEGIES:
            raise RuntimeError(
                f"Unsupported start strategy '{start_strategy}' for {module_id}"
            )

        port = _effective_port(module)
        if port is None:
            raise RuntimeError("Module has no configured port")

        self._kill_process_on_port(port, module_id=module_id)
        run_dir = _module_run_dir(module)
        python_path = _module_python_path(module)
        if not python_path.exists():
            raise RuntimeError(_missing_python_message(module, python_path))

        command = [
            str(python_path),
            "-m",
            "uvicorn",
            str(module.get("uvicornTarget", "app.main:app")),
            "--host",
            _uvicorn_host(),
            "--port",
            str(port),
            "--log-level",
            str(self._settings["logLevel"]),
        ]
        process = subprocess.Popen(
            command,
            cwd=run_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        managed = ManagedProcess(process=process, logs=self._logs[module_id])
        with self._lock:
            self._processes[module_id] = managed
            self._persist_states()
        self._stream_logs(module_id, managed)
        self._watch_process_exit(module_id, managed)

        deadline = time.monotonic() + STARTUP_GRACE_SECONDS
        while time.monotonic() < deadline:
            ok, status_code, health_text = self._probe_health(module)
            if ok:
                next_status = _status_for_health_response(status_code, preflight.status)
                self._update_module_fields(
                    module_id,
                    status=next_status,
                    installProgress=1.0,
                    healthStatus=health_text,
                )
                return
            if process.poll() is not None:
                raise RuntimeError(f"Process exited with code {process.returncode}")
            time.sleep(0.5)

        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus="Timed out waiting for /health",
        )

    def _stream_logs(self, module_id: str, managed: ManagedProcess) -> None:
        def _pump(stream: Any, *, stderr: bool = False) -> None:
            if stream is None:
                return
            for line in stream:
                self._append_log(module_id, line, stderr=stderr, emit_terminal=True)

        if managed.process.stdout is not None:
            threading.Thread(
                target=_pump,
                args=(managed.process.stdout,),
                daemon=True,
                name=f"{module_id}-stdout",
            ).start()
        if managed.process.stderr is not None:
            threading.Thread(
                target=_pump,
                args=(managed.process.stderr,),
                kwargs={"stderr": True},
                daemon=True,
                name=f"{module_id}-stderr",
            ).start()

    def _watch_process_exit(self, module_id: str, managed: ManagedProcess) -> None:
        def _watch() -> None:
            return_code = managed.process.wait()
            with self._lock:
                current = self._processes.get(module_id)
                if current is managed:
                    self._processes.pop(module_id, None)
            if self._shutdown.is_set():
                return
            if self.serialize_module(module_id)["status"] == STATUS_INDEX["stopping"]:
                return
            self._set_error(module_id, f"Process exited with code {return_code}")

        threading.Thread(
            target=_watch,
            daemon=True,
            name=f"{module_id}-exit-watch",
        ).start()

    def _stop_process(self, module_id: str) -> None:
        with self._lock:
            managed = self._processes.pop(module_id, None)
        if managed is None:
            return
        managed.process.terminate()
        try:
            managed.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            managed.process.kill()
            managed.process.wait(timeout=5)

    def _probe_health(self, module: dict[str, Any]) -> tuple[bool, int, str | None]:
        port = _effective_port(module)
        if port is None:
            return False, 0, None

        start_strategy = _module_start_strategy(module)
        if start_strategy == "none":
            # Native feature modules in the monolith have their own health path
            # All mounted domain prefixes in suite_api are lowercase.
            url = f"http://127.0.0.1:{port}/api/{module['id'].lower()}/health"
        else:
            url = f"http://127.0.0.1:{port}/health"
        try:
            with urllib.request.urlopen(url, timeout=2.0) as response:
                body = response.read().decode("utf-8", errors="replace")
                return True, int(response.status), body
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            if exc.code in (HTTPStatus.NOT_FOUND, HTTPStatus.SERVICE_UNAVAILABLE):
                return True, int(exc.code), body
            return False, int(exc.code), body
        except (urllib.error.URLError, TimeoutError, socket.timeout):
            return False, 0, None

    def _health_poll_loop(self) -> None:
        while not self._shutdown.wait(HEALTH_POLL_SECONDS):
            if self._manage_suite_api:
                ok, message = _suite_api_health_probe()
                if ok:
                    self._set_suite_api_state(
                        SUITE_API_STATUS_READY, "Managed by suite_api"
                    )
                elif self._suite_api_status == SUITE_API_STATUS_READY:
                    self._set_suite_api_state(
                        SUITE_API_STATUS_PREFLIGHT_FAILED,
                        message or "suite_api health probe failed",
                    )
            with self._lock:
                module_ids = list(self._processes.keys())
            for module_id in module_ids:
                with self._lock:
                    module = dict(self._get_module(module_id))
                ok, status_code, health_text = self._probe_health(module)
                if ok:
                    next_status = _status_for_health_response(
                        status_code,
                        str(module.get("preflightStatus", PREFLIGHT_OK)),
                    )
                    self._update_module_fields(
                        module_id,
                        status=next_status,
                        healthStatus=health_text
                        if health_text
                        else (
                            "No /health endpoint (server is up)"
                            if status_code == 404
                            else None
                        ),
                    )
                elif module_id in self._processes:
                    self._update_module_fields(
                        module_id,
                        status=STATUS_INDEX["error"],
                        healthStatus="Health probe failed",
                    )

    def _run_command(self, command: list[str], cwd: Path, module_id: str) -> None:
        result = subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.stdout:
            self._append_log(module_id, result.stdout, emit_terminal=True)
        if result.stderr:
            self._append_log(module_id, result.stderr, stderr=True, emit_terminal=True)
        if result.returncode != 0:
            raise RuntimeError(
                result.stderr.strip() or f"Command failed: {' '.join(command)}"
            )

    def _append_log(
        self,
        module_id: str,
        text: str,
        *,
        stderr: bool = False,
        emit_terminal: bool = False,
    ) -> None:
        terminal_lines: list[str] = []
        with self._lock:
            lines = self._logs[module_id]
            managed = self._processes.get(module_id)
            for line in text.splitlines():
                if line.strip():
                    clean_line = line.rstrip()
                    stored_line = f"[stderr] {clean_line}" if stderr else clean_line
                    lines.append(stored_line)
                    if managed is not None and managed.logs is not lines:
                        managed.logs.append(stored_line)
                    if emit_terminal:
                        terminal_lines.append(clean_line)

        if emit_terminal:
            for line in terminal_lines:
                self._emit_terminal_log(module_id, line, stderr=stderr)

    def _emit_terminal_log(
        self, module_id: str, line: str, *, stderr: bool = False
    ) -> None:
        stream = sys.stderr if stderr else sys.stdout
        with self._terminal_lock:
            print(f"[{module_id}] {line}", file=stream, flush=True)

    def _kill_process_on_port(self, port: int, module_id: str) -> None:
        if os.name == "nt":
            return
        result = subprocess.run(
            ["lsof", "-ti", f":{port}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return
        for pid_text in result.stdout.splitlines():
            pid_text = pid_text.strip()
            if not pid_text:
                continue
            try:
                os.kill(int(pid_text), 9)
                self._append_log(
                    module_id, f"Killed stale process {pid_text} on port {port}"
                )
            except OSError:
                continue

    def doctor_report(self) -> dict[str, Any]:
        modules: list[dict[str, Any]] = []
        akida_hosts: list[dict[str, Any]] = []
        pynq_boards: list[dict[str, Any]] = []
        akida_hosts: list[dict[str, Any]] = []
        global_checks = _global_preflight_checks()
        fatal_count = 0
        degraded_count = 0
        ok_count = 0

        for check in global_checks:
            status = str(check.get("preflightStatus", PREFLIGHT_OK))
            if status == PREFLIGHT_FAILED:
                fatal_count += 1
            elif status == PREFLIGHT_DEGRADED:
                degraded_count += 1
            else:
                ok_count += 1

        with self._lock:
            snapshot = [dict(module) for module in self._modules.values()]

        for module in snapshot:
            if not module.get("isEnabled", True):
                result = PreflightResult(
                    status=PREFLIGHT_OK,
                    message="Module disabled",
                )
            elif (
                int(module.get("status", STATUS_INDEX["notInstalled"]))
                == STATUS_INDEX["notInstalled"]
            ):
                result = PreflightResult(
                    status=PREFLIGHT_OK,
                    message="Module not installed",
                )
            elif _module_start_strategy(module) == "none":
                result = self._suite_api_ready_result()
            else:
                result = self._preflight_module(module, allow_repair=False)

            if result.status == PREFLIGHT_FAILED:
                fatal_count += 1
            elif result.status == PREFLIGHT_DEGRADED:
                degraded_count += 1
            else:
                ok_count += 1

            modules.append(
                {
                    "id": module["id"],
                    "name": module["name"],
                    "status": _status_name(int(module.get("status", 0))),
                    "preflightStatus": result.status,
                    "preflightMessage": result.message,
                    "capabilityWarnings": list(result.capability_warnings),
                    "environmentFingerprint": result.environment_fingerprint,
                    "effectivePort": _effective_port(module),
                }
            )

        with self._lock:
            akida_host_snapshot = [
                dict(host) for host in self._settings.get("akidaHosts", [])
            ]
            board_snapshot = [
                dict(board) for board in self._settings.get("pynqBoards", [])
            ]

        for host in akida_host_snapshot:
            state = _normalize_akida_host_state(
                host.get("state"),
                _load_neurochip_launcher_runtime_contract().akida.default_state,
            )
            if state == "ready":
                ok_count += 1
            elif state in {
                "degraded_optional_capability",
                "degraded",
                "simulator_only",
                "reachable",
                "bootstrapping",
                "installing_runtime",
                "verifying_sdk",
                "unpaired",
            }:
                degraded_count += 1
            elif state in {"preflight_failed", "blocked", "error", "provision_failed"}:
                fatal_count += 1

            akida_hosts.append(
                {
                    "id": host["id"],
                    "displayName": host["displayName"],
                    "host": str(
                        host.get("host")
                        or urlparse(_resolved_akida_base_url(host)).hostname
                        or ""
                    ),
                    "baseUrl": _resolved_akida_base_url(host),
                    "controlApiUrl": _resolved_akida_control_api_url(host),
                    "runtimeApiUrl": str(
                        host.get("runtimeApiUrl") or _resolved_akida_base_url(host)
                    ).strip(),
                    "sshPort": int(
                        host.get("sshPort")
                        or _load_neurochip_launcher_runtime_contract().akida.ssh_port
                    ),
                    "username": str(host.get("username") or "").strip(),
                    "runtimeMode": _normalize_akida_runtime_mode(
                        host.get("runtimeMode")
                    ),
                    "state": state,
                    "hostOs": str(host.get("hostOs") or "").strip(),
                    "pythonVersion": str(host.get("pythonVersion") or "").strip(),
                    "lastPreflightStatus": host.get("lastPreflightStatus"),
                    "lastPreflightMessage": host.get("lastPreflightMessage"),
                    "lastSdkStatus": host.get("lastSdkStatus"),
                    "lastRuntimeTarget": host.get("lastRuntimeTarget"),
                    "lastReadinessMessage": str(
                        host.get("lastReadinessMessage") or ""
                    ).strip(),
                }
            )

        for board in board_snapshot:
            state = _normalize_pynq_board_state(
                board.get("state"),
                _load_neurochip_launcher_runtime_contract().pynq.default_state,
            )
            if state == "ready":
                ok_count += 1
            elif state == "degraded_optional_capability":
                degraded_count += 1
            elif state in {"provision_failed", "overlay_missing", "preflight_failed", "error"}:
                fatal_count += 1

            pynq_boards.append(
                {
                    "id": board["id"],
                    "displayName": board["displayName"],
                    "host": board["host"],
                    "state": state,
                    "lastPreflightStatus": board.get("lastPreflightStatus"),
                    "lastPreflightMessage": board.get("lastPreflightMessage"),
                    "runtimeApiUrl": _resolved_pynq_runtime_api_url(board),
                    "runtimeApiUrlOverride": str(
                        board.get("runtimeApiUrlOverride") or ""
                    ).strip(),
                }
            )

        return {
            "status": "ok" if fatal_count == 0 else "error",
            "fatalCount": fatal_count,
            "degradedCount": degraded_count,
            "okCount": ok_count,
            "globalChecks": global_checks,
            "modules": modules,
            "backendDeployment": {
                "ready": self._deployment.is_ready(),
                "selectedTarget": self._deployment.selected_target(),
                "targetCount": len(self._deployment.list_targets()),
            },
            "akidaHosts": akida_hosts,
            "pynqBoards": pynq_boards,
        }

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

    def _set_error(self, module_id: str, message: str) -> None:
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus=message,
        )

    def _get_module(self, module_id: str) -> dict[str, Any]:
        try:
            return self._modules[module_id]
        except KeyError as exc:
            raise KeyError(f"Unknown module '{module_id}'") from exc

    def _update_module_fields(self, module_id: str, **fields: Any) -> None:
        with self._lock:
            module = self._get_module(module_id)
            for key, value in fields.items():
                module[key] = value
            self._persist_states()

    def _persist_states(self) -> None:
        payload = {
            module_id: {
                "id": module["id"],
                "version": module.get("version", "0.0.0"),
                "remoteVersion": module.get("remoteVersion", "0.0.0"),
                "versionPinned": bool(module.get("versionPinned", False)),
                "isEnabled": bool(module.get("isEnabled", True)),
                "customPort": module.get("customPort"),
                "startOnLaunch": bool(module.get("startOnLaunch", False)),
                "status": module.get("status", STATUS_INDEX["notInstalled"]),
                "installProgress": float(module.get("installProgress", 0.0)),
                "healthStatus": module.get("healthStatus"),
                "preflightStatus": module.get("preflightStatus", PREFLIGHT_OK),
                "preflightMessage": module.get("preflightMessage"),
                "capabilityWarnings": list(module.get("capabilityWarnings", [])),
                "environmentFingerprint": module.get("environmentFingerprint"),
                "directory": module["directory"],
                "port": module.get("port"),
                "hasFrontend": bool(module.get("hasFrontend", False)),
                "showInLauncherNav": bool(module.get("showInLauncherNav", True)),
                "frontendStatus": module.get("frontendStatus", "No"),
                "requiresMuJoCo": bool(module.get("requiresMuJoCo", False)),
                "sourcePath": module.get("sourcePath", "."),
                "runPath": module.get("runPath", "."),
                "uvicornTarget": module.get("uvicornTarget", "app.main:app"),
                "requiredImports": list(module.get("requiredImports", [])),
                "optionalImports": list(module.get("optionalImports", [])),
                "installExtras": list(module.get("installExtras", [])),
                "installStrategy": module.get("installStrategy", "pip"),
                "startStrategy": module.get("startStrategy", "uvicorn"),
                "akidaRuntimeState": _normalize_akida_runtime_state(
                    module.get("akidaRuntimeState")
                ),
            }
            for module_id, module in self._modules.items()
        }
        _write_json_file(STATE_FILE, payload)


class LauncherControlHandler(BaseHTTPRequestHandler):
    """HTTP adapter exposing launcher control state over a JSON API."""

    server: "LauncherControlServer"

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._send_json(HTTPStatus.NO_CONTENT, {})

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch("PUT")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)
        body = self._read_body()
        try:
            if method == "GET" and path == "/health":
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                        **self.server.state.get_settings(),
                    },
                )
                return

            if method == "GET" and path == "/api/launcher/modules":
                refresh_updates = query.get("refreshUpdates", ["0"])[0].lower() in {
                    "1",
                    "true",
                    "yes",
                }
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.serialize_modules(
                        refresh_updates=refresh_updates,
                    ),
                )
                return

            if method == "GET" and path == "/api/launcher/doctor":
                self._send_json(HTTPStatus.OK, self.server.state.doctor_report())
                return

            if method == "GET" and path == "/api/launcher/settings":
                self._send_json(HTTPStatus.OK, self.server.state.get_settings())
                return

            if method == "PUT" and path == "/api/launcher/settings":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.update_settings(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/workspace":
                self._send_json(HTTPStatus.OK, self.server.state.get_workspace())
                return

            if method == "PUT" and path == "/api/launcher/workspace":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.update_workspace(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/workspace/sessions":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_workspace_session(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/akida/hosts":
                self._send_json(HTTPStatus.OK, self.server.state.list_akida_hosts())
                return

            if method == "POST" and path == "/api/launcher/akida/hosts":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_akida_host(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/pynq/boards":
                self._send_json(HTTPStatus.OK, self.server.state.list_pynq_boards())
                return

            if method == "POST" and path == "/api/launcher/pynq/boards":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_pynq_board(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/deployment/targets":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.list_deployment_targets(),
                )
                return

            if method == "POST" and path == "/api/launcher/deployment/targets":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_deployment_target(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/deployment/preflight":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.deployment_preflight(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/deployment/jobs":
                self._send_json(
                    HTTPStatus.ACCEPTED,
                    self.server.state.create_deployment_job(body or {}),
                )
                return

            segments = [segment for segment in path.split("/") if segment]
            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "deployment",
                "targets",
            ]:
                target_id = segments[4]
                if len(segments) == 5 and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_deployment_target(
                            target_id, body or {}
                        ),
                    )
                    return
                if len(segments) == 5 and method == "DELETE":
                    self.server.state.delete_deployment_target(target_id)
                    self._send_json(HTTPStatus.NO_CONTENT, {})
                    return

            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "deployment",
                "jobs",
            ]:
                job_id = segments[4]
                if len(segments) == 5 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.get_deployment_job(job_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "events" and method == "GET":
                    self._send_deployment_sse(job_id)
                    return
                if len(segments) == 6 and segments[5] == "cancel" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.cancel_deployment_job(job_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "retry" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.retry_deployment_job(job_id),
                    )
                    return

            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "akida",
                "hosts",
            ]:
                host_id = segments[4]
                if len(segments) == 5 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.get_akida_host(host_id)
                    )
                    return
                if len(segments) == 5 and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_akida_host(host_id, body or {}),
                    )
                    return
                if len(segments) == 5 and method == "DELETE":
                    self.server.state.delete_akida_host(host_id)
                    self._send_json(HTTPStatus.NO_CONTENT, {})
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "connectivity-test"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.test_akida_host_connection(host_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "provision" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.provision_akida_host(host_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "repair" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.repair_akida_host(host_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "restart-services"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.restart_akida_host_services(host_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "preflight"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_akida_host_preflight(host_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "status" and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_akida_host_status(host_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "map" and method == "POST":
                    bit_width_raw = query.get("bit_width", ["4"])[0]
                    try:
                        bit_width = int(bit_width_raw)
                    except (TypeError, ValueError):
                        raise ValueError("bit_width must be an integer")
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_map(
                            host_id,
                            body or {},
                            bit_width=bit_width,
                        ),
                    )
                    return
                if len(segments) == 6 and segments[5] == "run" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_run(host_id, body or {}),
                    )
                    return

            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "pynq",
                "boards",
            ]:
                board_id = segments[4]
                if len(segments) == 5 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.get_pynq_board(board_id)
                    )
                    return
                if len(segments) == 5 and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_pynq_board(board_id, body or {}),
                    )
                    return
                if len(segments) == 5 and method == "DELETE":
                    self.server.state.delete_pynq_board(board_id)
                    self._send_json(HTTPStatus.NO_CONTENT, {})
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "connectivity-test"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.test_pynq_board_connection(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "provision"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.provision_pynq_board(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "install-overlay"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.install_pynq_overlay_assets(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "restart-runtime"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.restart_pynq_runtime(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "preflight"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_pynq_board_preflight(board_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "status" and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_pynq_board_status(board_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "deploy" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_deploy(board_id, body or {}),
                    )
                    return
                if len(segments) == 6 and segments[5] == "verify" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_verify(board_id, body or {}),
                    )
                    return
                if len(segments) == 6 and segments[5] == "run" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_run(board_id, body or {}),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "runtime-status"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_runtime_status(board_id),
                    )
                    return

            if len(segments) == 5 and segments[:4] == [
                "api",
                "launcher",
                "workspace",
                "sessions",
            ]:
                module_id = segments[4]
                if method == "DELETE":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.delete_workspace_session(module_id),
                    )
                    return

            if len(segments) >= 4 and segments[:3] == ["api", "launcher", "modules"]:
                module_id = segments[3]
                if len(segments) == 4 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.serialize_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "logs" and method == "GET":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.get_logs(module_id)
                    )
                    return
                if len(segments) == 5 and segments[4] == "install" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.install_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "start" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.start_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "stop" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.stop_module(module_id)
                    )
                    return
                if (
                    len(segments) == 5
                    and segments[4] == "uninstall"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.uninstall_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "update" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.update_module(module_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[4] == "akida-runtime"
                    and segments[5] == "prepare"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.prepare_akida_runtime(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "settings" and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_module_settings(module_id, body or {}),
                    )
                    return

            self._send_json(HTTPStatus.NOT_FOUND, {"error": f"Unknown route: {path}"})
        except KeyError as exc:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": str(exc)})
        except RuntimeRequestError as exc:
            status = (
                HTTPStatus.GATEWAY_TIMEOUT
                if exc.kind == "timeout"
                else HTTPStatus.BAD_GATEWAY
            )
            if exc.status_code is not None:
                try:
                    status = HTTPStatus(exc.status_code)
                except ValueError:
                    status = HTTPStatus.BAD_GATEWAY
            payload: dict[str, Any] = {
                "error": str(exc),
                "path": path,
                "method": method,
            }
            if exc.response_body:
                payload["runtimeBody"] = exc.response_body
                try:
                    payload["runtimeJson"] = json.loads(exc.response_body)
                except json.JSONDecodeError:
                    pass
            self._send_json(status, payload)
        except Exception as exc:  # noqa: BLE001
            self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"error": str(exc), "path": path, "method": method},
            )

    def _read_body(self) -> dict[str, Any] | None:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return None
        raw = self.rfile.read(length)
        if not raw:
            return None
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return None
        return payload if isinstance(payload, dict) else None

    def _send_json(self, status: HTTPStatus, payload: Any) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header(
            "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS"
        )
        self.end_headers()
        if status != HTTPStatus.NO_CONTENT:
            self.wfile.write(encoded)

    def _send_deployment_sse(self, job_id: str) -> None:
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        sent = 0
        deadline = time.monotonic() + 60.0
        while time.monotonic() < deadline:
            events = self.server.state.deployment_job_events(job_id)
            for event in events[sent:]:
                self.wfile.write(event.encode("utf-8"))
                self.wfile.flush()
            sent = len(events)
            job = self.server.state.get_deployment_job(job_id)
            if str(job.get("stage") or "") in {"completed", "failed", "cancelled"}:
                break
            self.wfile.write(b"event: heartbeat\ndata: {}\n\n")
            self.wfile.flush()
            time.sleep(2.0)


class LauncherControlServer(ThreadingHTTPServer):
    """HTTP server bound to a shared launcher state."""

    daemon_threads = True

    def __init__(
        self, server_address: tuple[str, int], manage_suite_api: bool = True
    ) -> None:
        self.state = LauncherControlState(manage_suite_api=manage_suite_api)
        super().__init__(server_address, LauncherControlHandler)

    def server_close(self) -> None:
        self.state.shutdown()
        super().server_close()


def create_server(
    host: str, port: int, manage_suite_api: bool = True
) -> LauncherControlServer:
    return LauncherControlServer((host, port), manage_suite_api=manage_suite_api)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Launcher control service")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8090)
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

    server = create_server(args.host, args.port, manage_suite_api=args.manage_suite_api)
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
