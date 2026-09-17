# SpiNNaker2 Integration Plan

## 1. Overview
Neurosim integrates with the `py-spinnaker2` package to provide massively parallel neuromorphic simulations on the SpiNNaker2 hardware. SpiNNaker2 can support very large-scale SNN models at or faster than biological real time. This integration offers a new backend service (`SpiNNaker2SimBackend`) parallel to existing backends (like Nengo), along with a set of FastAPI endpoints mapping specifically to SpiNNaker2 run and status polling actions.

## 2. Invocation as a Simulation Backend
Unlike the default CPU-bound backends (e.g., Nengo) which can run within the same event loop with a direct thread or process, SpiNNaker2 interaction works via a job submission model due to its hardware-bound nature.

The flow is as follows:
1. **Frontend Request:** User triggers a run using a target backend `spinnaker2`.
2. **Router Mapping:** Request is directed to `POST /api/sim/spinnaker2/run`.
3. **Backend Engine:** The `SpiNNaker2SimBackend` parses the `CanvasGraph` and generates a compatible `py-spinnaker2` Network.
4. **Hardware Execution:** The payload is sent to the physical SpiNNaker2 system (via Ethernet/SpinnCloud connection).
5. **Results Collection:** The backend polls or waits for completion, downloads memory buffers containing spikes/voltages, and formats them into Neurosim's standard dictionary.

## 3. The `SpiNNaker2SimBackend` Class
Located in `neurosim/app/backends/spinnaker2_backend.py`.

### Interfaces
- `load(graph: CanvasGraph)`:
  Converts a Neurosim graph into a SpiNNaker2 network. Each `CanvasNode` translates to a `spinnaker2.Population` and `CanvasEdge` translates to a `spinnaker2.Projection`.
- `run(duration_ms: float) -> str`:
  Initiates the run via `hardware.Simulator`. Assigns and returns a unique `run_id`.
- `get_results() -> dict`:
  Fetches simulation recordings.
- `reset() -> None`:
  Clears the current state of the backend to accept a new graph.

## 4. Spike & Potential Recordings
Py-SpiNNaker2 uses probe arrays bound to populations. In `load()`, the integration dynamically injects voltage and spike probes on target nodes where recordings are enabled.

Mapping logic for `get_results()`:
- `spikes`: The raw byte stream from the hardware is decoded. For each population, it builds a list of spike times per neuron ID, aligning exactly with Neurosim's `PreviewResponse` format `results[node_id]["spikes"]`.
- `voltage`: Mapped similarly using float traces collected per time-step.

## 5. Real-Time vs. Offline Modes
- **Real-Time Mode:** Runs strict synchronized intervals for closed-loop tasks.
- **Offline/As-Fast-As-Possible Mode:** Allows the hardware to run fully unbounded. Neurosim currently defaults to offline mode, batching the entire run and fetching results at the end. Future UI features will permit users to enable closed-loop (Real-Time) sync via WebSockets.

## 6. Large Network Partitioning
SpiNNaker2 maps neural populations automatically to compute cores (152 per chip).
For models exceeding one core's memory (typically a few thousand neurons), py-spinnaker2 automatically partitions populations.

**Neurosim UI Exposure:**
Users do not explicitly manage this partitioning, but Neurosim will read the `n_neurons` per population and may issue an info-level warning via the API metrics if the partition count approaches system limits.

## 7. Graceful Software-Only Fallback
If the py-spinnaker2 library is missing or a board is unavailable (e.g. `ImportError`), the `SpiNNaker2SimBackend` enters a fallback state. It warns the user via logs, generates a dummy `run_id`, and returns zero-filled tensors for voltage/spikes. This ensures integration tests and local UI testing won't crash when hardware is detached.

## 8. New Endpoints
Registered in `neurosim/app/routers/spinnaker2.py`:
- `POST /api/sim/spinnaker2/run`
  Accepts a `PreviewRequest` and initiates execution.
- `GET /api/sim/spinnaker2/results/{run_id}`
  Retrieves data. Returns 404 if the run ID is missing or expired.

## 9. Dependencies
Managed in `pyproject.toml` under `project.optional-dependencies`:
```toml
spinnaker2 = [
    "py-spinnaker2",
]
```
Users looking to deploy SpiNNaker2 support must run `pip install -e ".[spinnaker2]"`.
