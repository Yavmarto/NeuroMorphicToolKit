"""Stream router -- WebSocket endpoints for raw, filtered, and spike data."""

import asyncio
import time
from collections.abc import Callable
from typing import Any

import numpy as np
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from ..services.device_manager import device_manager
from ..services.filter_pipeline import filter_pipeline
from ..services.recording_service import recording_service
from ..services.spike_encoder import spike_encoder

router = APIRouter()


async def _get_device_or_close(websocket: WebSocket, device_id: str | None) -> str:
    """Resolve the device ID to use for streaming.

    If *device_id* is None, falls back to the currently connected device.
    Closes the WebSocket with an error if no device is available.
    Returns the resolved device_id.
    """
    if device_id is None:
        connected = device_manager.get_connected_device()
        if connected is None:
            await websocket.close(code=4001, reason="No device connected.")
            return ""
        device_id = connected.id
    return device_id


async def _socket_consumer(websocket: WebSocket, queue: asyncio.Queue[dict[str, Any]]) -> None:
    """Generic consumer task to send JSON frames from a queue to a WebSocket."""
    try:
        while True:
            data = await queue.get()
            await websocket.send_json(data)
            queue.task_done()
    except (WebSocketDisconnect, asyncio.CancelledError):
        pass


async def _enqueue_with_backpressure(
    queue: asyncio.Queue[dict[str, Any]], payload: dict[str, Any]
) -> None:
    """Push *payload*, dropping the oldest queued frame first if full."""
    if queue.full():
        try:
            queue.get_nowait()
            queue.task_done()
        except asyncio.QueueEmpty:
            pass
    await queue.put(payload)


def _next_frame_timing(start_time: float, frame_count: int, interval: float) -> tuple[float, int]:
    """Calculate the next wakeup, resetting the clock if badly behind schedule."""
    next_time = start_time + (frame_count * interval)
    sleep_time = next_time - time.perf_counter()
    if sleep_time < -interval:
        # We are significantly behind; reset timing to catch up
        return time.perf_counter(), 0
    return start_time, frame_count


async def _run_streaming_loop(
    websocket: WebSocket,
    device_id: str,
    batch_ms: int,
    process_fn: Callable[[list[list[float]]], dict[str, Any] | None],
) -> None:
    """Generic producer-consumer loop with backpressure and precise timing."""
    device = device_manager._devices.get(device_id)
    if device is None:
        await websocket.close(code=4001, reason="Device not found.")
        return

    samples_per_batch = max(1, int(device.sampling_rate_hz * batch_ms / 1000))
    interval = batch_ms / 1000.0

    queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=5)
    consumer_task = asyncio.create_task(_socket_consumer(websocket, queue))

    try:
        start_time = time.perf_counter()
        frame_count = 0

        while True:
            # 1. Fetch data
            raw_data = await device_manager.get_current_data(device_id, samples_per_batch)

            # 2. Process data (filtering, encoding, etc.)
            payload = await asyncio.to_thread(process_fn, raw_data)

            # 3. Handle backpressure: drop oldest if queue is full
            if payload:
                await _enqueue_with_backpressure(queue, payload)

            # 4. Precise timing: sleep until the next scheduled frame
            frame_count += 1
            start_time, frame_count = _next_frame_timing(start_time, frame_count, interval)
            sleep_time = (start_time + frame_count * interval) - time.perf_counter()
            if sleep_time > 0:
                await asyncio.sleep(sleep_time)

    except (WebSocketDisconnect, asyncio.CancelledError):
        pass
    finally:
        consumer_task.cancel()
        try:
            await consumer_task
        except asyncio.CancelledError:
            pass


@router.websocket("/raw")
async def stream_raw(
    websocket: WebSocket,
    device_id: str | None = Query(default=None),
    batch_ms: int = Query(default=50, ge=10, le=1000),
) -> None:
    """Stream raw analog data from the connected device."""
    await websocket.accept()
    resolved_id = await _get_device_or_close(websocket, device_id)
    if not resolved_id:
        return

    device = device_manager._devices.get(resolved_id)
    if not device:
        return

    def process_raw(data: list[list[float]]) -> dict[str, Any] | None:
        if recording_service.is_active and data and len(data[0]) > 0:
            recording_service.append_raw(np.array(data))
        return {
            "timestamp": time.time(),
            "channels": data,
            "sampling_rate_hz": device.sampling_rate_hz,
        }

    await _run_streaming_loop(websocket, resolved_id, batch_ms, process_raw)


@router.websocket("/filtered")
async def stream_filtered(
    websocket: WebSocket,
    device_id: str | None = Query(default=None),
    batch_ms: int = Query(default=50, ge=10, le=1000),
) -> None:
    """Stream filtered analog data."""
    await websocket.accept()
    resolved_id = await _get_device_or_close(websocket, device_id)
    if not resolved_id:
        return

    device = device_manager._devices.get(resolved_id)
    if not device:
        return

    def process_filtered(data: list[list[float]]) -> dict[str, Any] | None:
        raw_array = np.array(data, dtype=np.float64)
        if raw_array.size > 0:
            filtered_array = filter_pipeline.apply(raw_array)
            channels_out = filtered_array.tolist()
            if recording_service.is_active:
                recording_service.append_filtered(np.array(channels_out))
        else:
            channels_out = data
        return {
            "timestamp": time.time(),
            "channels": channels_out,
            "sampling_rate_hz": device.sampling_rate_hz,
        }

    await _run_streaming_loop(websocket, resolved_id, batch_ms, process_filtered)


@router.websocket("/spikes")
async def stream_spikes(
    websocket: WebSocket,
    device_id: str | None = Query(default=None),
    batch_ms: int = Query(default=50, ge=10, le=1000),
) -> None:
    """Stream spike-encoded data."""
    await websocket.accept()
    resolved_id = await _get_device_or_close(websocket, device_id)
    if not resolved_id:
        return

    device = device_manager._devices.get(resolved_id)
    if not device:
        return

    def process_spikes(data: list[list[float]]) -> dict[str, Any] | None:
        raw_array = np.array(data, dtype=np.float64)
        if raw_array.size > 0:
            filtered = filter_pipeline.apply(raw_array)
            spike_result = spike_encoder.encode(filtered)
        else:
            spike_result = {
                "spike_trains": [],
                "spike_counts": [],
                "method": "unknown",
            }
        if recording_service.is_active:
            recording_service.append_spikes(spike_result)
        return {
            "timestamp": time.time(),
            **spike_result,
            "sampling_rate_hz": device.sampling_rate_hz,
        }

    await _run_streaming_loop(websocket, resolved_id, batch_ms, process_spikes)
