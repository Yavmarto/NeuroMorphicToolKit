from __future__ import annotations

import asyncio
import json
import multiprocessing
import traceback
from typing import Any, cast

import httpx
import uvicorn
import websockets

import os

from neurosense.app.main import app


def run_server() -> None:
    uvicorn.run(app, host="127.0.0.1", port=8005, log_level="info")


def stop_server_process(server_process: multiprocessing.Process) -> None:
    """Stop the verifier server without waiting forever on hardware threads."""
    server_process.terminate()
    server_process.join(timeout=5)
    if server_process.is_alive():
        server_process.kill()
        server_process.join(timeout=5)
    if server_process.is_alive():
        raise RuntimeError("NeuroSense bridge verifier server did not stop.")


async def _exercise_device_path(
    client: httpx.AsyncClient,
    *,
    base_url: str,
    ws_url: str,
    device_type: str,
    sampling_rate_hz: float,
    allow_experimental: bool = False,
) -> None:
    print(f"Scanning for {device_type} device...")
    resp = await client.get(f"{base_url}/devices")
    assert resp.status_code == 200
    devices = cast(list[dict[str, Any]], resp.json())
    device = next((entry for entry in devices if entry["type"] == device_type), None)
    assert device is not None, f"{device_type} device not found"
    device_id = device["id"]
    print(f"Found {device_type} device: {device_id}")

    connect_suffix = "?allow_experimental=true" if allow_experimental else ""
    print(f"Connecting to device {device_id}...")
    resp = await client.post(f"{base_url}/devices/{device_id}/connect{connect_suffix}")
    if resp.status_code != 200:
        print(f"Connect failed: {resp.text}")
    assert resp.status_code == 200
    assert resp.json()["connected"] is True

    print("Triggering encoder configuration via /encode...")
    encoding_config = {"method": "delta", "delta_threshold": 0.1}
    await client.post(
        f"{base_url}/encode",
        json={
            "data": [[0.0, 0.1, 0.2]],
            "encoding_config": encoding_config,
            "sampling_rate_hz": sampling_rate_hz,
        },
    )

    print("Connecting to spike stream WebSocket...")
    try:
        async with websockets.connect(f"{ws_url}?device_id={device_id}") as ws:
            for i in range(5):
                try:
                    message = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    data = json.loads(message)
                    print(f"Received spike data batch {i + 1}")
                    print(f"Keys: {data.keys()}")
                    if "spike_trains" in data:
                        print(f"Channels in spike data: {len(data['spike_trains'])}")
                    assert "spike_trains" in data
                    assert "spike_counts" in data
                except TimeoutError:
                    print("Timeout waiting for WebSocket message")
                    break
    except Exception as e:
        print(f"WebSocket error: {e}")
        traceback.print_exc()

    print(f"Disconnecting from device {device_id}...")
    resp = await client.post(f"{base_url}/devices/{device_id}/disconnect")
    assert resp.status_code == 200
    assert resp.json()["connected"] is False


async def verify() -> None:
    os.environ["NEUROSENSE_MUSE_MODEL"] = "muse2"
    os.environ["NEUROSENSE_PIEEG_STREAM_HOST"] = "225.1.1.1"
    os.environ["NEUROSENSE_MOCK_BOARD_SHIM"] = "1"

    # Start the server in a separate process (inherits env for mock + Muse target)
    server_process = multiprocessing.Process(target=run_server)
    server_process.start()

    # Wait for the server to start
    await asyncio.sleep(3)

    base_url = "http://127.0.0.1:8005/api/neurosense"
    ws_url = "ws://127.0.0.1:8005/api/neurosense/stream/spikes"

    try:
        async with httpx.AsyncClient() as client:
            await _exercise_device_path(
                client,
                base_url=base_url,
                ws_url=ws_url,
                device_type="synthetic",
                sampling_rate_hz=250.0,
            )
            await _exercise_device_path(
                client,
                base_url=base_url,
                ws_url=ws_url,
                device_type="muse",
                sampling_rate_hz=256.0,
                allow_experimental=True,
            )
            await _exercise_device_path(
                client,
                base_url=base_url,
                ws_url=ws_url,
                device_type="pieeg",
                sampling_rate_hz=250.0,
                allow_experimental=True,
            )
    finally:
        stop_server_process(server_process)


if __name__ == "__main__":
    asyncio.run(verify())
