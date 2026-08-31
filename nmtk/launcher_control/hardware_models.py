"""Typed hardware records, normalization, and launcher compatibility helpers."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from collections.abc import Mapping
from http import HTTPStatus
from pathlib import Path
from typing import Any, cast
from urllib.parse import urlparse
from uuid import uuid4

from .config import MODULES_MANIFEST, REPO_ROOT
from .pynq_status import (
    _default_runtime_api_url as _default_runtime_api_url,
)
from .pynq_status import (
    _effective_runtime_api_url as _effective_runtime_api_url,
)
from .pynq_status import (
    _serialize_pynq_board as _serialize_pynq_board,
)
from .runtime_contracts import (
    AkidaLauncherRuntimeContract as AkidaLauncherRuntimeContract,
)
from .runtime_contracts import (
    NeurochipLauncherRuntimeContract as NeurochipLauncherRuntimeContract,
)
from .runtime_contracts import (
    PynqLauncherRuntimeContract as PynqLauncherRuntimeContract,
)
from .runtime_contracts import (
    load_neurochip_launcher_runtime_contract,
)
from .runtime_errors import RuntimeRequestError as RuntimeRequestError
from .state_contracts import (
    AKIDA_HOST_AUTH_MODES,
    AKIDA_HOST_STATES,
    AKIDA_RUNTIME_MODES,
    BENIGN_SSH_WARNING_PREFIXES,
    DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS,
    DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
    DEFAULT_PYNQ_RUN_TIMEOUT_SECONDS,
    DEFAULT_STAGED_OVERLAY_MANIFEST,
    DEFAULT_STAGED_PYNQ_BITSTREAM_NAME,
    DEFAULT_STAGED_PYNQ_HWH_NAME,
    INSTALL_STATUS_SENTINEL,
    PREFLIGHT_DEGRADED,
    PREFLIGHT_OK,
    PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS,
    PYNQ_BOARD_STATES,
    PYNQ_PREFLIGHT_TIMEOUT_BOUNDS,
    PYNQ_RUN_TIMEOUT_BOUNDS,
    STATUS_INDEX,
    AkidaCapabilitySnapshot,
    AkidaHostRecord,
    AkidaHostState,
    AkidaRuntimeMode,
    PynqBoardRecord,
    PynqBoardState,
)

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


def _load_neurochip_launcher_runtime_contract() -> NeurochipLauncherRuntimeContract:
    return load_neurochip_launcher_runtime_contract(MODULES_MANIFEST)


def _validate_pynq_overlay_manifest(payload: Any) -> None:
    if not isinstance(payload, dict):
        raise ValueError("manifest must be a JSON object")  # noqa: TRY004

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
        raise ValueError("register_map must be an object")  # noqa: TRY004
    if register_map.get("dma_channel") != payload.get("dma_ip_name"):
        raise ValueError("register_map.dma_channel must match dma_ip_name")

    weight_layout = payload.get("weight_layout")
    if not isinstance(weight_layout, dict):
        raise ValueError("weight_layout must be an object")  # noqa: TRY004
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
        raise ValueError("layer_config_layout must be an object")  # noqa: TRY004
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


def _normalize_pynq_board_state(value: Any, default_state: str) -> PynqBoardState:
    candidate = str(value or default_state).strip().lower()
    normalized_default = default_state.strip().lower() or "unpaired"
    resolved = candidate if candidate in PYNQ_BOARD_STATES else normalized_default
    # Membership validation above narrows the runtime value to the closed state set.
    return cast(PynqBoardState, resolved)


def _normalize_akida_host_state(value: Any, default_state: str) -> AkidaHostState:
    candidate = str(value or default_state).strip().lower()
    normalized_default = default_state.strip().lower() or "unknown"
    resolved = candidate if candidate in AKIDA_HOST_STATES else normalized_default
    # Membership validation above narrows the runtime value to the closed state set.
    return cast(AkidaHostState, resolved)


def _normalize_akida_runtime_mode(value: Any) -> AkidaRuntimeMode:
    candidate = str(value or "unknown").strip().lower()
    resolved = candidate if candidate in AKIDA_RUNTIME_MODES else "unknown"
    # Membership validation above narrows the runtime value to the closed mode set.
    return cast(AkidaRuntimeMode, resolved)


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
    raw: Mapping[str, Any],
    runtime_port: int,
) -> str:
    default_url = f"http://{host}:{runtime_port}" if host else ""
    explicit_override = raw.get("runtimeApiUrlOverride")
    if explicit_override is not None:
        override = str(explicit_override).strip()
        return "" if not override or override == default_url else override

    legacy_runtime_api_url = str(raw.get("runtimeApiUrl") or "").strip()
    if legacy_runtime_api_url and legacy_runtime_api_url != default_url:
        return legacy_runtime_api_url
    return ""


def _pynq_user_space_upgrade_message(username: str) -> str:
    return (
        "Runtime is running in user space. Install the overlay now; after a board "
        "reboot, choose Restart runtime here before deploying again."
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


def _normalize_pynq_board(raw: Mapping[str, Any]) -> PynqBoardRecord:
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

    board: PynqBoardRecord = {
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
            raise RuntimeError(  # noqa: TRY004
                "Install status sentinel must decode to an object"
            )
        return payload
    return None


def _resolved_pynq_runtime_api_url(board: Mapping[str, Any]) -> str:
    return _effective_runtime_api_url(
        str(board.get("host") or "").strip(),
        str(board.get("runtimeApiUrlOverride") or "").strip(),
        _load_neurochip_launcher_runtime_contract().pynq.runtime_port,
    )


def _resolved_akida_base_url(host: Mapping[str, Any]) -> str:
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


def _resolved_akida_control_api_url(host: Mapping[str, Any]) -> str:
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
    host: Mapping[str, Any],
    status: Mapping[str, Any],
) -> AkidaHostState:
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


def _normalize_akida_capability_snapshot(
    raw: Any,
) -> AkidaCapabilitySnapshot | None:
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


def _normalize_akida_host(raw: Mapping[str, Any]) -> AkidaHostRecord:
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
    recommended_runtime = (
        capability_snapshot["recommendedRuntime"]
        if capability_snapshot is not None
        else None
    )
    runtime_mode = _normalize_akida_runtime_mode(
        raw.get("runtimeMode") or recommended_runtime
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


def _serialize_akida_host(host: Mapping[str, Any]) -> dict[str, Any]:
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
    except (urllib.error.URLError, TimeoutError, ValueError):
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
