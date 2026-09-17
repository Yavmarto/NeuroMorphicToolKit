"""Standalone PYNQ worker executed by an isolated interpreter."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Any

_DMA_TIMEOUT_DEFAULT_S = 30.0
_DMA_TIMEOUT_BOUNDS_S = (5.0, 300.0)
_raw_dma_timeout = os.getenv("NEUROCHIP_PYNQ_DMA_TIMEOUT_SECONDS", "").strip()
try:
    _parsed = float(_raw_dma_timeout) if _raw_dma_timeout else _DMA_TIMEOUT_DEFAULT_S
except ValueError:
    _parsed = _DMA_TIMEOUT_DEFAULT_S
DMA_TIMEOUT_S = max(_DMA_TIMEOUT_BOUNDS_S[0], min(_DMA_TIMEOUT_BOUNDS_S[1], _parsed))
DMA_POLL_INTERVAL_S = 0.01

# Vitis HLS `CTRL` register bits, fixed by the s_axilite protocol.
CTRL_AP_START_BIT = 0x1
CTRL_AP_DONE_BIT = 0x2
CTRL_AP_IDLE_BIT = 0x4


class WorkerError(RuntimeError):
    """Structured worker-side error."""

    def __init__(self, message: str, *, error_code: str) -> None:
        self.error_code = error_code
        super().__init__(message)


def _emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, sort_keys=True))
    sys.stdout.write("\n")


def _load_request() -> dict[str, Any]:
    raw = sys.stdin.read().strip()
    if not raw:
        raise WorkerError("Worker request payload missing", error_code="WORKER_BAD_REQUEST")
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise WorkerError(
            f"Worker request must be valid JSON: {exc}",
            error_code="WORKER_BAD_REQUEST",
        ) from exc
    if not isinstance(decoded, dict):
        raise WorkerError(
            "Worker request must decode to an object", error_code="WORKER_BAD_REQUEST"
        )
    return decoded


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
        raise WorkerError("DMA channel is missing wait()", error_code="DMA_RUNTIME_UNAVAILABLE")

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
        time.sleep(DMA_POLL_INTERVAL_S)

    if _dma_channel_idle(channel) is True:
        return
    raise TimeoutError(f"DMA channel did not become idle within {timeout_s:.2f}s")


def _validate_overlay(path_text: str) -> Path:
    path = Path(path_text)
    if path.suffix != ".bit":
        raise WorkerError(
            f"Bitstream must be a .bit file, got: {path.name}",
            error_code="OVERLAY_INVALID_FORMAT",
        )
    if not path.exists():
        raise WorkerError(f"Bitstream not found: {path}", error_code="OVERLAY_NOT_FOUND")
    hwh_path = path.with_suffix(".hwh")
    if not hwh_path.exists():
        raise WorkerError(
            f"Hardware handoff file not found: {hwh_path}",
            error_code="HWH_NOT_FOUND",
        )
    return path


def _load_hardware(
    path_text: str,
    *,
    dma_ip_name: str,
    snn_ip_name: str,
) -> tuple[Any, Any, Any, Any]:
    path = _validate_overlay(path_text)
    try:
        import importlib

        pynq_module = importlib.import_module("pynq")
        Device = getattr(pynq_module, "Device")
        Overlay = getattr(pynq_module, "Overlay")
        allocate = getattr(pynq_module, "allocate")
    except ImportError as exc:
        raise WorkerError(
            f"pynq runtime unavailable in isolated interpreter: {exc}",
            error_code="PYNQ_RUNTIME_UNAVAILABLE",
        ) from exc
    except AttributeError as exc:
        raise WorkerError(
            f"pynq runtime is missing required symbols: {exc}",
            error_code="PYNQ_RUNTIME_UNAVAILABLE",
        ) from exc

    try:
        devices = Device.devices
    except Exception as exc:  # noqa: BLE001
        raise WorkerError(
            f"PYNQ device probe failed: {exc}",
            error_code="PYNQ_DEVICE_PROBE_FAILED",
        ) from exc
    if not devices:
        raise WorkerError(
            "PYNQ device probe failed: no programmable devices found",
            error_code="PYNQ_DEVICE_NOT_FOUND",
        )

    try:
        overlay = Overlay(str(path))
    except Exception as exc:  # noqa: BLE001
        # PYNQ writes the bitstream through the FPGA manager, which only root
        # may drive, and says so with a bare "Root permissions required." that
        # names neither the cause nor a way out. A runtime installed in user
        # space passes every readiness check and only fails here, so say what
        # the user has to do about it.
        if "root permissions" in str(exc).lower():
            raise WorkerError(
                "The board runtime is not allowed to program the FPGA: loading a "
                "bitstream requires root and this runtime runs as an ordinary "
                "user. Install the board runtime again from the app so it is "
                "installed as a privileged service.",
                error_code="PYNQ_ROOT_REQUIRED",
            ) from exc
        raise WorkerError(
            f"Overlay loading failed: {exc}",
            error_code="OVERLAY_LOAD_FAILED",
        ) from exc

    dma = getattr(overlay, dma_ip_name, None)
    snn_ip = getattr(overlay, snn_ip_name, None)
    return overlay, dma, snn_ip, allocate


def _require_offset(register_map: dict[str, Any], key: str) -> int:
    """Return a register offset, or refuse to guess one.

    Overlay-v1 defaulted every offset it could not find, so the host happily
    wrote each of the engine's arguments to an address nothing decoded and the
    board returned silence that looked like a successful run. There is no safe
    default for an address, so a missing one stops the deploy.
    """
    value = register_map.get(key)
    if not isinstance(value, int):
        raise WorkerError(
            f"The installed overlay's register map has no '{key}'. Its offsets "
            "were never resolved from a built bitstream, so the host does not "
            "know where to write the engine's arguments. Reinstall the overlay.",
            error_code="OVERLAY_REGISTER_MAP_UNRESOLVED",
        )
    return value


def _int8(value: float) -> int:
    return max(-128, min(127, int(round(float(value)))))


def _layer_config_words(layers: list[dict[str, Any]]) -> list[int]:
    """Pack layer descriptors into the engine's uint32 word layout.

    Mirrors the ``OVERLAY_V2_CFG_*`` constants in
    ``hardware/pynq_z2/hls/snn_overlay_engine.hpp``.
    """
    words: list[int] = []
    for layer in layers:
        words.extend(
            [
                int(layer.get("input_size", 0)),
                int(layer.get("output_size", 0)),
                int(layer.get("weight_offset", 0)),
                int(layer.get("threshold", 0)) & 0xFFFFFFFF,
                int(layer.get("leak_shift", 0)),
                int(layer.get("refractory", 0)),
                0,
                0,
            ]
        )
    return words


def _configure_hardware(
    snn_ip: Any,
    allocate: Any,
    *,
    weights: list[float],
    layers: list[dict[str, Any]],
    register_map: dict[str, Any],
    max_synapses: int,
) -> list[Any]:
    """Program the engine and return the buffers it will read from.

    The returned buffers must stay alive for as long as the engine may read
    them: they live in physically contiguous DDR and the engine holds their
    addresses. Freeing them early hands the fabric someone else's memory.
    """
    if len(weights) > max_synapses:
        raise WorkerError(
            f"Weight/synapse count ({len(weights)}) exceeds MAX_SYNAPSES ({max_synapses})",
            error_code="WEIGHT_BUFFER_OVERFLOW",
        )
    if not layers:
        raise WorkerError(
            "Deploy payload carries no layer descriptors, so the engine has no network to run.",
            error_code="MISSING_LAYER_DESCRIPTORS",
        )

    if snn_ip is None or allocate is None:
        return []

    # Resolve every offset before allocating anything, so an unresolved
    # register map surfaces as itself rather than as a downstream write error.
    weights_ptr_offset = _require_offset(register_map, "weights_ptr_offset")
    layer_config_ptr_offset = _require_offset(register_map, "layer_config_ptr_offset")
    layer_count_offset = _require_offset(register_map, "layer_count_offset")
    weight_count_offset = _require_offset(register_map, "weight_count_offset")

    np = _numpy()

    weight_buffer = allocate(shape=(max(1, len(weights)),), dtype=np.int8)
    config_words = _layer_config_words(layers)
    config_buffer = allocate(shape=(len(config_words),), dtype=np.uint32)
    buffers = [weight_buffer, config_buffer]

    try:
        if weights:
            np.copyto(
                weight_buffer,
                np.array([_int8(weight) for weight in weights], dtype=np.int8),
            )
        np.copyto(config_buffer, np.array(config_words, dtype=np.uint32))

        # Hand the engine the physical addresses of both buffers. v1 tried to
        # push weights through an AXI-Lite window the block design never
        # connected to the engine's weight port.
        snn_ip.write(weights_ptr_offset, int(weight_buffer.physical_address))
        snn_ip.write(layer_config_ptr_offset, int(config_buffer.physical_address))
        snn_ip.write(layer_count_offset, len(layers))
        snn_ip.write(weight_count_offset, len(weights))
    except WorkerError:
        for buffer in buffers:
            buffer.freebuffer()
        raise
    except Exception as exc:  # noqa: BLE001
        for buffer in buffers:
            buffer.freebuffer()
        raise WorkerError(f"Register write failed: {exc}", error_code="MMIO_WRITE_FAILED") from exc

    return buffers


def _numpy() -> Any:
    try:
        import importlib

        return importlib.import_module("numpy")
    except ImportError as exc:
        raise WorkerError(
            f"numpy runtime unavailable in isolated interpreter: {exc}",
            error_code="DMA_RUNTIME_UNAVAILABLE",
        ) from exc


def _start_kernel(snn_ip: Any, register_map: dict[str, Any]) -> None:
    """Assert ``ap_start``.

    v1 wrote the weight count over this register and then poked offset 0x08,
    which is neither ``CTRL`` nor ``GIER``, so the kernel was never
    deliberately started.
    """
    control_offset = _require_offset(register_map, "control_reg_offset")
    snn_ip.write(control_offset, CTRL_AP_START_BIT)


def _wait_for_kernel(snn_ip: Any, register_map: dict[str, Any], *, timeout_s: float) -> bool:
    """Poll ``ap_done``/``ap_idle``. Returns whether the kernel reported done."""
    control_offset = _require_offset(register_map, "control_reg_offset")
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        try:
            status = int(snn_ip.read(control_offset))
        except Exception:  # noqa: BLE001
            return False
        if status & (CTRL_AP_DONE_BIT | CTRL_AP_IDLE_BIT):
            return True
        time.sleep(DMA_POLL_INTERVAL_S)
    return False


def _run_hardware(
    dma: Any,
    snn_ip: Any,
    allocate: Any,
    *,
    input_spikes: list[int],
    timesteps: int,
    layers: list[dict[str, Any]],
    register_map: dict[str, Any],
) -> dict[str, Any]:
    if dma is None:
        raise WorkerError(
            "DMA IP not available in the loaded overlay",
            error_code="DMA_NOT_AVAILABLE",
        )
    if not input_spikes:
        raise WorkerError(
            "Input spike buffer is empty — DMA underrun",
            error_code="DMA_EMPTY_BUFFER",
        )
    if not layers:
        raise WorkerError(
            "Cannot run without layer descriptors",
            error_code="MISSING_LAYER_DESCRIPTORS",
        )

    np = _numpy()

    # The engine consumes one input frame and produces one output frame per
    # timestep. v1's engine read the input vector once per *output neuron*
    # while the host sent it once per timestep, and sized the output buffer
    # from the input length.
    input_size = int(layers[0].get("input_size", 0))
    output_size = int(layers[-1].get("output_size", 0))
    expected_input_words = input_size * timesteps
    if input_size <= 0 or output_size <= 0:
        raise WorkerError(
            "Layer descriptors declare a zero-width input or output",
            error_code="MISSING_LAYER_DESCRIPTORS",
        )
    if len(input_spikes) != expected_input_words:
        raise WorkerError(
            f"Expected {expected_input_words} input words "
            f"({input_size} neurons x {timesteps} timesteps), got {len(input_spikes)}",
            error_code="DMA_INPUT_SIZE_MISMATCH",
        )

    start = time.monotonic()
    in_buffer = allocate(shape=(expected_input_words,), dtype=np.uint32)
    out_buffer = allocate(shape=(output_size * timesteps,), dtype=np.uint32)

    try:
        np.copyto(in_buffer, np.array(input_spikes, dtype=np.uint32))
        if snn_ip is not None:
            snn_ip.write(_require_offset(register_map, "timestep_count_offset"), timesteps)
            _start_kernel(snn_ip, register_map)

        dma.sendchannel.transfer(in_buffer)
        dma.recvchannel.transfer(out_buffer)
        _wait_for_dma_channel(dma.sendchannel, timeout_s=DMA_TIMEOUT_S)
        _wait_for_dma_channel(dma.recvchannel, timeout_s=DMA_TIMEOUT_S)
        kernel_done = (
            _wait_for_kernel(snn_ip, register_map, timeout_s=DMA_TIMEOUT_S)
            if snn_ip is not None
            else False
        )
        output_spikes = out_buffer.tolist()
    except WorkerError:
        in_buffer.freebuffer()
        out_buffer.freebuffer()
        raise
    except Exception as exc:  # noqa: BLE001
        in_buffer.freebuffer()
        out_buffer.freebuffer()
        raise WorkerError(
            f"DMA transfer failed: {exc}",
            error_code="DMA_TRANSFER_FAILED",
        ) from exc
    else:
        in_buffer.freebuffer()
        out_buffer.freebuffer()

    return {
        "output_spikes": output_spikes,
        "timesteps": timesteps,
        "output_neurons": output_size,
        "kernel_reported_done": kernel_done,
        "execution_time_us": (time.monotonic() - start) * 1_000_000,
    }


def main() -> int:
    try:
        request = _load_request()
        action = str(request.get("action") or "").strip()
        bitstream_path = str(request.get("bitstream_path") or "")
        dma_ip_name = str(request.get("dma_ip_name") or "axi_dma_0").strip() or "axi_dma_0"
        snn_ip_name = str(request.get("snn_ip_name") or "snn_engine_0").strip() or "snn_engine_0"
        register_map = request.get("register_map")
        config = request.get("config")
        layers = request.get("layers")
        if not isinstance(register_map, dict):
            register_map = {}
        if not isinstance(config, dict):
            config = {}
        if not isinstance(layers, list):
            layers = []

        if action == "probe_device":
            path = _validate_overlay(bitstream_path)
            try:
                import importlib

                pynq_module = importlib.import_module("pynq")
                Device = getattr(pynq_module, "Device")
            except ImportError as exc:
                raise WorkerError(
                    f"pynq runtime unavailable in isolated interpreter: {exc}",
                    error_code="PYNQ_RUNTIME_UNAVAILABLE",
                ) from exc
            except AttributeError as exc:
                raise WorkerError(
                    f"pynq runtime is missing required symbols: {exc}",
                    error_code="PYNQ_RUNTIME_UNAVAILABLE",
                ) from exc
            try:
                devices = Device.devices
            except Exception as exc:  # noqa: BLE001
                raise WorkerError(
                    f"PYNQ device probe failed: {exc}",
                    error_code="PYNQ_DEVICE_PROBE_FAILED",
                ) from exc
            if not devices:
                raise WorkerError(
                    "PYNQ device probe failed: no programmable devices found",
                    error_code="PYNQ_DEVICE_NOT_FOUND",
                )
            _emit(
                {
                    "ok": True,
                    "result": {
                        "device_count": len(devices),
                        "bitstream_path": str(path),
                    },
                }
            )
            return 0

        if action == "load_overlay":
            _load_hardware(
                bitstream_path,
                dma_ip_name=dma_ip_name,
                snn_ip_name=snn_ip_name,
            )
            _emit({"ok": True})
            return 0

        weights = [float(value) for value in request.get("weights", [])]
        max_synapses = int(request.get("max_synapses", 262144))
        _, dma, snn_ip, allocate = _load_hardware(
            bitstream_path,
            dma_ip_name=dma_ip_name,
            snn_ip_name=snn_ip_name,
        )
        # The engine reads weights and descriptors from physically contiguous
        # DDR it holds the addresses of, so those buffers have to outlive the
        # configure step. This process is one-shot, which is why `run` always
        # reprograms rather than relying on a previous `deploy`.
        buffers = _configure_hardware(
            snn_ip,
            allocate,
            weights=weights,
            layers=layers,
            register_map=register_map,
            max_synapses=max_synapses,
        )

        try:
            if action == "deploy":
                _emit({"ok": True})
                return 0
            if action == "run":
                input_spikes = [int(value) for value in request.get("input_spikes", [])]
                timesteps = int(request.get("timesteps", 1))
                _emit(
                    {
                        "ok": True,
                        "result": _run_hardware(
                            dma,
                            snn_ip,
                            allocate,
                            input_spikes=input_spikes,
                            timesteps=timesteps,
                            layers=layers,
                            register_map=register_map,
                        ),
                    }
                )
                return 0
        finally:
            for buffer in buffers:
                buffer.freebuffer()

        raise WorkerError(
            f"Unsupported worker action: {action or '<missing>'}",
            error_code="WORKER_BAD_REQUEST",
        )
    except WorkerError as exc:
        _emit({"ok": False, "detail": str(exc), "error_code": exc.error_code})
        return 1
    except Exception as exc:  # noqa: BLE001
        _emit(
            {
                "ok": False,
                "detail": f"Unexpected worker failure: {type(exc).__name__}: {exc}",
                "error_code": "WORKER_RUNTIME_ERROR",
            }
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
