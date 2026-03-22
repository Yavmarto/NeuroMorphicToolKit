# Benchmarking Tools
> Addresses the gap: no common yardstick exists for evaluating neuromorphic models

---

## 1. Benchmark Runner

**Description**
Execute standard tasks against any SNN model and collect energy, latency, and accuracy metrics in a reproducible way.

**Target surfaces:** Desktop app + Python library

**Tags:** `NeuroBench` `SNN` `metrics`

### Spec
- Accepts a model object in any supported format: PyNN, Lava, Nengo, Brian2, or NIR
- Runs a configurable suite of standard benchmark tasks (keyword spotting, gesture recognition, etc.)
- Records the following metrics per run:
  - Inference latency (ms)
  - Synaptic operations (SynOps)
  - Energy estimate (mJ)
  - Accuracy (%)
- Outputs a structured JSON report and an optional NeuroBench-compatible CSV
- **Desktop:** visual task selector, live progress bar, results table with sortable columns
- **Python:** `runner.run(model, tasks=["kws", "gesture"])` → returns `BenchmarkResult` dataclass

---

## 2. Results Comparator

**Description**
Side-by-side comparison of benchmark runs across different models, hardware targets, and frameworks.

**Target surfaces:** Desktop app

**Tags:** `comparison` `visualization` `export`

### Spec
- Load multiple saved `.bench` result files and display them in a unified table
- Spider/radar chart for multi-metric comparison (energy vs. accuracy vs. latency trade-offs)
- Filter by hardware target, framework, and task type
- Export to PNG, CSV, or LaTeX table for publication
- Flag runs that used incompatible settings with a warning badge

---

## 3. Hardware Profiler

**Description**
Connect to physical neuromorphic hardware (Intel Loihi, SpiNNaker, BrainScaleS) and record real on-chip metrics.

**Target surfaces:** Desktop app + Python library

**Tags:** `Loihi` `SpiNNaker` `on-chip`

### Spec
- Hardware abstraction layer: uniform interface regardless of backend
- Captures chip-level power readings, spike train traces, and neuron utilization
- Outputs the same `BenchmarkResult` schema as the Benchmark Runner for direct comparison
- **Desktop:** live spike raster view during execution, per-core utilization heatmap
- **Python:** `profiler.attach("loihi2")` → context manager that wraps a model run
