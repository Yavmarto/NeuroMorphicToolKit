# SpiNNcloud / SpiNNaker2 Hardware Benchmarking Integration Plan

## 1. Overview
This document serves as the formal integration plan for executing and benchmarking Spiking Neural Networks (SNNs) on SpiNNaker2 hardware via the Neurobench module. Using the `py-spinnaker2` SDK interface, Neurobench will directly deploy network definitions (.cnl / pyNN), stream data, and collect physical performance metrics.

## 2. `SpiNNaker2BenchmarkRunner` Interface
The `SpiNNaker2BenchmarkRunner` is designed to be fully compatible with Neurobench’s existing runner suite (`simulation`, `neurosim`, `neurochip`).
It resides in `neurobench/app/runners/spinnaker2_runner.py` and exposes:
*   `run_benchmark(benchmark_id, network_path, params, seed)` -> `BenchmarkResult`

**Execution Flow:**
1. Loads the target network CNL/PyNN specification.
2. Interacts with the `py-spinnaker2.simulator.Simulator` to configure the board and instantiate the network map.
3. Streams inputs across the deployed network.
4. Pauses/completes execution and extracts physical statistics via `py-spinnaker2` chip monitors.

## 3. Metric Collection Strategy
Instrumenting SpiNNaker2 requires leveraging specific hardware monitors exposed by `py-spinnaker2`:
*   **Latency (Wall-Clock):** Unlike pure simulation, physical latency will be tracked via the host-side measurement of the full pipeline (data streaming in + chip processing + streaming out) divided by the timesteps, and by internal chip clock cycles if fine-grained execution timestamps are returned by the SDK.
*   **Spike Counts (Sparsity):** Using `py-spinnaker2` monitors (`record(['spikes'])`), the runner extracts exact spike totals generated per layer during execution to compute activation sparsity.
*   **Energy Consumption:** If real-time power monitoring is active on the SpiNNaker2 board (e.g., via specialized diagnostic folders or board sensors), telemetry is sampled. If direct board telemetry is not exposed, energy is approximated using the static baseline power of active cores + dynamic event-driven energy proportional to spike counts and communication hops.
*   **Accuracy/Assertions:** Final state traces or output spikes are scored against the standard `benchmark_def.assertions`.

## 4. Standard Benchmark Suite Compatibility
SpiNNaker2 supports Brian2-style and PyNN-style definitions. For Neurobench's standard suites:
*   **Static Gesture (DVS):** Uses data streaming capabilities (`s2_nir` or Brian2 streaming backend) to stream DVS frames as spikes into the chip, reading categorical output spike arrays.
*   **Speech Commands:** Audio sequences are converted to spike trains (e.g., via Delta Modulation) and streamed to the chip.
The runner automatically resolves CNL assertions into expected physical output probes.

## 5. Result Schema Mapping
Extracted data maps neatly into Neurobench's unified `contracts.BenchmarkResult`:
```json
{
  "target_id": "spinnaker2",
  "metrics": {
    "latency_ms": 12.5,
    "energy_uj": 450.0,
    "accuracy": 0.94,
    "assertions_passed": 10,
    "assertions_failed": 0
  }
}
```

## 6. Comparison Mode: CPU/GPU vs SpiNNaker2
To generate comprehensive cross-target reports, the `spinnaker2` target integrates directly with Neurobench's `TargetComparator`.
Users can submit a comparison job specifying targets `["simulation", "spinnaker2"]`.
*   **Simulation (CPU/GPU):** Handled by `neurocnl` pipeline (exact mathematical evaluation).
*   **SpiNNaker2:** Handled by `SpiNNaker2BenchmarkRunner` (physical hardware proxy).
The `DiffEngine` and `ReportGenerator` will automatically highlight the physical speedup (Latency $\\Delta$) and energy advantages of SpiNNaker2 while confirming that physical fidelity and accuracy (Assertions) are maintained.

## 7. API Endpoints
A dedicated routing module `neurobench/app/routers/spinnaker2.py` exposes:
*   `POST /bench/spinnaker2/run` - Initiates a direct run on SpiNNaker2 hardware.
*   `GET /bench/spinnaker2/results/{run_id}` - Polls and retrieves the specific benchmark payload.

## 8. Dependencies
`py-spinnaker2` is declared as an optional `[spinnaker2]` extra in `pyproject.toml`, allowing lightweight frontend/simulation nodes to operate without requiring the heavy hardware SDK unless explicitly provisioning a hardware-connected worker.
