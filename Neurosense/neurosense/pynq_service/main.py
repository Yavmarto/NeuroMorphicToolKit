"""
FastAPI service running on the PYNQ Z2 ARM processor.
Manages PL (Programmable Logic) streams, AXI DMA transfers, and serves spike data over WebSockets.
"""

import asyncio
import importlib
import logging
from dataclasses import dataclass
from typing import Any, cast

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)

app = FastAPI(title="PYNQ Z2 Sensor Node")


@dataclass
class _HardwareState:
    overlay: Any = None
    dma: Any = None
    input_buffer: Any = None
    output_buffer: Any = None
    error: str | None = None


_hardware_state = _HardwareState()


def _load_pynq() -> Any:
    """Load pynq lazily so type checking does not require board stubs."""
    return cast(Any, importlib.import_module("pynq"))


def _reset_hardware(error: str) -> None:
    """Drop any partially initialised overlay/DMA state and record why."""
    _hardware_state.overlay = None
    _hardware_state.dma = None
    _hardware_state.input_buffer = None
    _hardware_state.output_buffer = None
    _hardware_state.error = error


def init_hardware() -> None:
    """Initialize the PYNQ Overlay and AXI DMA pipelines.

    This runs on the PYNQ board's ARM core. It loads the bitstream for spike
    pre-processing (e.g., rate coding/delta modulation) and configures DMA.
    """
    _hardware_state.error = None
    try:
        pynq = _load_pynq()
        logger.info("Loading neuromorphic bitstream on PL...")
        _hardware_state.overlay = pynq.Overlay("sensor_pipeline.bit")

        logger.info("Configuring AXI DMA pipelines...")
        # Assuming the overlay exposes a DMA IP named 'axi_dma_0'
        _hardware_state.dma = _hardware_state.overlay.axi_dma_0

        # Allocate contiguous memory buffers for DMA transfer (ARM space)
        _hardware_state.input_buffer = pynq.allocate(shape=(1024,), dtype="u4")
        _hardware_state.output_buffer = pynq.allocate(shape=(1024,), dtype="u4")

    except ImportError:
        logger.warning("pynq package not found. Running in simulated mode.")
        _reset_hardware("pynq package not installed")
    except (OSError, ValueError, RuntimeError) as exc:
        # A real board with no staged bitstream raises here (missing .bit/.hwh).
        # Stay up and serve fallback frames instead of crashing the startup hook.
        logger.warning("PYNQ overlay unavailable (%s). Serving fallback frames.", exc)
        _reset_hardware(str(exc))


@app.on_event("startup")
async def on_startup() -> None:
    init_hardware()


@app.get("/status")
async def get_status() -> dict[str, Any]:
    """Return the status of the edge node and PL."""
    hardware_initialized = _hardware_state.overlay is not None
    return {
        "status": "ok",
        "hardware_initialized": str(hardware_initialized),
        "runtime_mode": "hardware" if hardware_initialized else "fallback",
        "overlay_error": _hardware_state.error,
    }


@app.websocket("/stream")
async def stream_data(websocket: WebSocket) -> None:
    """WebSocket endpoint to stream processed spike data to the host."""
    await websocket.accept()
    logger.info("WebSocket client connected for data stream.")

    # Background task to consume messages (process ping/pong control frames)
    async def consume_messages() -> None:
        try:
            while True:
                await websocket.receive()
        except WebSocketDisconnect:
            pass
        except Exception:
            pass

    consumer_task = asyncio.create_task(consume_messages())

    try:
        while True:
            # If real hardware is initialized, perform DMA transfer
            if _hardware_state.dma is not None and _hardware_state.output_buffer is not None:
                # Initiate DMA transfer from PL to ARM
                _hardware_state.dma.recvchannel.transfer(_hardware_state.output_buffer)
                _hardware_state.dma.recvchannel.wait()

                # Extract spikes (example payload conversion)
                data_list = _hardware_state.output_buffer.tolist()
                payload = {"spikes": data_list}
            else:
                # Simulated payload if PYNQ not installed
                await asyncio.sleep(0.05)
                payload = {"spikes": [1, 0, 1, 0]}

            await websocket.send_json(payload)

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected.")
    except Exception as e:
        logger.error(f"Error during streaming: {e}")
        try:
            await websocket.close()
        except Exception:
            pass
    finally:
        consumer_task.cancel()
