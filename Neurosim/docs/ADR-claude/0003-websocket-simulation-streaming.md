# ADR 0003: WebSocket Simulation Streaming

## Status
Accepted

## Context
SNN simulations can run for seconds to minutes. Users need live progress feedback and partial results during execution, not just final outputs after completion.

## Decision
Use a FastAPI WebSocket endpoint (`/api/neurosim/ws/simulation`) with an `asyncio.Queue`-based progress callback pattern. Simulation runs in a thread pool executor, pushes partial results to the main event loop via `run_coroutine_threadsafe`, and the WebSocket consumer streams typed messages (status, partial_results, complete, error) to the client.

## Consequences
- **Positive:** Real-time feedback enables interactive parameter tuning during simulation; WebSocket avoids polling overhead compared to HTTP long-polling.
- **Negative:** WebSocket connections are stateful and complicate horizontal scaling; the thread-to-async bridge adds complexity to error handling and cancellation.
