"""Akida Backend for Neurochip.

Manages building Akida SDK models from shared mapped network representations,
mapping to hardware/simulator, running inference, and generating truthful
deployment packages.

When the ``akida`` library is not installed (CI, local dev), all operations
are transparently delegated to :class:`AkidaSimulator`.
"""

from __future__ import annotations

import hashlib
import importlib.metadata
import importlib.util
import io
import json
import logging
import struct
import sys
import zipfile
from datetime import datetime
from typing import Any, Literal

from ..._compat import UTC
from ...contracts.akida_runtime_contract import (
    MAX_WEIGHT,
    AkidaEnvironmentChecks,
    AkidaMappedNetworkPayloadContract,
    AkidaRuntimeStatusContract,
)
from ...contracts.deployment_contracts import DeploymentManifest, TargetDevice
from ..schemas.estimation import NetworkInput
from .akida_errors import (
    AkidaConfigurationError,
    AkidaDeviceMappingError,
    AkidaInferenceError,
    AkidaModelConstructionError,
    AkidaSdkNotAvailableError,
)
from .akida_simulator import AkidaSimulator, AkidaState

logger = logging.getLogger(__name__)

try:
    import akida  # type: ignore[import-not-found]

    AKIDA_AVAILABLE = True
except ImportError:
    akida = None
    AKIDA_AVAILABLE = False
    logger.info("akida library not available — using AkidaSimulator fallback.")


SUPPORTED_AKIDA_PLATFORMS = frozenset({"linux", "windows"})
SUPPORTED_AKIDA_PYTHON_MIN = (3, 10)
SUPPORTED_AKIDA_PYTHON_MAX_EXCLUSIVE = (3, 13)


def _current_platform_key() -> str:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform.startswith(("win32", "cygwin")):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return sys.platform


def _current_python_version_tuple() -> tuple[int, int, int]:
    info = sys.version_info
    return info.major, info.minor, info.micro


def _module_available(module_name: str) -> bool:
    return importlib.util.find_spec(module_name) is not None


def _installed_akida_version() -> str:
    """The installed Akida SDK version, or "" if it cannot be determined.

    Read from package metadata rather than by importing `akida`, so collecting
    diagnostics never touches the device or pays the import cost.
    """
    try:
        return importlib.metadata.version("akida")
    except Exception:  # noqa: BLE001 - absent or unreadable metadata is not an error here
        return ""


def _collect_akida_environment_checks() -> AkidaEnvironmentChecks:
    platform_key = _current_platform_key()
    python_version = _current_python_version_tuple()
    host_supported = platform_key in SUPPORTED_AKIDA_PLATFORMS
    python_supported = (
        SUPPORTED_AKIDA_PYTHON_MIN <= python_version < SUPPORTED_AKIDA_PYTHON_MAX_EXCLUSIVE
    )
    recommended_runtime: Literal["local_sdk", "remote_sdk", "simulator_only"]

    if not host_supported:
        recommended_runtime = "simulator_only"
    elif python_supported:
        recommended_runtime = "local_sdk"
    else:
        recommended_runtime = "remote_sdk"

    return AkidaEnvironmentChecks(
        host_supported=host_supported,
        python_supported=python_supported,
        tensorflow_available=_module_available("tensorflow"),
        cnn2snn_available=_module_available("cnn2snn"),
        akida_models_available=_module_available("akida_models"),
        recommended_runtime=recommended_runtime,
        akida_version=_installed_akida_version(),
    )


def collect_akida_environment_checks() -> dict[str, Any]:
    """Return the local Akida environment diagnostics as JSON-ready data."""
    return _collect_akida_environment_checks().model_dump()


def _environment_sdk_issues(
    checks: AkidaEnvironmentChecks,
    *,
    sdk_available: bool,
    last_sdk_issue: str | None,
) -> list[str]:
    issues: list[str] = []
    if not checks.host_supported:
        issues.append("unsupported_os")
    if not checks.python_supported:
        issues.append("unsupported_python")
    if not checks.tensorflow_available:
        issues.append("tensorflow_missing")
    if not checks.cnn2snn_available:
        issues.append("cnn2snn_missing")
    if not checks.akida_models_available:
        issues.append("akida_models_missing")
    if not sdk_available:
        issues.append("sdk_not_available")
    if last_sdk_issue == "device_mapping_failure":
        issues.append("device_mapping_failure")
    if last_sdk_issue == "model_construction_failure":
        issues.append("model_construction_failure")
    return issues


def _sdk_issue_detail(
    checks: AkidaEnvironmentChecks,
    *,
    sdk_available: bool,
    last_sdk_issue: str | None,
    last_sdk_issue_detail: str | None,
) -> str | None:
    if last_sdk_issue == "model_construction_failure" and last_sdk_issue_detail:
        return last_sdk_issue_detail

    platform_key = _current_platform_key()
    python_version = ".".join(str(part) for part in _current_python_version_tuple())
    if not checks.host_supported:
        return (
            "Akida SDK installation is only supported on Linux or Windows. "
            f"This Neurochip host is running on {platform_key}; use the local "
            "simulator or a remote Neurochip host for SDK verification."
        )
    if not checks.python_supported:
        return (
            "Akida SDK installation requires Python 3.10 to 3.12. "
            f"This Neurochip backend is running Python {python_version}; use "
            "a Linux or Windows Neurochip host running Python 3.10-3.12 for "
            "SDK verification."
        )
    if not checks.tensorflow_available:
        return "TensorFlow 2.19 is required for the full Akida MetaTF workflow."
    if not checks.cnn2snn_available:
        return "cnn2snn is not installed; CNN-to-SNN conversion is unavailable."
    if not checks.akida_models_available:
        return "akida-models is not installed; BrainChip model-zoo workflows are unavailable."
    if not sdk_available:
        return "Akida Python SDK is not installed; install akida==2.19.1 to verify deployability."
    return last_sdk_issue_detail


def _probe_runtime_target() -> tuple[str, str | None, str | None]:
    """Inspect the current Akida runtime target without requiring a mapped model."""
    if not AKIDA_AVAILABLE:
        return "software_fallback", AkidaSimulator.__name__, None

    try:
        _device, runtime_target, device_info = _get_target_device()
    except AkidaSdkNotAvailableError as exc:
        return "software_fallback", AkidaSimulator.__name__, str(exc)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Unable to probe Akida runtime target: %s", exc)
        return "unknown", None, str(exc)
    return runtime_target, device_info, None


def build_akida_runtime_status(
    *,
    state: str,
    model_summary: dict[str, Any] | None = None,
    runtime_target: str | None = None,
    device_info: str | None = None,
    last_sdk_issue: str | None = None,
    last_sdk_issue_detail: str | None = None,
    sdk_available: bool | None = None,
) -> dict[str, Any]:
    """Build a truthful Akida runtime status payload for routers and services."""
    resolved_sdk_available = AKIDA_AVAILABLE if sdk_available is None else sdk_available
    environment_checks = _collect_akida_environment_checks()
    resolved_runtime_target = runtime_target or "unknown"
    resolved_device_info = device_info
    probe_issue_detail = last_sdk_issue_detail

    if resolved_runtime_target == "unknown" and last_sdk_issue != "device_mapping_failure":
        (
            resolved_runtime_target,
            probed_device_info,
            runtime_probe_issue_detail,
        ) = _probe_runtime_target()
        if resolved_device_info is None:
            resolved_device_info = probed_device_info
        if probe_issue_detail is None:
            probe_issue_detail = runtime_probe_issue_detail

    if not resolved_sdk_available:
        sdk_status = "not_available"
    elif last_sdk_issue == "device_mapping_failure":
        sdk_status = "mapping_failed"
    elif state in {AkidaState.MAPPED.name.lower(), AkidaState.RUNNING.name.lower()}:
        sdk_status = "deployable"
    else:
        sdk_status = "unknown"

    status = AkidaRuntimeStatusContract(
        sdk_available=resolved_sdk_available,
        sdk_status=sdk_status,
        sdk_issues=_environment_sdk_issues(
            environment_checks,
            sdk_available=resolved_sdk_available,
            last_sdk_issue=last_sdk_issue,
        ),
        state=state,
        model_summary=model_summary,
        runtime_target=resolved_runtime_target,
        device_info=resolved_device_info,
        sdk_issue_detail=_sdk_issue_detail(
            environment_checks,
            sdk_available=resolved_sdk_available,
            last_sdk_issue=last_sdk_issue,
            last_sdk_issue_detail=probe_issue_detail,
        ),
        environment_checks=environment_checks,
    )
    return status.model_dump()


def _discover_akida_devices() -> list[Any]:
    """Return the physical Akida devices attached to this host.

    Wraps ``akida.devices()`` so hardware auto-detection can enumerate every
    installed NSoC device without requiring a preconfigured target. Returns an
    empty list when the Akida SDK is not installed or when no physical device
    is present; it never falls back to the AKD1000 simulator because a
    simulator is not hardware a launcher could register as a target.
    """
    if akida is None:
        logger.info("akida SDK not installed — no Akida devices to enumerate.")
        return []
    try:
        devices = akida.devices()
    except Exception as exc:  # noqa: BLE001 - degrade gracefully across SDK versions
        logger.warning("Unable to enumerate Akida devices: %s", exc)
        return []
    if not devices:
        return []
    logger.info("Discovered %s physical Akida device(s)", len(list(devices)))
    return list(devices)


def _get_target_device() -> tuple[Any, str, str]:
    """Return the Akida target object plus runtime-target metadata."""
    if akida is None:
        raise AkidaSdkNotAvailableError("Akida Python SDK is not installed.")

    available_devices = _discover_akida_devices()
    if available_devices:
        device = available_devices[0]
        logger.info("Using physical Akida device: %s", device)
        return device, "hardware", str(device)

    logger.info("No physical Akida devices found. Falling back to AKD1000 Simulator.")
    simulator = akida.AKD1000()
    return simulator, "akd1000_simulator", simulator.__class__.__name__


def _quantize_weight(weight: float, bit_width: int) -> int:
    """Quantize a float weight to a fixed-point integer at the given bit-width."""
    max_int = (2 ** (bit_width - 1)) - 1
    clamped = max(-MAX_WEIGHT, min(MAX_WEIGHT, weight))
    if MAX_WEIGHT > 0:
        return int(round(clamped * max_int / MAX_WEIGHT))
    return 0


def _vector_input_shape(population_size: int) -> tuple[int, int, int]:
    """Represent a 1D CNL population as Akida's required 3D input shape."""
    return (1, 1, population_size)


def _normalise_vector_inputs(inputs: list[float], input_size: int) -> list[float]:
    """Pad or truncate caller inputs to the first mapped population size."""
    normalised = list(inputs[:input_size])
    while len(normalised) < input_size:
        normalised.append(0.0)
    return normalised


def _configure_layer_threshold(layer: Any, lif_threshold: float, units: int) -> None:
    """Apply a mapped LIF population's threshold to an Akida layer's on-chip activation.

    The installed ``akida`` SDK version may not expose a settable ``threshold``
    variable on this layer type; that is not an error, so any failure here is
    logged and the layer is left on its default activation rather than
    aborting model construction.
    """
    try:
        layer.set_variable("threshold", [lif_threshold] * units)
    except Exception as exc:  # noqa: BLE001 - degrade gracefully across SDK versions
        logger.warning(
            "Akida layer %r does not support threshold configuration on this "
            "SDK version (%s); using default on-chip activation.",
            getattr(layer, "name", "?"),
            exc,
        )


class AkidaBackend:
    """Hardware-aware Akida runtime backend.

    Lifecycle:  ``__init__`` -> ``construct_model`` -> ``map_to_device``
    -> ``run_inference`` (repeatable).  Call ``reset`` to return to the
    CONSTRUCTED state.

    When ``akida`` is not installed every call is forwarded to
    :class:`AkidaSimulator`.
    """

    def __init__(self) -> None:
        self._simulator: AkidaSimulator | None = None
        self.state: AkidaState = AkidaState.UNINITIALIZED
        self._mapped_network: dict[str, Any] | None = None
        self._model: Any = None  # akida.Model when SDK available
        self._device: Any = None
        self._bit_width: int = 4
        self._runtime_target: str = "unknown"
        self._device_info: str | None = None
        self._last_sdk_issue: str | None = None
        self._last_sdk_issue_detail: str | None = None

        if not AKIDA_AVAILABLE:
            self._simulator = AkidaSimulator()

    # ------------------------------------------------------------------
    # Model construction
    # ------------------------------------------------------------------

    def construct_model(
        self,
        mapped_network: dict[str, Any],
        bit_width: int = 4,
    ) -> None:
        """Build an Akida model from an AkidaMappedNetwork-shaped dict.

        Defense-in-depth: validates the payload against Neurochip-side
        Akida limits before constructing.

        Args:
            mapped_network: Dict matching the AkidaMappedNetwork schema
                (``populations``, ``connections``, ``akida_version``, etc.).
            bit_width: Weight quantization bit-width (1, 2, or 4).

        Raises:
            AkidaConfigurationError: If the mapped network is invalid.
            AkidaModelConstructionError: If SDK model construction fails.
        """
        self.prepare_mapped_network(mapped_network, bit_width=bit_width)

        if self._simulator is not None:
            self._simulator.construct_model(mapped_network)
            self.state = AkidaState.CONSTRUCTED
            return

        # SDK path: build real Akida model
        populations = mapped_network.get("populations", [])
        connections = mapped_network.get("connections", [])

        if not populations:
            raise AkidaConfigurationError(
                "Cannot construct model: populations list is empty",
                error_code="CONSTRUCT_EMPTY_POPULATIONS",
            )

        try:
            model = akida.Model()

            # First population -> InputData layer
            first_pop = populations[0]
            input_layer = akida.InputData(
                input_shape=_vector_input_shape(first_pop["size"]),
                input_bits=bit_width,
                name=first_pop["id"],
            )
            model.add(input_layer)

            population_by_id = {pop["id"]: pop for pop in populations}

            # Each connection -> FullyConnected layer (named after target pop)
            for conn in connections:
                layer = akida.FullyConnected(
                    name=conn["target"],
                    units=conn["units"],
                    weights_bits=bit_width,
                )
                model.add(layer)

                target_population = population_by_id.get(conn["target"], {})
                lif_threshold = target_population.get("attributes", {}).get("lif_threshold")
                if lif_threshold is not None:
                    _configure_layer_threshold(layer, lif_threshold, conn["units"])

            self._model = model
        except Exception as exc:
            raise AkidaModelConstructionError(
                f"Akida SDK model construction failed: {exc}",
            ) from exc

        self.state = AkidaState.CONSTRUCTED
        logger.info(
            "Model constructed: %d populations, %d connections",
            len(populations),
            len(connections),
        )

    def prepare_mapped_network(
        self,
        mapped_network: dict[str, Any],
        *,
        bit_width: int = 4,
    ) -> None:
        """Validate and store a mapped payload for scaffold generation.

        This keeps scaffold export independent from whether the local Akida SDK
        can construct or map the model.
        """
        try:
            AkidaMappedNetworkPayloadContract(
                akida_version=mapped_network.get("akida_version", "akida1"),
                populations=mapped_network.get("populations", []),
                connections=mapped_network.get("connections", []),
            )
        except Exception as exc:
            raise AkidaConfigurationError(
                f"Mapped network payload validation failed: {exc}",
                error_code="PAYLOAD_VALIDATION_FAILED",
            ) from exc

        self._mapped_network = dict(mapped_network)
        self._bit_width = bit_width
        self._runtime_target = "unknown"
        self._device_info = None
        self._last_sdk_issue = None
        self._last_sdk_issue_detail = None
        self._model = None
        self._device = None
        self.state = AkidaState.CONSTRUCTED
        if self._simulator is not None:
            self._simulator.construct_model(mapped_network)

    # ------------------------------------------------------------------
    # Device mapping
    # ------------------------------------------------------------------

    def map_to_device(self) -> None:
        """Map the constructed model to an Akida device or simulator.

        Raises:
            AkidaConfigurationError: If called before construct_model.
            AkidaDeviceMappingError: If device mapping fails.
        """
        if self.state == AkidaState.UNINITIALIZED:
            raise AkidaConfigurationError(
                "Cannot map to device before model is constructed",
                error_code="MAP_BEFORE_CONSTRUCT",
            )

        if self._simulator is not None:
            self._simulator.map_to_device()
            self._runtime_target = "software_fallback"
            self._device_info = self._simulator.__class__.__name__
            self.state = AkidaState.MAPPED
            return

        try:
            self._device, self._runtime_target, self._device_info = _get_target_device()
            self._model.map(self._device)
        except AkidaSdkNotAvailableError:
            raise
        except Exception as exc:
            self._runtime_target = "unknown"
            self._device_info = None
            self._last_sdk_issue = "device_mapping_failure"
            self._last_sdk_issue_detail = str(exc)
            raise AkidaDeviceMappingError(
                f"Failed to map model to Akida device: {exc}",
            ) from exc

        self.state = AkidaState.MAPPED
        logger.info("Model mapped to Akida device")

    # ------------------------------------------------------------------
    # Inference
    # ------------------------------------------------------------------

    def run_inference(self, inputs: list[float]) -> dict[str, Any]:
        """Run inference on the mapped model.

        Args:
            inputs: Input values for the first population.

        Returns:
            Dict with ``outputs`` and ``telemetry``.

        Raises:
            AkidaConfigurationError: If not in MAPPED state.
            AkidaInferenceError: On inference failure.
        """
        if self.state not in (AkidaState.MAPPED, AkidaState.RUNNING):
            raise AkidaConfigurationError(
                "Cannot run inference before model is mapped",
                error_code="INFERENCE_BEFORE_MAP",
            )

        if self._simulator is not None:
            result = self._simulator.run_inference(inputs)
            self.state = AkidaState.MAPPED
            return result

        try:
            import numpy as np

            self.state = AkidaState.RUNNING
            input_size = 1
            if self._mapped_network is not None:
                populations = self._mapped_network.get("populations", [])
                if populations:
                    input_size = populations[0].get("size", 1)
            normalised_inputs = _normalise_vector_inputs(inputs, input_size)
            input_data = np.array(normalised_inputs, dtype=np.uint8).reshape(
                1,
                *_vector_input_shape(input_size),
            )
            outputs = self._model.run(input_data)
            output_list = outputs.tolist() if hasattr(outputs, "tolist") else list(outputs)

            telemetry: dict[str, Any] = {}
            if hasattr(self._model, "statistics"):
                stats = self._model.statistics
                telemetry["fps"] = getattr(stats, "fps", None)
                telemetry["power"] = getattr(stats, "power", None)

            self.state = AkidaState.MAPPED
            return {"outputs": output_list, "telemetry": telemetry}
        except Exception as exc:
            self.state = AkidaState.MAPPED
            raise AkidaInferenceError(
                f"Akida inference failed: {exc}",
            ) from exc

    # ------------------------------------------------------------------
    # Package generation
    # ------------------------------------------------------------------

    def generate_package(self, bit_width: int | None = None) -> bytes:
        """Generate a truthful deployment package as a zip archive.

        Can be called in CONSTRUCTED (scaffold-only) or MAPPED (full SDK)
        state.  The manifest reflects actual network metadata, not mock data.

        Args:
            bit_width: Override weight bit-width (defaults to construction value).

        Returns:
            Bytes of the zip archive.

        Raises:
            AkidaConfigurationError: If called before construct_model.
        """
        if self.state == AkidaState.UNINITIALIZED:
            raise AkidaConfigurationError(
                "Cannot generate package before model is constructed",
                error_code="PACKAGE_BEFORE_CONSTRUCT",
            )

        if bit_width is None:
            bit_width = self._bit_width

        mapped = self._mapped_network or {}
        populations = mapped.get("populations", [])
        connections = mapped.get("connections", [])
        network_summary = mapped.get("network_summary", {})
        akida_version = mapped.get("akida_version", "akida1")
        topology_verdict = mapped.get("topology_verdict", "unknown")
        timestamp = datetime.now(UTC).isoformat()

        # Build truthful model config
        model_config = {
            "network_name": "SNN Network",
            "timestamp": timestamp,
            "akida_version": akida_version,
            "topology_verdict": topology_verdict,
            "sdk_available": AKIDA_AVAILABLE,
            "sdk_mapped": self.state == AkidaState.MAPPED,
            "bit_width": bit_width,
            "populations": [
                {
                    "id": p.get("id"),
                    "size": p.get("size"),
                    "role": p.get("role"),
                }
                for p in populations
            ],
            "connections": [
                {
                    "source": c.get("source"),
                    "target": c.get("target"),
                    "units": c.get("units"),
                    "weight": c.get("weight"),
                    "block_type": c.get("block_type"),
                }
                for c in connections
            ],
            "network_summary": network_summary,
        }

        # SDK model summary if available
        if AKIDA_AVAILABLE and self._model is not None:
            try:
                model_config["sdk_model_summary"] = str(self._model.summary())
            except Exception:
                model_config["sdk_model_summary"] = None

        # Build real quantized weights
        weights_data: list[int] = []
        for conn in connections:
            weight = conn.get("weight")
            units = conn.get("units", 1)
            if weight is not None:
                q = _quantize_weight(weight, bit_width)
                weights_data.extend([q] * units)
            else:
                weights_data.extend([0] * units)

        # Pack weights based on bit-width
        if bit_width <= 8:
            weights_bin = struct.pack(
                f"<{len(weights_data)}b", *[max(-128, min(127, w)) for w in weights_data]
            )
        else:
            weights_bin = struct.pack(
                f"<{len(weights_data)}h", *[max(-32768, min(32767, w)) for w in weights_data]
            )

        # README
        total_neurons = sum(p.get("size", 0) for p in populations)
        readme = (
            f"# Neurochip Akida Deployment Package\n\n"
            f"Auto-generated on {timestamp}\n\n"
            f"## Target\n"
            f"- Device: BrainChip Akida ({akida_version})\n"
            f"- SDK available: {AKIDA_AVAILABLE}\n"
            f"- SDK mapped: {self.state == AkidaState.MAPPED}\n\n"
            f"## Network Summary\n"
            f"- Populations: {len(populations)}\n"
            f"- Connections: {len(connections)}\n"
            f"- Total neurons: {total_neurons}\n"
            f"- Weight bit-width: {bit_width}-bit\n"
            f"- Topology: {topology_verdict}\n"
        )

        # Truthful manifest
        config_json = json.dumps(model_config, indent=2)
        checksum = hashlib.sha256(config_json.encode() + weights_bin).hexdigest()

        # Core count: approximate as number of populations that need NPs
        core_count = max(1, min(len(populations), 80))

        manifest = DeploymentManifest(
            target_device=TargetDevice.AKIDA,
            core_count=core_count,
            firmware_version="1.2.0",
            checksum_sha256=checksum,
        )

        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("akida_deploy/model.json", config_json)
            zf.writestr("akida_deploy/weights.bin", weights_bin)
            zf.writestr("akida_deploy/manifest.json", manifest.model_dump_json(indent=2))
            zf.writestr("akida_deploy/README.md", readme)

        logger.info(
            "Package generated: %d populations, %d bytes",
            len(populations),
            buffer.tell(),
        )
        return buffer.getvalue()

    # ------------------------------------------------------------------
    # Status and verification
    # ------------------------------------------------------------------

    def get_sdk_status(self) -> dict[str, Any]:
        """Return current SDK availability and model mapping status."""
        model_summary = None
        if self._mapped_network:
            model_summary = self._mapped_network.get("network_summary")

        return build_akida_runtime_status(
            state=self.current_state,
            model_summary=model_summary,
            runtime_target=self._runtime_target,
            device_info=self._device_info,
            last_sdk_issue=self._last_sdk_issue,
            last_sdk_issue_detail=self._last_sdk_issue_detail,
        )

    # ------------------------------------------------------------------
    # Reset & state
    # ------------------------------------------------------------------

    def reset(self) -> None:
        """Return to CONSTRUCTED state, clearing device mapping.

        Raises:
            AkidaConfigurationError: If model was never constructed.
        """
        if self.state == AkidaState.UNINITIALIZED:
            raise AkidaConfigurationError(
                "Cannot reset — model was never constructed",
                error_code="RESET_BEFORE_CONSTRUCT",
            )

        if self._simulator is not None:
            self._simulator.reset()
            self.state = AkidaState.CONSTRUCTED
            return

        self._device = None
        self.state = AkidaState.CONSTRUCTED
        logger.info("Backend reset to CONSTRUCTED state")

    @property
    def current_state(self) -> str:
        """Return the current lifecycle state as a lowercase string."""
        if self._simulator is not None:
            return self._simulator.current_state
        return self.state.name.lower()


def generate_akida_package(network: NetworkInput, bit_width: int = 4) -> bytes:
    """Generate a truthful Akida package from a high-level network payload."""
    backend = AkidaBackend()
    mapped_network = {
        "akida_version": "akida1",
        "populations": network.populations,
        "connections": network.connections,
        "network_summary": {
            "num_neurons": network.num_neurons,
            "num_synapses": network.num_synapses,
            "network_depth": network.network_depth,
            "weight_bit_width": bit_width,
        },
    }
    backend.construct_model(mapped_network, bit_width=bit_width)
    backend.map_to_device()
    return backend.generate_package(bit_width=bit_width)
