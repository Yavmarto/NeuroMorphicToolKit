# PYNQ Z2 — Physical Energy & Power Benchmarking Plan

## Context
A known gap in NMTK's benchmarking: the energy-efficiency claims of neuromorphic computing (Joules-per-spike, mW idle power) are not physically realised when the SNN runs on a CPU. The PYNQ Z2 has accessible on-board power rails and the Xilinx `xpowermon` / `pynq.pmbus` API, making it the first platform in the stack where real energy measurements are achievable. This is the benchmark that validates the core neuromorphic efficiency argument.

## 1. PYNQ Power Monitoring API
The PYNQ Z2 provides access to onboard power monitoring via the `pynq.pmbus` module and `pynq.DataRecorder`.

- **Power Rails:**
  - PL (Programmable Logic / FPGA): Monitored via the `VCC_INT`, `VCC_AUX`, and `VCCBRAM` rails. The sum of these represents the power consumed by the SNN overlay.
  - PS (Processing System / ARM): Monitored via the `PS` rail.
- **Sampling & Resolution:**
  - The `DataRecorder` samples voltage and current. The sampling rate is typically up to 10-100Hz depending on the PMBus IC and I2C bus speed, providing sufficient resolution for inference runs lasting seconds.
- **Isolation Strategy:**
  - To isolate PL (FPGA SNN overlay) power from PS (ARM) power, we record all rails concurrently. The PL power is calculated as the sum of `VCC_INT`, `VCC_AUX`, and `VCCBRAM` power (Voltage × Current). The PS power rail provides the baseline processing overhead, which is subtracted or reported separately.

## 2. `PYNQBenchmarkRunner` Class
A new runner class `PYNQBenchmarkRunner` will be created at `neurobench/app/runners/pynq_runner.py`.

- **Responsibilities:**
  - Wraps an SNN inference run on the PYNQ Z2.
  - Coordinates with a service running on the PYNQ board.
- **Interface:**
  - `load(bitstream)`: Triggers the remote PYNQ service to flash the provided SNN bitstream.
  - `run_benchmark(stimulus, n_steps)`: Transmits stimulus data over the network to the PYNQ board and initiates the inference window.
  - `get_metrics()`: Retrieves hardware metrics from the board.
- **Synchronization:**
  - The PYNQ-side service handles tight synchronization: it starts the `DataRecorder`, feeds the `stimulus` array to the PL via DMA, waits for completion, stops the `DataRecorder`, and calculates total Joules and average mW.
- **Returned Metrics:**
  - `energy_J` (total energy during inference), `avg_power_mW` (average power), `latency_ms` (inference time), `spike_count` (total emitted spikes), and `joules_per_spike`.

## 3. Baseline Comparison
To validate the neuromorphic efficiency claims, physical PYNQ runs must be compared against a CPU baseline.

- **CPU Baseline Methodology:**
  - Run the same network via Nengo simulation on a standard CPU host.
  - Capture wall-clock execution time and estimate CPU energy using `psutil` CPU load multiplied by the known TDP of the host CPU (e.g., `CPU Load % × TDP × time = estimated_energy_J`).
- **Comparison Table:**
  - A side-by-side comparison table will be generated showing:
    - **Latency (ms)**: CPU vs PYNQ PL
    - **Average Power (mW)**: CPU estimated vs PYNQ PL measured
    - **Energy Efficiency (J/spike)**: CPU estimated vs PYNQ PL measured

## 4. Neurobench Standard Suite on PYNQ
- **Compatible Benchmarks:**
  - Tasks that can be fed as discrete stimulus arrays (e.g., static gesture recognition, speech commands, pattern recognition) are compatible. The stimulus must be serialized, sent over the network to the PYNQ board, and fed to the PL.
- **Result Schema Mapping:**
  - `avg_power_mW` maps to `power_mw` in Neurobench's `BenchmarkResult.metrics`.
  - `energy_J * 1_000_000` maps to `energy_uj` in Neurobench's `BenchmarkResult.metrics`.
  - `latency_ms` maps to `latency_ms`.
  - `joules_per_spike` maps to a custom metric `joules_per_spike`.

## 5. New API Endpoints
A new router `neurobench/app/routers/pynq.py` will expose the following endpoints:

- `POST /api/neurobench/pynq/run`
  - Submits a benchmark job to a connected PYNQ Z2.
- `GET /api/neurobench/pynq/results/{run_id}`
  - Retrieves energy, latency, and standard benchmark metrics for a completed PYNQ run.
- `GET /api/neurobench/pynq/power_trace/{run_id}`
  - Retrieves the raw power rail time-series data for visualization (voltage/current per rail over time).

## 6. Dependency Management
- **Target Environment:** The `pynq>=2.7` library will not be a dependency for the main Neurobench backend running on the host. Instead, it must be installed in the Python environment on the PYNQ Z2 board itself via an optional extra `[pynq]`.
- **Communication:** The host-side `PYNQBenchmarkRunner` communicates with the PYNQ service strictly over the network (e.g., via REST HTTP calls), keeping the host environment free of PYNQ-specific system dependencies.
