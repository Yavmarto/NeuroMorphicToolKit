from __future__ import annotations

import asyncio
import json
import multiprocessing
import time
from typing import Any, cast

import httpx
import numpy as np
import uvicorn
import websockets

from neurosense.app.main import app


def run_server() -> None:
    uvicorn.run(app, host="127.0.0.1", port=8006, log_level="error")


async def benchmark_latency() -> None:
    server_process = multiprocessing.Process(target=run_server)
    server_process.start()
    await asyncio.sleep(2)

    base_url = "http://127.0.0.1:8006/api/neurosense"
    ws_url = "ws://127.0.0.1:8006/api/neurosense/stream/filtered"

    try:
        async with httpx.AsyncClient() as client:
            # 1. Get synthetic device
            resp = await client.get(f"{base_url}/devices")
            devices = cast(list[dict[str, Any]], resp.json())
            dev = next(d for d in devices if d["type"] == "synthetic")
            device_id = dev["id"]

            # 2. Connect
            await client.post(f"{base_url}/devices/{device_id}/connect")

            latencies: list[float] = []
            intervals: list[float] = []
            last_end = None

            async with websockets.connect(f"{ws_url}?device_id={device_id}&batch_ms=50") as ws:
                # Discard first few samples
                for _ in range(5):
                    await ws.recv()

                for _i in range(50):
                    msg = await ws.recv()
                    end = time.time()

                    data = json.loads(msg)
                    server_ts = data["timestamp"]

                    latencies.append((end - server_ts) * 1000)

                    if last_end is not None:
                        interval = (end - last_end) * 1000
                        intervals.append(interval)
                    last_end = end

            avg_lat = np.mean(latencies)
            std_lat = np.std(latencies)
            avg_int = np.mean(intervals)
            std_int = np.std(intervals)
            print(f"Average end-to-end latency: {avg_lat:.2f} ms (std: {std_lat:.2f} ms)")
            print(f"Average interval: {avg_int:.2f} ms (std: {std_int:.2f} ms)")

            if avg_lat < 50:
                print("Latency target MET (<50ms)")
            else:
                print("Latency target NOT MET (>50ms)")

    finally:
        server_process.terminate()
        server_process.join()


if __name__ == "__main__":
    asyncio.run(benchmark_latency())
