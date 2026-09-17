"""Speck Backend for Neurochip.

Manages SynSense Speck model validation, simulator-backed mapping,
and runtime diagnostics.
"""

from __future__ import annotations

import hashlib
import io
import json
import logging
import sys
import zipfile
from datetime import datetime
from typing import Any, Literal

from ..._compat import UTC
from ...contracts.speck_runtime_contract import (
    SpeckDeploymentManifest,
    SpeckEnvironmentChecks,
    SpeckMappedNetworkPayloadContract,
    SpeckRuntimeStatusContract,
    SpeckSamnaConfigContract,
)
from .speck_compiler import compile_speck_mapped_network
from .speck_errors import SpeckConfigurationError, SpeckDeviceMappingError
from .speck_samna_runtime import SpeckSamnaRuntime
from .speck_simulator import SpeckSimulator, SpeckState

logger = logging.getLogger(__name__)

try:
    import samna  # type: ignore[import-not-found]
    import sinabs  # type: ignore[import-not-found]  # noqa: F401

    SAMNA_AVAILABLE = True
    SINABS_AVAILABLE = True
except ImportError:
    samna = None
    sinabs = None
    SAMNA_AVAILABLE = False
    SINABS_AVAILABLE = False
    logger.info("samna/sinabs not available — using SpeckSimulator fallback.")


def _list_samna_devices() -> list[Any]:
    """Return discoverable samna device descriptors."""
    if samna is None or not hasattr(samna, "device"):
        return []

    device_api = samna.device
    get_unopened_devices = getattr(device_api, "get_unopened_devices", None)
    if callable(get_unopened_devices):
        devices = get_unopened_devices()
        if isinstance(devices, list):
            return devices

    get_all_devices = getattr(device_api, "get_all_devices", None)
    if callable(get_all_devices):
        devices = get_all_devices()
        if isinstance(devices, list):
            return devices

    return []


def _is_speck_device(device_info: Any) -> bool:
    """Return whether a samna device descriptor appears to be a Speck target."""
    for attr in ("device_type_name", "device_type", "name"):
        value = getattr(device_info, attr, None)
        if isinstance(value, str) and "speck" in value.lower():
            return True
    return "speck" in str(device_info).lower()


def _describe_speck_device(device_info: Any) -> str:
    """Build a compact operator-facing device label from samna device info."""
    type_name = getattr(device_info, "device_type_name", None) or getattr(
        device_info, "device_type", None
    )
    serial_number = getattr(device_info, "serial_number", None)
    usb_bus_number = getattr(device_info, "usb_bus_number", None)
    usb_device_address = getattr(device_info, "usb_device_address", None)

    parts: list[str] = []
    if type_name:
        parts.append(str(type_name))
    if serial_number:
        parts.append(f"serial={serial_number}")
    if usb_bus_number is not None and usb_device_address is not None:
        parts.append(f"usb={usb_bus_number}:{usb_device_address}")

    return ", ".join(parts) if parts else str(device_info)


def _discover_speck_devices() -> list[Any]:
    """Return discoverable Speck devices only."""
    return [device_info for device_info in _list_samna_devices() if _is_speck_device(device_info)]


def _default_speck_device_type_name() -> str:
    """Return the best-known Speck device type label for artifact generation."""
    speck_devices = _discover_speck_devices()
    if speck_devices:
        type_name = getattr(speck_devices[0], "device_type_name", None)
        if isinstance(type_name, str) and type_name:
            return type_name
    return "Speck2fDevKit"


def _build_speck_configuration_json(
    mapped_network: dict[str, Any],
) -> tuple[str, bool, bool, int, Literal["readout_pin", "spike_monitor"]]:
    """Build a Samna-native SpeckConfiguration JSON string when possible."""
    monitor_enable = True
    readout_enable = False
    input_spike_layer = 0
    output_event_mode: Literal["readout_pin", "spike_monitor"] = "spike_monitor"
    output_population_size = 0
    populations = mapped_network.get("populations", [])
    if populations:
        output_population_size = int(populations[-1].get("size", 0) or 0)
        readout_enable = output_population_size > 0 and output_population_size <= 15
        if readout_enable:
            input_spike_layer = 12
            output_event_mode = "readout_pin"

    if samna is not None:
        try:
            configuration_module = samna.speck2f.configuration
            config = configuration_module.SpeckConfiguration()
            config.dvs_layer.monitor_enable = monitor_enable
            first_destination = config.dvs_layer.destinations[0]
            first_destination.enable = True
            first_destination.layer = input_spike_layer
            config.readout.enable = readout_enable
            if readout_enable:
                config.readout.internal_slow_clk = True
                config.readout.threshold = 1
                config.readout.readout_pin_monitor_enable = True
                config.readout.low_pass_filter_disable = True
                config.readout.readout_configuration_sel = 3
                config.factory_config.io_sel = 24
            return (
                str(config.to_json()),
                monitor_enable,
                readout_enable,
                input_spike_layer,
                output_event_mode,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Failed to build samna-native Speck configuration JSON: %s", exc)

    fallback_config = {
        "dvs_layer": {
            "monitor_enable": monitor_enable,
            "destinations": [
                {"enable": True, "layer": 0},
                {"enable": False, "layer": 0},
            ],
        },
        "readout": {
            "enable": readout_enable,
            "internal_slow_clk": readout_enable,
            "threshold": 1,
            "readout_pin_monitor_enable": readout_enable,
            "low_pass_filter_disable": readout_enable,
            "readout_configuration_sel": 3 if readout_enable else 0,
        },
        "factory_config": {
            "io_sel": 24 if readout_enable else 0,
        },
    }
    return (
        json.dumps(fallback_config, indent=2),
        monitor_enable,
        readout_enable,
        input_spike_layer,
        output_event_mode,
    )


def collect_speck_environment_checks() -> dict[str, Any]:
    """Return structured local-environment diagnostics for the Speck runtime."""
    host_supported = sys.platform in ("linux", "darwin")
    python_supported = sys.version_info[:2] >= (3, 10)
    device_discovery_supported = (
        host_supported and python_supported and SAMNA_AVAILABLE and SINABS_AVAILABLE
    )
    discovered_device_count = 0

    if device_discovery_supported:
        try:
            discovered_device_count = sum(
                1 for device_info in _list_samna_devices() if _is_speck_device(device_info)
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Failed to probe Speck devices via samna: %s", exc)

    recommended_runtime: Literal["local_hw", "simulator", "not_available"]

    if not host_supported or not python_supported:
        recommended_runtime = "not_available"
    elif discovered_device_count > 0:
        recommended_runtime = "local_hw"
    else:
        recommended_runtime = "simulator"

    checks = SpeckEnvironmentChecks(
        host_supported=host_supported,
        python_supported=python_supported,
        sinabs_available=SINABS_AVAILABLE,
        samna_available=SAMNA_AVAILABLE,
        device_discovery_supported=device_discovery_supported,
        device_discovered=discovered_device_count > 0,
        discovered_device_count=discovered_device_count,
        recommended_runtime=recommended_runtime,
    )
    return checks.model_dump()


def build_speck_runtime_status(
    *,
    state: str,
    model_summary: dict[str, Any] | None = None,
    runtime_target: str | None = None,
    device_info: str | None = None,
    last_sdk_issue: str | None = None,
    last_sdk_issue_detail: str | None = None,
) -> dict[str, Any]:
    """Build a truthful Speck runtime status payload for routers and services."""
    environment_checks = collect_speck_environment_checks()
    sdk_available = SAMNA_AVAILABLE and SINABS_AVAILABLE

    sdk_issues: list[str] = []
    if not environment_checks["host_supported"]:
        sdk_issues.append("unsupported_os")
    if not environment_checks["python_supported"]:
        sdk_issues.append("unsupported_python")
    if not environment_checks["sinabs_available"]:
        sdk_issues.append("sinabs_missing")
    if not environment_checks["samna_available"]:
        sdk_issues.append("samna_missing")
    if (
        sdk_available
        and environment_checks["device_discovery_supported"]
        and not environment_checks["device_discovered"]
    ):
        sdk_issues.append("device_not_found")
    if last_sdk_issue is not None:
        sdk_issues.append(last_sdk_issue)
    if not sdk_available:
        sdk_issues.append("sdk_not_available")

    if not sdk_available:
        sdk_status = "not_available"
    elif last_sdk_issue == "device_mapping_failure":
        sdk_status = "mapping_failed"
    elif state in {SpeckState.MAPPED.name.lower(), SpeckState.RUNNING.name.lower()}:
        sdk_status = "deployable"
    else:
        sdk_status = "available"

    detail = last_sdk_issue_detail
    if detail is None and not environment_checks["host_supported"]:
        detail = "Speck runtime is currently supported on Linux and macOS hosts only."
    if detail is None and not environment_checks["python_supported"]:
        detail = "Speck runtime requires Python 3.10 or newer."
    if (
        detail is None
        and sdk_available
        and environment_checks["device_discovery_supported"]
        and environment_checks["device_discovered"]
        and runtime_target == "software_fallback"
    ):
        detail = (
            "Speck device discovery succeeded via samna, but Neurochip is still executing "
            "through the simulator-backed runtime path."
        )
    if detail is None and runtime_target == "hardware":
        detail = (
            "Speck device discovery succeeded and Neurochip selected the Samna-backed "
            "hardware adapter. Artifact-backed event I/O is enabled for the current "
            "Speck deployment path."
        )
    if (
        detail is None
        and sdk_available
        and environment_checks["device_discovery_supported"]
        and not environment_checks["device_discovered"]
    ):
        detail = (
            "samna and sinabs are installed, but no unopened Speck device was discovered; "
            "Speck runtime is using the simulator."
        )
    if detail is None and not sdk_available:
        detail = "samna and sinabs are not both installed; Speck runtime is using the simulator."

    status = SpeckRuntimeStatusContract(
        state=state,
        sdk_available=sdk_available,
        sdk_status=sdk_status,
        sdk_issues=sdk_issues,
        model_summary=model_summary,
        runtime_target=runtime_target or "unknown",
        device_info=device_info,
        sdk_issue_detail=detail,
        environment_checks=SpeckEnvironmentChecks(**environment_checks),
    )
    return status.model_dump()


class SpeckBackend:
    """Hardware-aware Speck runtime backend."""

    def __init__(self) -> None:
        self._simulator: SpeckSimulator | None = None
        self._hardware_runtime: SpeckSamnaRuntime | None = None
        self.state: SpeckState = SpeckState.UNINITIALIZED
        self._mapped_network: dict[str, Any] | None = None
        self._device: Any = None
        self._runtime_target: str = "unknown"
        self._device_info: str | None = None
        self._deployment_artifact: bytes | None = None
        self._last_sdk_issue: str | None = None
        self._last_sdk_issue_detail: str | None = None
        self._select_runtime_backend()

    def _select_runtime_backend(self) -> None:
        """Select a truthful runtime backend without requiring startup hardware."""
        checks = collect_speck_environment_checks()
        if checks["recommended_runtime"] == "local_hw":
            self._hardware_runtime = SpeckSamnaRuntime(
                samna_module=samna,
                discover_devices=_discover_speck_devices,
                describe_device=_describe_speck_device,
            )
            self._simulator = None
            self._runtime_target = "hardware"
            discovered_devices = _discover_speck_devices()
            if discovered_devices:
                self._device_info = _describe_speck_device(discovered_devices[0])
            return

        self._hardware_runtime = None
        self._simulator = SpeckSimulator()
        self._runtime_target = "software_fallback"
        self._device_info = SpeckSimulator.__name__

    def construct_model(self, mapped_network: dict[str, Any]) -> None:
        """Build a Speck model from a mapped network payload."""
        contract = SpeckMappedNetworkPayloadContract(**mapped_network)
        self._mapped_network = contract.model_dump()
        self._deployment_artifact = None
        self._last_sdk_issue = None
        self._last_sdk_issue_detail = None

        if self._hardware_runtime is not None:
            self._hardware_runtime.construct_model(self._mapped_network)
            self.state = SpeckState.CONSTRUCTED
            self._runtime_target = self._hardware_runtime.runtime_target
            self._device_info = self._hardware_runtime.device_info or self._device_info
            return

        if self._simulator is not None:
            self._simulator.construct_model(self._mapped_network)
            self.state = SpeckState.CONSTRUCTED
            return

        self.state = SpeckState.CONSTRUCTED

    def map_to_device(self) -> None:
        """Map the model to a Speck device or simulator."""
        if self.state == SpeckState.UNINITIALIZED:
            raise SpeckConfigurationError("Cannot map before construction")

        if self._hardware_runtime is not None:
            try:
                if self._deployment_artifact is None:
                    self._deployment_artifact = self.generate_package()
                self._hardware_runtime.load_artifact(self._deployment_artifact)
                self._hardware_runtime.map_to_device()
            except SpeckDeviceMappingError as exc:
                self._runtime_target = "unknown"
                self._device_info = None
                self._last_sdk_issue = "device_mapping_failure"
                self._last_sdk_issue_detail = str(exc)
                raise

            self._runtime_target = self._hardware_runtime.runtime_target
            self._device_info = self._hardware_runtime.device_info
            self.state = SpeckState.MAPPED
            return

        if self._simulator is not None:
            self._simulator.map_to_device()
            self._runtime_target = "software_fallback"
            self._device_info = "SpeckSimulator"
            self.state = SpeckState.MAPPED
            return

        try:
            self._runtime_target = "software_fallback"
            self._device_info = "SpeckSimulator"
            self.state = SpeckState.MAPPED
        except Exception as exc:
            self._last_sdk_issue = "device_mapping_failure"
            self._last_sdk_issue_detail = str(exc)
            raise SpeckDeviceMappingError(f"Mapping failed: {exc}") from exc

    def run_inference(self, inputs: list[float]) -> dict[str, Any]:
        """Run inference on the mapped model."""
        if self.state not in (SpeckState.MAPPED, SpeckState.RUNNING):
            raise SpeckConfigurationError("Not mapped")

        if self._hardware_runtime is not None:
            return self._hardware_runtime.run_inference(inputs)

        if self._simulator is not None:
            return self._simulator.run_inference(inputs)

        self.state = SpeckState.RUNNING
        self.state = SpeckState.MAPPED
        return {"outputs": [], "telemetry": {}}

    def reset(self) -> None:
        """Return to CONSTRUCTED state, clearing any mapped device state."""
        if self.state == SpeckState.UNINITIALIZED:
            raise SpeckConfigurationError(
                "Cannot reset — model was never constructed",
                error_code="RESET_BEFORE_CONSTRUCT",
            )

        if self._hardware_runtime is not None:
            self._hardware_runtime.reset()
            self.state = SpeckState.CONSTRUCTED
            self._runtime_target = self._hardware_runtime.runtime_target
            self._device_info = self._hardware_runtime.device_info
            return

        if self._simulator is not None:
            self._simulator.reset()
            self.state = SpeckState.CONSTRUCTED
            self._runtime_target = "software_fallback"
            self._device_info = "SpeckSimulator"
            return

        self._device = None
        self.state = SpeckState.CONSTRUCTED

    def get_status(self) -> dict[str, Any]:
        """Return current status contract."""
        model_summary = None
        if self._mapped_network is not None:
            model_summary = self._mapped_network.get("network_summary")
            if model_summary is None:
                model_summary = {
                    "n_populations": len(self._mapped_network.get("populations", [])),
                    "n_connections": len(self._mapped_network.get("connections", [])),
                }

        if (
            SAMNA_AVAILABLE
            and SINABS_AVAILABLE
            and self._runtime_target == "software_fallback"
            and self._device_info == SpeckSimulator.__name__
        ):
            try:
                speck_devices = [
                    device_info
                    for device_info in _list_samna_devices()
                    if _is_speck_device(device_info)
                ]
            except Exception as exc:  # noqa: BLE001
                logger.warning("Failed to inspect Speck device metadata for status: %s", exc)
            else:
                if speck_devices:
                    self._device_info = _describe_speck_device(speck_devices[0])

        return build_speck_runtime_status(
            state=self.current_state,
            model_summary=model_summary,
            runtime_target=self._runtime_target,
            device_info=self._device_info,
            last_sdk_issue=self._last_sdk_issue,
            last_sdk_issue_detail=self._last_sdk_issue_detail,
        )

    def generate_package(self) -> bytes:
        """Generate a scaffold Speck deployment package from the mapped network."""
        if self.state == SpeckState.UNINITIALIZED or self._mapped_network is None:
            raise SpeckConfigurationError(
                "Cannot generate package before model is constructed",
                error_code="PACKAGE_BEFORE_CONSTRUCT",
            )

        mapped = self._mapped_network
        populations = mapped.get("populations", [])
        connections = mapped.get("connections", [])
        network_summary = mapped.get("network_summary", {})
        timestamp = datetime.now(UTC).isoformat()

        compile_plan = compile_speck_mapped_network(mapped)
        model_json = {
            "network_name": "SNN Network",
            "timestamp": timestamp,
            "mapped_network": mapped,
            "runtime_target": self._runtime_target,
            "sdk_available": SAMNA_AVAILABLE and SINABS_AVAILABLE,
            "network_summary": network_summary,
            "compile_summary": {
                "compiler_backend": compile_plan["compiler_backend"],
                "deployable": compile_plan["deployable"],
                "topology_mode": compile_plan["topology_mode"],
            },
        }
        core_count = min(max(1, len(populations)), 11)
        readme = (
            f"# Neurochip Speck Deployment Package\n\n"
            f"Auto-generated on {timestamp}\n\n"
            f"## Target\n"
            f"- Device: SynSense Speck 2\n"
            f"- SDK available: {SAMNA_AVAILABLE and SINABS_AVAILABLE}\n"
            f"- Runtime target at generation: {self._runtime_target}\n\n"
            f"## Network Summary\n"
            f"- Populations: {len(populations)}\n"
            f"- Connections: {len(connections)}\n"
            f"- Total neurons: {sum(int(pop.get('size', 0)) for pop in populations)}\n"
            f"- Weight bit-width: {network_summary.get('weight_bit_width', 8)}-bit\n\n"
            f"## Compile Summary\n"
            f"- Compiler backend: {compile_plan['compiler_backend']}\n"
            f"- Deployable by current hardware path: {compile_plan['deployable']}\n"
            f"- Topology mode: {compile_plan['topology_mode']}\n"
            f"- Compiler issues: {compile_plan['compiler_issues'] or 'None'}\n\n"
            f"## Package Contents\n"
            f"- `model.json` — validated mapped-network payload\n"
            f"- `compile_plan.json` — truthful Speck compile classification and schedule\n"
            f"- `config.samna` — Samna runtime scaffold configuration\n"
            f"- `manifest.json` — typed Speck deployment manifest\n"
            f"- `README.md` — operator notes\n"
        )

        model_payload = json.dumps(model_json, indent=2)
        (
            configuration_json,
            monitor_enable,
            readout_enable,
            input_spike_layer,
            output_event_mode,
        ) = _build_speck_configuration_json(mapped)
        if compile_plan["output_event_mode"] != output_event_mode:
            output_event_mode = compile_plan["output_event_mode"]
        if compile_plan["input_spike_layer"] != input_spike_layer:
            input_spike_layer = int(compile_plan["input_spike_layer"])
        compile_plan_payload = json.dumps(compile_plan, indent=2)
        config_payload = SpeckSamnaConfigContract(
            device_type_name=_default_speck_device_type_name(),
            samna_configuration_type="samna.speck2f.configuration.SpeckConfiguration",
            artifact_mode="samna_configured" if samna is not None else "scaffold",
            monitor_enable=monitor_enable,
            readout_enable=readout_enable,
            input_spike_layer=input_spike_layer,
            output_event_mode=output_event_mode,
            configuration_json=configuration_json,
            population_count=len(populations),
            connection_count=len(connections),
        ).model_dump_json(indent=2)
        checksum = hashlib.sha256(
            (model_payload + compile_plan_payload + config_payload).encode("utf-8")
        ).hexdigest()
        manifest = SpeckDeploymentManifest(
            core_count=core_count,
            firmware_version="1.0.0",
            artifact_schema_version="1.0.0",
            checksum_sha256=checksum,
        )

        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("speck_deploy/model.json", model_payload)
            zf.writestr("speck_deploy/compile_plan.json", compile_plan_payload)
            zf.writestr("speck_deploy/config.samna", config_payload)
            zf.writestr("speck_deploy/manifest.json", manifest.model_dump_json(indent=2))
            zf.writestr("speck_deploy/README.md", readme)

        self._deployment_artifact = buffer.getvalue()
        return self._deployment_artifact

    @property
    def current_state(self) -> str:
        """Return the current lifecycle state as a lowercase string."""
        if self._hardware_runtime is not None:
            return self._hardware_runtime.current_state
        if self._simulator is not None:
            return self._simulator.current_state
        return self.state.name.lower()
