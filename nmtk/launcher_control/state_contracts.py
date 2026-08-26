"""Typed launcher state records and stable status constants.

This module is deliberately dependency-free so services can share launcher
contracts without importing the ``server`` compatibility façade.
"""

from __future__ import annotations

import textwrap
from typing import Any, Literal, NotRequired, TypedDict

ModuleStatusName = Literal[
    "notInstalled",
    "installing",
    "installed",
    "starting",
    "running",
    "stopping",
    "error",
    "degraded",
    "updating",
]
PreflightStatus = Literal["ok", "degraded", "failed"]
PynqBoardState = Literal[
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
]
AkidaHostState = Literal[
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
]
AkidaRuntimeMode = Literal[
    "local_sdk",
    "remote_sdk",
    "simulator_only",
    "unknown",
]


class AkidaCapabilitySnapshot(TypedDict):
    """Normalized capability fields persisted for one Akida host."""

    hostSupported: bool
    pythonSupported: bool
    tensorflowAvailable: bool
    cnn2snnAvailable: bool
    akidaModelsAvailable: bool
    recommendedRuntime: AkidaRuntimeMode


class PynqBoardRecord(TypedDict, total=False):
    """Internal persisted PYNQ record; wire serialization removes secrets."""

    id: str
    displayName: str
    host: str
    sshPort: int
    username: str
    authMode: str
    credentialRef: str
    password: str
    sshKeyPath: str
    runtimeApiUrl: str
    runtimeApiUrlOverride: str
    overlayVersion: str
    state: PynqBoardState
    lastPreflightStatus: str
    lastPreflightMessage: str
    lastRuntimeMode: str
    lastStatus: dict[str, Any] | None
    remoteInstallRoot: str
    remoteVenvPath: str
    remotePynqVenvPath: str
    remoteOverlayDir: str
    remoteInstallStatusPath: str
    remoteRuntimeLogPath: str
    remoteServiceName: str
    agentExecutableName: str
    isDefault: bool
    hasPassword: NotRequired[bool]


class AkidaHostRecord(TypedDict, total=False):
    """Internal persisted Akida record; wire serialization removes secrets."""

    id: str
    displayName: str
    host: str
    port: int
    sshPort: int
    controlPort: int
    username: str
    baseUrl: str
    runtimeApiUrl: str
    controlApiUrl: str
    authMode: str
    credentialRef: str
    password: str
    sshKeyPath: str
    remoteInstallRoot: str
    remoteVenvPath: str
    serviceUser: str
    runtimeServiceName: str
    controlServiceName: str
    tokenPath: str
    installStatusPath: str
    hostOs: str
    pythonVersion: str
    runtimeMode: AkidaRuntimeMode
    state: AkidaHostState
    lastPreflightStatus: str
    lastPreflightMessage: str
    lastSdkStatus: str
    lastRuntimeTarget: str
    lastStatus: dict[str, Any] | None
    lastReadinessMessage: str
    lastVerifiedAt: str
    lastInstallStatus: dict[str, Any] | None
    installedRuntimeVersion: str
    availableRuntimeVersion: str
    runtimeArtifactSha256: str
    runtimeUpdateState: str
    lastRuntimeUpdateJob: dict[str, Any] | None
    capabilitySnapshot: AkidaCapabilitySnapshot | None
    isDefault: bool
    autoDiscovered: bool
    sameHostAsBackend: bool
    hasPassword: NotRequired[bool]


class LauncherSettingsRecord(TypedDict):
    """Complete launcher settings document after loading and normalization."""

    logLevel: str
    mujocoAvailable: bool
    pythonAvailable: bool
    akidaHosts: list[AkidaHostRecord]
    akidaRuntimeUpdateJobs: list[dict[str, Any]]
    pynqBoards: list[PynqBoardRecord]
    selectedAkidaHostId: str | None
    selectedPynqBoardId: str | None


STATUS_INDEX: dict[ModuleStatusName, int] = {
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
PREFLIGHT_OK: PreflightStatus = "ok"
PREFLIGHT_DEGRADED: PreflightStatus = "degraded"
PREFLIGHT_FAILED: PreflightStatus = "failed"
SUPPORTED_INSTALL_STRATEGIES = {"pip"}
SUPPORTED_START_STRATEGIES = {"uvicorn", "none"}
PREFLIGHT_SENTINEL = "NMTK_PREFLIGHT_JSON="
INSTALL_STATUS_SENTINEL = "INSTALL_STATUS_JSON="
DEFAULT_AKIDA_HOST_PORT = 8002
DEFAULT_AKIDA_CONTROL_PORT = 8091
DEFAULT_AKIDA_HOST_SSH_PORT = 22
DEFAULT_PYNQ_BOARD_PORT = 8002
DEFAULT_PYNQ_BOARD_SSH_PORT = 22
DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS = 120.0
PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS = (5.0, 600.0)
PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS = 15.0
DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS = 45.0
PYNQ_PREFLIGHT_TIMEOUT_BOUNDS = (5.0, 300.0)
PYNQ_PREFLIGHT_RETRY_COUNT = 3
PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS = 2.0
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
AKIDA_RUNTIME_MODES = {"local_sdk", "remote_sdk", "simulator_only", "unknown"}
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
PYNQ_BOARD_STATES: set[str] = {
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
AKIDA_HOST_STATES: set[str] = {
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


__all__ = [
    "AkidaCapabilitySnapshot",
    "AkidaHostRecord",
    "AkidaHostState",
    "AkidaRuntimeMode",
    "LauncherSettingsRecord",
    "ModuleStatusName",
    "PreflightStatus",
    "PynqBoardRecord",
    "PynqBoardState",
]
