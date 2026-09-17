"""PYNQ backend with simulator fallback and isolated-interpreter support."""

from __future__ import annotations

import importlib
import importlib.util
import json
import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Any

from ...contracts.pynq_runtime_artifact_contract import (
    DEFAULT_REGISTER_MAP,
    DEFAULT_WEIGHT_LAYOUT,
    DMA_IP_NAME,
    MAX_SYNAPSES,
    SNN_IP_NAME,
    PynqOverlayManifestContract,
)
from .pynq_errors import (
    ConfigurationError,
    DmaTransferError,
    MmioWriteError,
    OverlayLoadError,
    PynqRuntimeError,
)
from .pynq_overlay_assets import (
    DEFAULT_PYNQ_BITSTREAM_NAME,
    OverlayAssetStatus,
    inspect_overlay_assets,
    resolve_bitstream_path,
)
from .pynq_overlay_manifest import load_overlay_manifest_file, load_runtime_overlay_manifest
from .pynq_simulator import PynqSimulator, PynqState

logger = logging.getLogger(__name__)

PYNQ_RUNTIME_PYTHON_ENV = "NEUROCHIP_PYNQ_PYTHON"
PYNQ_DEVICE_PROBE_TIMEOUT_ENV = "NEUROCHIP_PYNQ_DEVICE_PROBE_TIMEOUT_SECONDS"
PYNQ_DMA_TIMEOUT_ENV = "NEUROCHIP_PYNQ_DMA_TIMEOUT_SECONDS"
PYNQ_AVAILABLE = importlib.util.find_spec("pynq") is not None
_DMA_TIMEOUT_DEFAULT_S = 30.0
_DMA_TIMEOUT_BOUNDS_S = (5.0, 300.0)
_DMA_POLL_INTERVAL_S = 0.01
_DEFAULT_DEVICE_PROBE_TIMEOUT_S = 20.0
_DEVICE_PROBE_TIMEOUT_BOUNDS_S = (1.0, 120.0)
_DEFAULT_DEPLOY_TIMEOUT_S = 120.0
_DEPLOY_TIMEOUT_BOUNDS_S = (10.0, 600.0)
PYNQ_DEPLOY_TIMEOUT_ENV = "NEUROCHIP_PYNQ_DEPLOY_TIMEOUT_SECONDS"


def _configured_pynq_python() -> str | None:
    raw = os.getenv(PYNQ_RUNTIME_PYTHON_ENV, "").strip()
    return raw or None


def _resolve_device_probe_timeout() -> float:
    raw = os.getenv(PYNQ_DEVICE_PROBE_TIMEOUT_ENV, "").strip()
    if not raw:
        return _DEFAULT_DEVICE_PROBE_TIMEOUT_S
    try:
        parsed = float(raw)
    except ValueError:
        return _DEFAULT_DEVICE_PROBE_TIMEOUT_S
    lower, upper = _DEVICE_PROBE_TIMEOUT_BOUNDS_S
    return max(lower, min(upper, parsed))


def _resolve_deploy_timeout() -> float:
    raw = os.getenv(PYNQ_DEPLOY_TIMEOUT_ENV, "").strip()
    if not raw:
        return _DEFAULT_DEPLOY_TIMEOUT_S
    try:
        parsed = float(raw)
    except ValueError:
        return _DEFAULT_DEPLOY_TIMEOUT_S
    lower, upper = _DEPLOY_TIMEOUT_BOUNDS_S
    return max(lower, min(upper, parsed))


def _resolve_dma_timeout() -> float:
    raw = os.getenv(PYNQ_DMA_TIMEOUT_ENV, "").strip()
    if not raw:
        return _DMA_TIMEOUT_DEFAULT_S
    try:
        parsed = float(raw)
    except ValueError:
        return _DMA_TIMEOUT_DEFAULT_S
    lower, upper = _DMA_TIMEOUT_BOUNDS_S
    return max(lower, min(upper, parsed))


def _dma_channel_idle(channel: Any) -> bool | None:
    idle_attr = getattr(channel, "idle", None)
    if idle_attr is None:
        return None
    if callable(idle_attr):
        idle_value = idle_attr()
    else:
        idle_value = idle_attr
    return idle_value if isinstance(idle_value, bool) else None


def _wait_for_dma_channel(channel: Any, *, timeout_s: float) -> None:
    wait = getattr(channel, "wait", None)
    if wait is None:
        raise AttributeError("DMA channel is missing wait()")

    try:
        wait(timeout=timeout_s)
        return
    except TypeError as exc:
        if "timeout" not in str(exc):
            raise

    if _dma_channel_idle(channel) is None:
        wait()
        return

    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if _dma_channel_idle(channel) is True:
            return
        time.sleep(_DMA_POLL_INTERVAL_S)

    if _dma_channel_idle(channel) is True:
        return
    raise TimeoutError(f"DMA channel did not become idle within {timeout_s:.2f}s")


def _subprocess_runtime_available(python_path: str) -> bool:
    path = Path(python_path)
    if not path.exists():
        return False
    result = subprocess.run(
        [python_path, "-c", "import pynq"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def pynq_runtime_available() -> bool:
    """Return whether a real PYNQ runtime is reachable from this process."""
    configured_python = _configured_pynq_python()
    if configured_python is not None:
        return _subprocess_runtime_available(configured_python)
    return PYNQ_AVAILABLE


def default_runtime_mode() -> str:
    """Return the default runtime mode for the current process."""
    return "hardware" if pynq_runtime_available() else "simulator"


def probe_real_pynq_device_access(timeout_seconds: float | None = None) -> None:
    """Fail fast when the current runtime cannot open a real PYNQ device."""
    resolved_timeout = (
        _resolve_device_probe_timeout()
        if timeout_seconds is None
        else max(
            _DEVICE_PROBE_TIMEOUT_BOUNDS_S[0],
            min(_DEVICE_PROBE_TIMEOUT_BOUNDS_S[1], float(timeout_seconds)),
        )
    )
    configured_python = _configured_pynq_python()
    if configured_python is not None:
        worker = PYNQBackend()
        worker._run_worker(  # noqa: SLF001
            {
                "action": "probe_device",
                "bitstream_path": str(resolve_bitstream_path(DEFAULT_PYNQ_BITSTREAM_NAME)),
                "dma_ip_name": DMA_IP_NAME,
                "snn_ip_name": SNN_IP_NAME,
            },
            timeout=resolved_timeout,
        )
        return

    if not PYNQ_AVAILABLE:
        raise OverlayLoadError(
            "PYNQ runtime is unavailable in this process",
            error_code="PYNQ_RUNTIME_UNAVAILABLE",
        )

    try:
        pynq_module = importlib.import_module("pynq")
        device_type = getattr(pynq_module, "Device")
        devices = device_type.devices
    except OverlayLoadError:
        raise
    except Exception as exc:  # noqa: BLE001
        raise OverlayLoadError(
            f"PYNQ device probe failed: {exc}",
            error_code="PYNQ_DEVICE_PROBE_FAILED",
        ) from exc

    if not devices:
        raise OverlayLoadError(
            "PYNQ device probe failed: no programmable devices were detected",
            error_code="PYNQ_DEVICE_NOT_FOUND",
        )


class PYNQBackend:
    """Hardware-aware PYNQ runtime backend."""

    def __init__(self, bitstream_path: str | None = None) -> None:
        self.requested_bitstream_path = bitstream_path or DEFAULT_PYNQ_BITSTREAM_NAME
        self.bitstream_path = str(resolve_bitstream_path(bitstream_path))
        self._simulator: PynqSimulator | None = None
        self._pynq_python = self._resolve_pynq_python()
        self.overlay_manifest: PynqOverlayManifestContract | None = None

        self.overlay: Any = None
        self.dma: Any = None
        self.snn_ip: Any = None
        try:
            requested_path = Path(self.requested_bitstream_path)
            if requested_path.is_absolute():
                manifest_path = requested_path.with_name("overlay_manifest.json")
                if manifest_path.exists():
                    self.overlay_manifest = load_overlay_manifest_file(manifest_path)
                else:
                    self.overlay_manifest = None
            else:
                self.overlay_manifest = load_runtime_overlay_manifest()
        except Exception as exc:  # noqa: BLE001
            logger.warning("Unable to load runtime overlay manifest: %s", exc)
        self.register_map: dict[str, Any] = (
            self.overlay_manifest.register_map.model_dump()
            if self.overlay_manifest is not None
            else dict(DEFAULT_REGISTER_MAP)
        )
        self.weight_layout: dict[str, Any] = (
            dict(self.overlay_manifest.weight_layout)
            if self.overlay_manifest is not None
            else dict(DEFAULT_WEIGHT_LAYOUT)
        )
        self._dma_ip_name = (
            self.overlay_manifest.dma_ip_name if self.overlay_manifest is not None else DMA_IP_NAME
        )
        self._snn_ip_name = (
            self.overlay_manifest.snn_ip_name if self.overlay_manifest is not None else SNN_IP_NAME
        )
        self.state: PynqState = PynqState.UNLOADED
        self._configured_weights: list[float] = []
        self._configured_config: dict[str, Any] = {}
        self._configured_layers: list[dict[str, Any]] = []

        if self._pynq_python is None and not PYNQ_AVAILABLE:
            self._simulator = PynqSimulator()

    def _resolve_pynq_python(self) -> str | None:
        configured_python = _configured_pynq_python()
        if configured_python is None:
            return None
        if not _subprocess_runtime_available(configured_python):
            logger.warning(
                "Configured PYNQ interpreter %s is unavailable; falling back to simulator mode.",
                configured_python,
            )
            return None
        return configured_python

    def _worker_script_path(self) -> Path:
        return Path(__file__).with_name("pynq_worker.py")

    def _run_worker(
        self,
        payload: dict[str, Any],
        *,
        timeout: float | None = None,
    ) -> dict[str, Any]:
        if self._pynq_python is None:
            raise OverlayLoadError(
                "PYNQ runtime interpreter is unavailable",
                error_code="PYNQ_RUNTIME_UNAVAILABLE",
            )

        try:
            result = subprocess.run(
                [self._pynq_python, str(self._worker_script_path())],
                input=json.dumps(payload),
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired as exc:
            action = str(payload.get("action") or "worker request").replace("_", " ")
            error_code = (
                "PYNQ_DEVICE_PROBE_TIMEOUT"
                if payload.get("action") == "probe_device"
                else "PYNQ_WORKER_TIMEOUT"
            )
            timeout_suffix = f" after {float(timeout):.0f}s" if timeout is not None else ""
            raise OverlayLoadError(
                f"PYNQ {action} timed out{timeout_suffix}",
                error_code=error_code,
            ) from exc
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        if not stdout:
            raise OverlayLoadError(
                stderr or "PYNQ worker produced no response",
                error_code="PYNQ_WORKER_NO_RESPONSE",
            )
        try:
            decoded = json.loads(stdout)
        except json.JSONDecodeError as exc:
            raise OverlayLoadError(
                f"PYNQ worker returned invalid JSON: {stdout}",
                error_code="PYNQ_WORKER_BAD_RESPONSE",
            ) from exc
        if not isinstance(decoded, dict):
            raise OverlayLoadError(
                "PYNQ worker response must be an object",
                error_code="PYNQ_WORKER_BAD_RESPONSE",
            )
        if decoded.get("ok") is True:
            return decoded

        detail = str(decoded.get("detail") or stderr or "PYNQ worker failed")
        error_code = str(decoded.get("error_code") or "PYNQ_WORKER_FAILED")
        if error_code.startswith(("OVERLAY", "HWH", "PYNQ_RUNTIME", "PYNQ_ROOT")):
            raise OverlayLoadError(detail, error_code=error_code)
        if error_code.startswith(("CONFIG", "WORKER_BAD_REQUEST")):
            raise ConfigurationError(detail, error_code=error_code)
        if error_code.startswith(("DMA",)):
            raise DmaTransferError(detail, error_code=error_code)
        if error_code.startswith(("MMIO",)):
            raise MmioWriteError(detail, error_code=error_code)
        raise PynqRuntimeError(detail, error_code=error_code)

    def _validated_overlay_path(self) -> Path:
        asset_status = self.overlay_asset_status
        path = Path(asset_status.bitstream_path)
        if path.suffix != ".bit":
            raise OverlayLoadError(
                f"Bitstream must be a .bit file, got: {path.name}",
                error_code="OVERLAY_INVALID_FORMAT",
            )
        if not asset_status.bitstream_exists:
            raise OverlayLoadError(
                f"Bitstream not found: {path}",
                error_code="OVERLAY_NOT_FOUND",
            )
        hwh_path = Path(asset_status.hwh_path)
        if not asset_status.hwh_exists:
            raise OverlayLoadError(
                f"Hardware handoff file not found: {hwh_path}",
                error_code="HWH_NOT_FOUND",
            )
        if not asset_status.manifest_exists:
            raise OverlayLoadError(
                f"Overlay manifest not found: {asset_status.manifest_path}",
                error_code="OVERLAY_MANIFEST_NOT_FOUND",
            )
        if not asset_status.manifest_valid:
            raise OverlayLoadError(
                f"Overlay manifest is invalid: {asset_status.manifest_path}",
                error_code="OVERLAY_MANIFEST_INVALID",
            )
        return path

    def _native_symbols(self) -> tuple[Any, Any]:
        pynq_module = importlib.import_module("pynq")
        overlay_type = getattr(pynq_module, "Overlay")
        allocate_fn = getattr(pynq_module, "allocate")
        return overlay_type, allocate_fn

    def load_overlay(self) -> None:
        if self._simulator is not None:
            self._simulator.load_overlay(self.bitstream_path)
            self.state = PynqState.LOADED
            return

        path = self._validated_overlay_path()
        if self._pynq_python is not None:
            self.state = PynqState.LOADED
            logger.info(
                "Overlay assets validated for isolated PYNQ runtime at %s", self._pynq_python
            )
            return

        try:
            Overlay, _ = self._native_symbols()
            self.overlay = Overlay(str(path))
        except OverlayLoadError:
            raise
        except Exception as exc:  # noqa: BLE001
            # Same translation as the isolated worker: PYNQ's bare "Root
            # permissions required." names neither the cause nor the fix.
            if "root permissions" in str(exc).lower():
                raise OverlayLoadError(
                    "The board runtime is not allowed to program the FPGA: "
                    "loading a bitstream requires root and this runtime runs as "
                    "an ordinary user. Install the board runtime again from the "
                    "app so it is installed as a privileged service.",
                    error_code="PYNQ_ROOT_REQUIRED",
                ) from exc
            raise OverlayLoadError(
                f"Overlay loading failed: {exc}",
                error_code="OVERLAY_LOAD_FAILED",
            ) from exc

        self.dma = getattr(self.overlay, self._dma_ip_name, None)
        self.snn_ip = getattr(self.overlay, self._snn_ip_name, None)
        if not self.dma:
            logger.warning("DMA IP '%s' not found in overlay.", self._dma_ip_name)
        if not self.snn_ip:
            logger.warning("SNN IP '%s' not found in overlay.", self._snn_ip_name)
        self.state = PynqState.LOADED
        logger.info("Overlay loaded from %s", self.bitstream_path)

    def configure(
        self,
        weights: list[float],
        config: dict[str, Any],
        register_map: dict[str, Any] | None = None,
        layers: list[dict[str, Any]] | None = None,
    ) -> None:
        layers = [dict(layer) for layer in (layers or [])]

        if self._simulator is not None:
            self._simulator.configure(weights, config, register_map, layers=layers)
            self.state = PynqState.CONFIGURED
            self._configured_weights = list(weights)
            self._configured_config = dict(config)
            self._configured_layers = layers
            return

        if self.state == PynqState.UNLOADED:
            raise ConfigurationError(
                "Cannot configure before overlay is loaded",
                error_code="CONFIGURE_BEFORE_LOAD",
            )
        if register_map is not None:
            self.register_map = register_map
        if len(weights) > MAX_SYNAPSES:
            raise MmioWriteError(
                f"Weight/synapse count ({len(weights)}) exceeds MAX_SYNAPSES ({MAX_SYNAPSES})",
                error_code="MMIO_WEIGHT_OVERFLOW",
            )

        if self._pynq_python is not None:
            self._run_worker(
                {
                    "action": "deploy",
                    "bitstream_path": self.bitstream_path,
                    "dma_ip_name": self._dma_ip_name,
                    "snn_ip_name": self._snn_ip_name,
                    "weights": weights,
                    "layers": layers,
                    "config": config,
                    "register_map": self.register_map,
                    "max_synapses": MAX_SYNAPSES,
                },
                timeout=_resolve_deploy_timeout(),
            )
            self.state = PynqState.CONFIGURED
            self._configured_weights = list(weights)
            self._configured_config = dict(config)
            self._configured_layers = layers
            return

        # In-process PYNQ (no isolated worker) is not a supported path for
        # overlay-v2: the engine reads weights and descriptors from physically
        # contiguous DDR buffers whose lifetime the worker owns, and v1's
        # attempt to push them through an AXI-Lite window reached a port the
        # block design never connected.
        raise ConfigurationError(
            "The PYNQ overlay must be programmed through the isolated worker; "
            "in-process register writes cannot deliver the weight buffer.",
            error_code="PYNQ_WORKER_REQUIRED",
        )

    def run(
        self,
        input_spikes: list[int],
        timesteps: int = 1,
    ) -> dict[str, Any]:
        if self._simulator is not None:
            result = self._simulator.run(input_spikes, timesteps)
            self.state = PynqState.CONFIGURED
            return result

        if self.state not in (PynqState.CONFIGURED, PynqState.RUNNING):
            raise ConfigurationError(
                "Cannot run before configure is called",
                error_code="RUN_BEFORE_CONFIGURE",
            )

        if self._pynq_python is not None:
            self.state = PynqState.RUNNING
            try:
                response = self._run_worker(
                    {
                        "action": "run",
                        "bitstream_path": self.bitstream_path,
                        "dma_ip_name": self._dma_ip_name,
                        "snn_ip_name": self._snn_ip_name,
                        "weights": self._configured_weights,
                        "layers": self._configured_layers,
                        "config": self._configured_config,
                        "register_map": self.register_map,
                        "max_synapses": MAX_SYNAPSES,
                        "input_spikes": input_spikes,
                        "timesteps": timesteps,
                    }
                )
            finally:
                self.state = PynqState.CONFIGURED
            result_payload = response.get("result")
            if not isinstance(result_payload, dict):
                raise DmaTransferError(
                    "PYNQ worker returned an invalid run payload",
                    error_code="PYNQ_WORKER_BAD_RESPONSE",
                )
            return result_payload

        # In-process PYNQ is not a supported path for overlay-v2. This branch
        # used to carry its own copy of the v1 run defects — starting the
        # kernel by writing 0x01 to an unmapped offset, and sizing the output
        # buffer from the input length when the engine emits one word per
        # output neuron per timestep. Deleting it removes the second copy
        # rather than leaving it to be found again later.
        raise ConfigurationError(
            "The PYNQ overlay must be driven through the isolated worker; "
            "in-process DMA cannot deliver the engine's weight buffer.",
            error_code="PYNQ_WORKER_REQUIRED",
        )

    def reset(self) -> None:
        if self._simulator is not None:
            self._simulator.reset()
            self.state = PynqState.LOADED
            return
        if self.state == PynqState.UNLOADED:
            raise ConfigurationError(
                "Cannot reset — overlay was never loaded",
                error_code="RESET_BEFORE_LOAD",
            )
        self.state = PynqState.LOADED
        logger.info("Backend reset to LOADED state")

    @property
    def current_state(self) -> str:
        if self._simulator is not None:
            return self._simulator.current_state
        return self.state.name.lower()

    @property
    def runtime_mode(self) -> str:
        return "simulator" if self._simulator is not None else "hardware"

    @property
    def overlay_asset_status(self) -> OverlayAssetStatus:
        return inspect_overlay_assets(self.requested_bitstream_path)
