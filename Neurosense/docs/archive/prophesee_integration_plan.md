# Prophesee — Event Camera / Metavision SDK Integration Plan

Support level for this path: `prototype`

This document describes the intended event-camera integration path. It should
not be interpreted as a validated equivalent to the flagship forearm-EMG
workflow.

## 1. Device discovery
We will use `metavision_sdk_core` to interact with Prophesee EVK cameras. The integration assumes a single connected EVK for live mode. A new `PropheseeSource` class will wrap `EventsIterator` to connect to a live Prophesee EVK camera. For device discovery, a new endpoint `GET /api/neurosense/sense/prophesee/devices` is implemented to return available Prophesee devices if the SDK is installed.

## 2. Event stream ingestion
`PropheseeSource` utilizes `metavision_core.event_io.EventsIterator` to ingest the asynchronous event stream. The iterator batches events into `EventCD` buffers (NumPy arrays with fields `x`, `y`, `p`, `t`) over a time window `delta_t`. The method `read_events` in `PropheseeSource` returns these arrays to the caller.

## 3. Offline playback
`PropheseeSource` supports an `"offline"` mode. When instantiated with `mode="offline"` and a `path` parameter pointing to a `.raw` or `.hdf5` recording, it opens the recording using `EventsIterator`. This enables offline replay and benchmarking without live hardware.

## 4. Spike encoding pipeline
Unlike traditional analog signals, the event stream from Prophesee cameras is already neuromorphic (asynchronous events). Therefore, the pipeline bypasses the standard `SpikeEncoder` used for analog-to-spike conversion. Instead, a new `EventEncoder` service takes the raw event batches from `PropheseeSource` and converts them into SNN spike tensors directly.

## 5. Coordinate mapping
The `EventEncoder` is responsible for mapping the 3D event coordinates `(x, y, polarity)` into a flattened 1D neuron address for generic SNN input layers.
The mapping function used is: `address = y * (width * 2) + x * 2 + polarity`.
This flattens the spatial and polarity dimensions into a single linear index.

## 6. Synchronisation
Timestamps (`t`) from the `EventCD` buffers are preserved and passed along in the spike tensor. In a real-time system, these timestamps are aligned relative to the simulation timestep or initial stream start time to keep the camera and SNN simulation in sync. For this integration, timestamps are passed through directly from the event buffer.

## 7. A new `PropheseeSource` data source class
A new module `neurosense/app/sources/prophesee_source.py` contains `PropheseeSource`, which provides `open(delta_t)`, `read_events()`, and `close()` methods. It encapsulates the `EventsIterator` and handles both live and offline modes.

## 8. New API endpoints
A new router `neurosense/app/routers/prophesee.py` defines the following endpoints:
- `GET /sense/prophesee/devices`: Discovers available Prophesee devices.
- `POST /sense/prophesee/stream/start`: Starts a stream (live or offline).
- `POST /sense/prophesee/stream/stop`: Stops the active stream.
The router is mounted under `/api/neurosense/sense/prophesee`.

## 9. Dependency
The optional dependency `metavision-sdk` is added to `pyproject.toml` under the `[project.optional-dependencies]` block as `prophesee = ["metavision-sdk"]`. The integration gracefully handles its absence by checking if `metavision_core` is importable.
