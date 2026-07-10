"""Manifest-backed contracts for launcher-managed Neurochip runtimes.

This module deliberately has no dependency on the HTTP server or runtime
services.  Keeping the manifest parser here makes the PYNQ and Akida defaults
usable by provisioning and diagnostics without introducing a reverse import.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


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
        return self.install_root_template.replace(
            "{username}", username.strip() or self.default_username
        )

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
    control_port: int = 8091
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
    akida: AkidaLauncherRuntimeContract = field(default_factory=AkidaLauncherRuntimeContract)


def _string(value: Any, default: str) -> str:
    return str(value or "").strip() or default


def _integer(value: Any, default: int) -> int:
    return value if isinstance(value, int) else default


def load_neurochip_launcher_runtime_contract(
    manifest_path: Path,
) -> NeurochipLauncherRuntimeContract:
    """Read Neurochip launcher defaults, falling back safely on malformed data."""
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        manifest = []

    runtime: dict[str, Any] = {}
    if isinstance(manifest, list):
        runtime = next(
            (
                raw["launcherRuntime"]
                for raw in manifest
                if isinstance(raw, dict)
                and str(raw.get("id") or "").strip() == "Neurochip"
                and isinstance(raw.get("launcherRuntime"), dict)
            ),
            {},
        )
    pynq_raw = runtime.get("pynq") if isinstance(runtime.get("pynq"), dict) else {}
    akida_raw = runtime.get("akida") if isinstance(runtime.get("akida"), dict) else {}
    pynq = PynqLauncherRuntimeContract()
    akida = AkidaLauncherRuntimeContract()
    return NeurochipLauncherRuntimeContract(
        pynq=PynqLauncherRuntimeContract(
            runtime_port=_integer(pynq_raw.get("runtimePort"), pynq.runtime_port),
            ssh_port=_integer(pynq_raw.get("sshPort"), pynq.ssh_port),
            default_username=_string(pynq_raw.get("defaultUsername"), pynq.default_username),
            default_state=_string(pynq_raw.get("defaultState"), pynq.default_state),
            default_auth_mode=_string(pynq_raw.get("defaultAuthMode"), pynq.default_auth_mode),
            legacy_install_root=_string(pynq_raw.get("legacyInstallRoot"), pynq.legacy_install_root),
            install_root_template=_string(pynq_raw.get("installRootTemplate"), pynq.install_root_template),
            agent_venv_dir_name=_string(pynq_raw.get("agentVenvDirName"), pynq.agent_venv_dir_name),
            runtime_venv_dir_name=_string(pynq_raw.get("runtimeVenvDirName"), pynq.runtime_venv_dir_name),
            overlay_dir_name=_string(pynq_raw.get("overlayDirName"), pynq.overlay_dir_name),
            service_name=_string(pynq_raw.get("serviceName"), pynq.service_name),
            agent_executable_name=_string(pynq_raw.get("agentExecutableName"), pynq.agent_executable_name),
            install_status_filename=_string(pynq_raw.get("installStatusFilename"), pynq.install_status_filename),
            runtime_log_filename=_string(pynq_raw.get("runtimeLogFilename"), pynq.runtime_log_filename),
            overlay_staging_subdir=_string(pynq_raw.get("overlayStagingSubdir"), pynq.overlay_staging_subdir),
        ),
        akida=AkidaLauncherRuntimeContract(
            runtime_port=_integer(akida_raw.get("runtimePort"), akida.runtime_port),
            control_port=_integer(akida_raw.get("controlPort"), akida.control_port),
            ssh_port=_integer(akida_raw.get("sshPort"), akida.ssh_port),
            default_state=_string(akida_raw.get("defaultState"), akida.default_state),
            default_auth_mode=_string(akida_raw.get("defaultAuthMode"), akida.default_auth_mode),
            install_root=_string(akida_raw.get("installRoot"), akida.install_root),
            service_user=_string(akida_raw.get("serviceUser"), akida.service_user),
            venv_dir_name=_string(akida_raw.get("venvDirName"), akida.venv_dir_name),
            runtime_service_name=_string(akida_raw.get("runtimeServiceName"), akida.runtime_service_name),
            control_service_name=_string(akida_raw.get("controlServiceName"), akida.control_service_name),
            token_relative_path=_string(akida_raw.get("tokenRelativePath"), akida.token_relative_path),
            install_status_relative_path=_string(akida_raw.get("installStatusRelativePath"), akida.install_status_relative_path),
        ),
    )
