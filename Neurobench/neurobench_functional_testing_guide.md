# Neurobench Functional Testing Guide

**Module Purpose:**
The `neurobench` module acts as a rigorous testing and benchmarking workbench for evaluating Spiking Neural Network (SNN) performance. It translates Cognitive Network Language (CNL) specifications into executable simulations (via `neurocnl`, `nengo`, and `mujoco`), executes SNN models against standardized sensory datasets, and calculates metrics like accuracy, latency, power consumption, memory footprint, spike fidelity, and stopping distance while strictly enforcing regression boundaries and robustness criteria.

## 1. Core Functional Walkthrough (The "Happy Path")

This section verifies the primary SNN benchmarking lifecycle from the frontend interface down to the backend `BenchmarkRunner`.

**Execution Steps:**
1. **Select Benchmark Suite:** In the neurobench UI, select an existing `BenchmarkSuite` (e.g., "Visual Keyword Spotting" or "Neuromorphic Motor Control").
2. **Provide the Input Spec:** Upload or select the target SNN model specification (a `.cnl` file or pre-defined Cognitive Network Language specification).
3. **Configure Execution Parameters:**
   * Set the number of execution seeds (ensure `n_seeds` is set to $\ge 5$ for robustness testing to satisfy the `RobustnessCurve` contract).
   * Define the `RegressionThreshold` tolerances for key metrics (e.g., a 2% tolerance for `accuracy` and `power_mw`).
4. **Trigger SNN Simulation:** Click **"Run Benchmark"**.
5. **Monitor Pipeline:** Observe the loading states as the `BenchmarkRunner` merges the user's CNL specification with built-in assertions and hands it off to the simulation pipeline.

**Expected Outputs & Visual Changes:**
* **Dashboard Rendering:** Upon completion, the UI should transition to the Results Dashboard.
* **Metric Readouts:** You should see exact scalar readouts for all enforced contract metrics: `accuracy`, `latency_ms`, `power_mw`, `memory_kb`, `spike_fidelity`, and `stopping_distance`.
* **Robustness Curve Rendering:** A multi-line graph should render showing the `RobustnessCurve`, mapping fault rates against mean performance with confidence interval bounds shaded in.
* **Baseline Comparison:** The `DiffEngine` output should visually flag metrics as "Pass" (green) or "Regression/Fail" (red) compared to historical baselines based on the `lower-is-better` or `higher-is-better` logic specific to each metric.

## 2. Data & State Validation

To verify the internal structural and mathematical correctness of the SNN simulation and pipeline:

* **Pydantic Contract Validation (Network Level):** Open the browser's DevTools (Network Tab) and inspect the JSON payload returned by the FastAPI backend. Verify it strictly conforms to the `BenchmarkResult` and `TargetComparisonResult` schemas exported from `neurobench/contracts/`.
* **Database State Check (SQLite):** Connect to the backend `neurobench.sqlite` file. Query the `RunResult` table to verify:
  * Timestamps are stored in strict ISO-8601 format.
  * No metrics contain negative scores (which would violate database-level and Pydantic invariants).
  * Numeric fields are constrained correctly (e.g., 64-bit signed ranges to avoid overflow).
* **Robustness Curve Array Symmetry:** Intercept the backend JSON for the `RobustnessCurve` data object. Programmatically or manually verify that the lengths of the `fault_rates`, `means`, and `confidence_intervals` arrays are strictly identical.
* **DiffEngine Mathematical Validation:** Given a baseline `accuracy` of 0.90, a new `accuracy` of 0.88, and a `RegressionThreshold` tolerance of 0.015, verify the `DiffEngine` accurately marks this run as a regression, properly accounting for the metric direction (higher-is-better).

## 3. Module-Specific Edge Cases & Boundary Testing

Testing the domain-specific logic, specifically boundary conditions in neuromorphic simulation and metric evaluation:

1. **Extreme Denormals in Metric Deltas:**
   * *Test:* Submit an SNN model that performs *almost* identically to the baseline, yielding an infinitesimally small performance difference (e.g., a `latency_ms` difference of `1e-6`).
   * *Validation:* Verify the `DiffEngine` accurately applies the tolerance logic without experiencing floating-point overflow/underflow or mathematical rounding errors that falsely trigger a regression flag.
2. **Zero-Tolerance Natural Variance:**
   * *Test:* Set the `RegressionThreshold` tolerance to exactly `0.0` for a non-deterministic SNN run (executing across multiple seeds).
   * *Validation:* Verify that natural, sub-percentage variance correctly triggers a strict regression failure. This ensures the thresholding bounds logic treats `0.0` as an absolute invariant rather than evaluating as a "falsy" or ignored parameter.
3. **Spike Fidelity Saturation / Silence:**
   * *Test:* Provide an invalid sensory dataset where the baseline firing rate is entirely saturated (e.g., 1000 Hz in a 1ms time bin) or completely silent (0 spikes across the simulation window).
   * *Validation:* Ensure the `BenchmarkRunner` cleanly catches division-by-zero or infinite limit errors when calculating the `spike_fidelity` metric, gracefully failing the simulation with a meaningful domain-specific error message rather than a generic Python exception.
4. **Unsupported Metric Enforcement:**
   * *Test:* Use an intercepted API request to inject an unsupported metric (e.g., `"throughput_fps"`) into the `BenchmarkSuite`'s scoring config.
   * *Validation:* The backend `ScoringConfig` Pydantic contracts should immediately reject the payload with a 422 Unprocessable Entity, explicitly listing the allowed subset of supported metrics (`accuracy`, `latency_ms`, `power_mw`, `memory_kb`, `spike_fidelity`, `stopping_distance`).

## 4. Inter-Module Handoff Preparation

To guarantee that the outputs generated by `neurobench` are correctly formatted for downstream processing in the NMTK pipeline (e.g., deploying the validated network to `neurosim` or hardware compilation):

* **JSON Export Serialization Check:** Ensure that clicking "Export Results" yields a standard JSON structure where `TargetMetrics` and `TargetComparisonResult` objects are serialized cleanly without Python-specific data types (e.g., no raw UUID objects, NaNs, or unhandled datetime instances).
* **Reproducible State Package:** Verify that the exported bundle contains both the evaluation benchmark history and the exact version of the `.cnl` file that passed the benchmark. This guarantees the next module ingests the precisely validated configuration, rather than a modified local copy.
* **Baseline Registry Sync:** Verify that if the run is marked as a "New Baseline", the `neurobench` module successfully flags this state in the database payload, ensuring the overarching NMTK registry updates its global model tracking correctly.
