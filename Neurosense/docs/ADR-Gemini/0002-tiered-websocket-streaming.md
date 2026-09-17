# ADR 0002: Tiered WebSocket Streaming

## Status
Accepted

## Context
Neurosense must rapidly acquire sensor data (EMG, EEG) and deliver it safely to the Flutter frontend and the pipeline. The streams include pure raw data, filtered signals, and spike-encoded events occurring contemporaneously. Polling via HTTP is too slow, and sending mixed packets via a single socket requires complex frontend demultiplexing.

## Decision
We implemented a tiered WebSocket architecture. The FastAPI backend broadcasts three distinct WS endpoints: `/stream/raw`, `/stream/filtered`, and `/stream/spikes`. Each endpoint manages a bounded ring-buffer (e.g. last 30s) pushed out to the specific frontend consumer blocks at native sampling rate groupings (e.g., 50ms batches).

## Consequences
- **Positive:** Lowers latency considerably (`<100ms`). Consumers (Flutter Views, file exporters) only subscribe to the data format they expressly need.
- **Negative:** High concurrency overhead on the backend handling 3+ WS broadcasting streams per connected client; risks thread starvation in high-throughput sensor environments.

## Status Update (2026-07-16 audit)
There is no bounded ring-buffer holding ~30s of history. `_run_streaming_loop` in
`neurosense/app/routers/stream.py` uses `asyncio.Queue(maxsize=5)` (line 61) purely as a
producer/consumer backpressure mechanism between the acquisition loop and the WebSocket
sender for live frames — it holds at most 5 pending frames, not a time-windowed buffer.
Confirmed via grep that no `deque` or `ring_buffer` construct exists anywhere in
`neurosense/app/`. The three-endpoint tiering (`/stream/raw`, `/stream/filtered`,
`/stream/spikes`) itself checks out.
