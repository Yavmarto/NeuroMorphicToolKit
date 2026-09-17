"""Samna-backed Speck runtime adapter.

This adapter owns physical-device selection and lifecycle transitions for
hosts where the SynSense Speck SDK is installed and a discoverable Speck
device is present.
"""

from __future__ import annotations

import io
import json
import logging
import time
import zipfile
from collections.abc import Callable
from typing import Any

from ...contracts.speck_runtime_contract import (
    SpeckDeploymentManifest,
    SpeckSamnaConfigContract,
    validate_speck_runtime_artifact_archive,
)
from .speck_errors import (
    SpeckConfigurationError,
    SpeckDeviceMappingError,
    SpeckInferenceError,
    SpeckSdkNotAvailableError,
)
from .speck_simulator import SpeckState

logger = logging.getLogger(__name__)


class SpeckSamnaRuntime:
    """Minimal hardware adapter for a discoverable Speck device via samna."""

    def __init__(
        self,
        *,
        samna_module: Any,
        discover_devices: Callable[[], list[Any]],
        describe_device: Callable[[Any], str],
    ) -> None:
        self._samna = samna_module
        self._discover_devices = discover_devices
        self._describe_device = describe_device
        self._device: Any = None
        self._mapped_network: dict[str, Any] | None = None
        self._device_info: str | None = None
        self._artifact_bytes: bytes | None = None
        self._artifact_manifest: SpeckDeploymentManifest | None = None
        self._compile_plan: dict[str, Any] | None = None
        self._config_payload: SpeckSamnaConfigContract | None = None
        self._event_source: Any = None
        self._event_sink: Any = None
        self.state: SpeckState = SpeckState.UNINITIALIZED

    @property
    def runtime_target(self) -> str:
        """Return the runtime target label for status payloads."""
        return "hardware"

    @property
    def device_info(self) -> str | None:
        """Return the active hardware device label."""
        return self._device_info

    def construct_model(self, mapped_network: dict[str, Any]) -> None:
        """Store the mapped network pending artifact-backed deployment."""
        populations = mapped_network.get("populations", [])
        if not populations:
            raise SpeckConfigurationError(
                "Cannot construct model: populations list is empty",
                error_code="CONSTRUCT_EMPTY_POPULATIONS",
            )

        self._mapped_network = dict(mapped_network)
        self.state = SpeckState.CONSTRUCTED

    def load_artifact(self, artifact_bytes: bytes) -> None:
        """Validate and store a deployment artifact for later device mapping."""
        self._artifact_manifest = validate_speck_runtime_artifact_archive(artifact_bytes)
        self._artifact_bytes = artifact_bytes
        # `config.samna` is validated as part of the archive validator, but we still
        # load it here so the runtime can apply the serialized configuration.
        with zipfile.ZipFile(io.BytesIO(artifact_bytes)) as archive:
            compile_plan_raw = archive.read("speck_deploy/compile_plan.json").decode("utf-8")
            config_raw = archive.read("speck_deploy/config.samna").decode("utf-8")
        self._compile_plan = json.loads(compile_plan_raw)
        self._config_payload = SpeckSamnaConfigContract(**json.loads(config_raw))

    def _apply_configuration_to_device(self) -> None:
        """Apply the serialized SpeckConfiguration to the opened device model."""
        if self._device is None or self._config_payload is None:
            raise SpeckDeviceMappingError(
                "Speck hardware configuration is not loaded.",
                error_code="CONFIGURATION_NOT_LOADED",
            )

        get_model = getattr(self._device, "get_model", None)
        if not callable(get_model):
            raise SpeckDeviceMappingError(
                "Opened Speck device does not expose get_model().",
                error_code="MODEL_ACCESS_UNAVAILABLE",
            )

        model = get_model()
        apply_configuration = getattr(model, "apply_configuration", None)
        if not callable(apply_configuration):
            raise SpeckDeviceMappingError(
                "Opened Speck model does not expose apply_configuration().",
                error_code="APPLY_CONFIGURATION_UNAVAILABLE",
            )

        if self._samna is None:
            raise SpeckSdkNotAvailableError("samna module is not available for configuration.")

        try:
            configuration_module = self._samna.speck2f.configuration
            config = configuration_module.SpeckConfiguration()
            config.from_json(self._config_payload.configuration_json)
            apply_configuration(config)
        except Exception as exc:  # noqa: BLE001
            raise SpeckDeviceMappingError(
                f"Failed to apply Speck configuration via samna: {exc}",
                error_code="CONFIGURATION_APPLY_FAILED",
            ) from exc

    def _get_model(self) -> Any:
        """Return the opened board model."""
        if self._device is None:
            raise SpeckConfigurationError(
                "Speck device is not open.",
                error_code="DEVICE_NOT_OPEN",
            )

        get_model = getattr(self._device, "get_model", None)
        if not callable(get_model):
            raise SpeckDeviceMappingError(
                "Opened Speck device does not expose get_model().",
                error_code="MODEL_ACCESS_UNAVAILABLE",
            )
        return get_model()

    def _ensure_event_io(self) -> None:
        """Create the Samna source/sink nodes used during inference."""
        if self._event_source is not None and self._event_sink is not None:
            return

        if self._samna is None or not hasattr(self._samna, "graph"):
            raise SpeckSdkNotAvailableError("samna.graph is not available on this host.")

        model = self._get_model()
        graph_module = self._samna.graph
        source_to = getattr(graph_module, "source_to", None)
        sink_from = getattr(graph_module, "sink_from", None)
        get_sink_node = getattr(model, "get_sink_node", None)
        get_source_node = getattr(model, "get_source_node", None)
        if not callable(source_to) or not callable(sink_from):
            raise SpeckSdkNotAvailableError("samna.graph source/sink helpers are unavailable.")
        if not callable(get_sink_node) or not callable(get_source_node):
            raise SpeckDeviceMappingError(
                "Opened Speck model does not expose sink/source nodes.",
                error_code="EVENT_IO_UNAVAILABLE",
            )

        self._event_source = source_to(get_sink_node())
        self._event_sink = sink_from(get_source_node())

    def _build_input_events(self, inputs: list[float]) -> list[Any]:
        """Encode numeric inputs as Samna Speck input spikes."""
        if self._samna is None or self._config_payload is None:
            raise SpeckSdkNotAvailableError("samna Speck event types are unavailable.")

        spike_type = self._samna.speck2f.event.Spike
        input_layer = self._config_payload.input_spike_layer
        events: list[Any] = []
        timestamp = 0
        for feature_index, value in enumerate(inputs):
            amplitude = float(value)
            if amplitude <= 0:
                continue

            spike_count = min(32, max(1, round(amplitude)))
            for _ in range(spike_count):
                spike_event = spike_type()
                if hasattr(spike_event, "layer"):
                    spike_event.layer = input_layer
                if hasattr(spike_event, "feature"):
                    spike_event.feature = feature_index % 16
                if hasattr(spike_event, "x"):
                    spike_event.x = feature_index % 128
                if hasattr(spike_event, "y"):
                    spike_event.y = (feature_index // 128) % 128
                if hasattr(spike_event, "timestamp"):
                    spike_event.timestamp = timestamp
                events.append(spike_event)
                timestamp += 1
        return events

    def _collect_output_events(self) -> list[Any]:
        """Read any currently buffered events from the output sink node."""
        if self._event_sink is None:
            return []

        get_events = getattr(self._event_sink, "get_events", None)
        if not callable(get_events):
            raise SpeckDeviceMappingError(
                "Speck output sink does not expose get_events().",
                error_code="EVENT_SINK_UNAVAILABLE",
            )
        return list(get_events())

    def _decode_output_events(self, events: list[Any]) -> dict[str, Any]:
        """Reduce Samna output events into a simple numeric output vector."""
        output_size = 0
        if self._mapped_network is not None:
            populations = self._mapped_network.get("populations", [])
            if populations:
                output_size = int(populations[-1].get("size", 0) or 0)
        output_size = max(1, output_size)

        outputs = [0.0] * output_size
        telemetry: dict[str, Any] = {
            "runtime_target": self.runtime_target,
            "event_count": len(events),
            "event_types": {},
        }

        for event in events:
            event_type = event.__class__.__name__
            telemetry["event_types"][event_type] = telemetry["event_types"].get(event_type, 0) + 1

            index = getattr(event, "index", None)
            if isinstance(index, int) and 0 <= index < output_size:
                outputs[index] += 1.0
                continue

            if event_type == "ReadoutValue":
                feature = getattr(event, "feature", None)
                value = getattr(event, "value", None)
                if isinstance(feature, int) and 0 <= feature < output_size:
                    outputs[feature] += float(value if isinstance(value, (int, float)) else 1.0)
                continue

            feature = getattr(event, "feature", None)
            layer = getattr(event, "layer", None)
            if (
                event_type == "Spike"
                and isinstance(feature, int)
                and 0 <= feature < output_size
                and isinstance(layer, int)
                and layer >= 0
            ):
                outputs[feature] += 1.0

        return {"outputs": outputs, "telemetry": telemetry}

    def map_to_device(self) -> None:
        """Open the first discoverable Speck device through samna."""
        if self.state == SpeckState.UNINITIALIZED:
            raise SpeckConfigurationError(
                "Cannot map to device before model is constructed",
                error_code="MAP_BEFORE_CONSTRUCT",
            )
        if self._artifact_bytes is None:
            raise SpeckDeviceMappingError(
                "Cannot map Speck hardware before loading deployment artifacts.",
                error_code="ARTIFACT_BEFORE_MAP",
            )
        if self._compile_plan is None:
            raise SpeckDeviceMappingError(
                "Cannot map Speck hardware before loading a compile plan.",
                error_code="COMPILE_PLAN_NOT_LOADED",
            )
        if not bool(self._compile_plan.get("deployable", False)):
            compiler_issues = self._compile_plan.get("compiler_issues", [])
            raise SpeckDeviceMappingError(
                "Current Speck hardware path cannot deploy this mapped network: "
                f"{compiler_issues or ['unknown_compile_issue']}",
                error_code="UNSUPPORTED_COMPILE_PLAN",
            )

        if self._samna is None or not hasattr(self._samna, "device"):
            raise SpeckSdkNotAvailableError(
                "samna device controller is not available on this host."
            )

        open_device = getattr(self._samna.device, "open_device", None)
        if not callable(open_device):
            raise SpeckSdkNotAvailableError(
                "samna.device.open_device is not available on this host."
            )

        speck_devices = self._discover_devices()
        if not speck_devices:
            raise SpeckDeviceMappingError(
                "No discoverable Speck devices were found by samna.",
                error_code="DEVICE_NOT_FOUND",
            )

        selected_device = speck_devices[0]
        try:
            self._device = open_device(selected_device)
            self._apply_configuration_to_device()
        except Exception as exc:  # noqa: BLE001
            raise SpeckDeviceMappingError(
                f"Failed to open/configure Speck device via samna: {exc}",
            ) from exc

        self._device_info = self._describe_device(selected_device)
        self.state = SpeckState.MAPPED
        logger.info("Speck device opened via samna: %s", self._device_info)

    def run_inference(self, inputs: list[float]) -> dict[str, Any]:
        """Run artifact-backed event I/O on the opened Speck device."""
        if self.state not in (SpeckState.MAPPED, SpeckState.RUNNING):
            raise SpeckConfigurationError(
                "Cannot run inference before model is mapped",
                error_code="INFERENCE_BEFORE_MAP",
            )

        if not inputs:
            raise SpeckInferenceError(
                "Input buffer is empty",
                error_code="INFERENCE_EMPTY_INPUT",
            )

        self._ensure_event_io()
        if self._event_source is None:
            raise SpeckInferenceError(
                "Speck input event source is unavailable.",
                error_code="EVENT_SOURCE_UNAVAILABLE",
            )

        write = getattr(self._event_source, "write", None)
        if not callable(write):
            raise SpeckInferenceError(
                "Speck input event source does not expose write().",
                error_code="EVENT_SOURCE_UNAVAILABLE",
            )

        input_events = self._build_input_events(inputs)
        if not input_events:
            raise SpeckInferenceError(
                "Input buffer does not contain any positive spikes to send.",
                error_code="INFERENCE_EMPTY_SPIKE_STREAM",
            )

        self.state = SpeckState.RUNNING
        start = time.monotonic()
        try:
            self._collect_output_events()
            write(input_events)
            time.sleep(0.01)
            output_events = self._collect_output_events()
        except Exception as exc:  # noqa: BLE001
            self.state = SpeckState.MAPPED
            raise SpeckInferenceError(
                f"Failed to execute Speck event I/O via samna: {exc}",
                error_code="HARDWARE_EVENT_IO_FAILED",
            ) from exc

        result = self._decode_output_events(output_events)
        result["timesteps"] = 1
        result["execution_time_us"] = (time.monotonic() - start) * 1_000_000
        self.state = SpeckState.MAPPED
        return result

    def reset(self) -> None:
        """Return to CONSTRUCTED state and close any opened device handle."""
        if self.state == SpeckState.UNINITIALIZED:
            raise SpeckConfigurationError(
                "Cannot reset — model was never constructed",
                error_code="RESET_BEFORE_CONSTRUCT",
            )

        close_device = None
        if self._samna is not None and hasattr(self._samna, "device"):
            close_device = getattr(self._samna.device, "close_device", None)

        if self._device is not None and callable(close_device):
            try:
                close_device(self._device)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Failed to close Speck device during reset: %s", exc)

        self._device = None
        self._artifact_bytes = None
        self._artifact_manifest = None
        self._compile_plan = None
        self._config_payload = None
        self._event_source = None
        self._event_sink = None
        self.state = SpeckState.CONSTRUCTED

    @property
    def current_state(self) -> str:
        """Return the current state as a lowercase string."""
        return self.state.name.lower()
