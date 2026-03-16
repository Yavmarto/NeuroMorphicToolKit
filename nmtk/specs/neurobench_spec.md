# NeuroBench — Test & Benchmarking Workbench
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroBench is a testing and benchmarking workbench for evaluating SNN performance across the full stack: algorithm accuracy, hardware efficiency, robustness, and real-world signal fidelity. It targets product teams building neuromorphic systems who need to systematically compare designs, validate robustness, and produce evidence for design reviews and certification.

---

## Repository

`neuro-space/NeuroBench` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package — for CNL parsing, validation, simulation
- `neurodreamhand` Python package — for fault injection, power profiling, quantization analysis
- `neuro-flutter-ui` shared Flutter design system package
- Optionally integrates with NeuroChip (cross-target comparison) and NeuroSense (real-signal benchmarks)

---

## User Stories

### Benchmark Execution

**NB-B1 · Run a standard benchmark**
As an engineer evaluating a network design,
I want to select a standard benchmark (e.g., grip stability, spike classification) and run it against my network,
so that I get a normalized performance score I can compare to other designs.

Acceptance criteria:
- Benchmark catalog lists available benchmarks with: name, description, task type, input format, scoring metric
- Built-in benchmarks: grip stability (prosthetic), spike classification accuracy, reaction latency, wake-word detection, pattern recognition
- "Run" button submits the benchmark as a background job
- Results display: score, breakdown by sub-metric, comparison to known baselines (if available)
- Benchmark parameters are configurable (e.g., simulation duration, number of trials, noise level)

**NB-B2 · Run benchmarks in CI/CD**
As a DevOps engineer integrating SNN testing into our build pipeline,
I want to trigger benchmarks via CLI or HTTP and fail the build on regression,
so that performance degradation is caught before deployment.

Acceptance criteria:
- CLI tool: `neurobench run <benchmark_id> --network <spec.cnl> --baseline <baseline.json> --fail-on-regression`
- HTTP API: `POST /api/neurobench/run` with the same parameters
- Exit code 1 (or HTTP 422) if any metric regresses beyond the configured threshold
- JSON output with all metrics, suitable for CI artifact storage
- Baseline file is a previous benchmark result JSON that defines the "pass" thresholds

**NB-B3 · Define custom benchmarks**
As a team with domain-specific requirements,
I want to define custom benchmarks using CNL assertion suites and input datasets,
so that I can test against our product's specific acceptance criteria.

Acceptance criteria:
- Benchmark definition format: JSON manifest with fields: name, description, input_spec (CNL or data file), assertions (CNL assertion suite), scoring_function, pass_threshold
- Custom benchmarks appear in the catalog alongside built-ins
- Benchmarks can reference NeuroSense recordings as input data
- Custom benchmarks are sharable via NeuroHub

### Cross-Target Comparison

**NB-CT1 · Compare the same network across hardware targets**
As a product team deciding between Loihi 2 and Akida,
I want to run the same benchmark on both targets and see accuracy, latency, power, and spike fidelity side by side,
so that I can make a data-driven deployment decision.

Acceptance criteria:
- Select network + benchmark + multiple targets (from NeuroChip's hardware profiles)
- For each target: apply target-specific quantization, run benchmark, collect metrics
- Comparison table: rows = targets, columns = accuracy, latency (est.), power (est.), memory usage, spike fidelity, quantization loss
- Highlight Pareto-optimal targets
- Export comparison as PDF or CSV

**NB-CT2 · Quantify simulation-to-hardware gap**
As an engineer validating that my simulation results hold on real hardware,
I want to compare benchmark results from Nengo simulation vs. a connected Teensy running the same network,
so that I can quantify the sim-to-real gap.

Acceptance criteria:
- Requires NeuroChip + physical hardware connected
- Run benchmark on Nengo (CPU), then flash to Teensy via NeuroChip, run same benchmark with real I/O
- Compare: accuracy, timing, spike counts, output waveforms
- Gap report: per-metric delta, percentage deviation, visual overlay of simulation vs. hardware output
- Flag metrics where hardware deviates > configurable threshold (default 5%)

### Encoding Strategy Comparison

**NB-ES1 · Compare spike encoding methods on the same task**
As an engineer choosing an encoding strategy,
I want to run the same network with rate, temporal, and delta encoding and see which preserves the most task-relevant information,
so that I pick the right encoding without trial-and-error.

Acceptance criteria:
- Select network + input signal (from NeuroSense recording or synthetic)
- Run benchmark with each encoding method, same parameters otherwise
- Comparison view: encoding method, accuracy score, spike rate (spikes/s), information efficiency (bits/spike), computation cost
- Recommendation text: "For this task and input type, delta encoding achieves the best accuracy/efficiency tradeoff"

### Regression Testing

**NB-R1 · Save and diff against baselines**
As an engineer iterating on a network,
I want to save a benchmark result as a baseline and get a diff when I re-run after changes,
so that I know exactly what improved or degraded.

Acceptance criteria:
- "Save as Baseline" button on any benchmark result
- Re-running the same benchmark shows a diff panel: metric, baseline value, current value, delta, delta %
- Color-coded: green = improved, red = regressed, gray = unchanged (within noise threshold)
- Configurable noise threshold per metric (default: 1%)
- Baseline history: track multiple baselines over time, see trend charts

**NB-R2 · Regression alerts**
As a team lead,
I want to be notified when a benchmark regresses beyond a threshold,
so that regressions are caught early.

Acceptance criteria:
- Per-benchmark configurable thresholds (e.g., "fail if accuracy drops > 2%", "warn if power increases > 10%")
- CLI mode returns non-zero exit code on threshold violation
- HTTP mode returns structured error response with violating metrics
- Optional: webhook notification (Slack, email) on regression

### Robustness Profiling

**NB-RP1 · Fault sweep robustness curve**
As an engineer designing for hardware reliability,
I want to sweep across fault injection rates and see a robustness curve,
so that I know the failure point of my network before deployment.

Acceptance criteria:
- Configure: fault type (dead neuron, stuck-at, weight noise), sweep range (0%-30%), step count
- Output: robustness curve (accuracy vs. fault rate) with confidence intervals (N=5 seeds per point)
- Summary: "Network maintains >90% accuracy up to 12% dead neurons"
- Compare robustness curves across different quantization levels or network variants

**NB-RP2 · Input perturbation sweep**
As an engineer validating noise tolerance,
I want to sweep input noise levels and see how performance degrades,
so that I know how sensitive my network is to noisy sensor data.

Acceptance criteria:
- Configure: noise type (Gaussian, salt-and-pepper, signal dropout), range, steps
- Output: performance vs. noise level curve
- Works with synthetic inputs or real recorded signals (via NeuroSense)

### Reporting

**NB-RE1 · Generate benchmark report**
As an engineer presenting to a design review,
I want to export a comprehensive benchmark report as PDF or HTML,
so that I can share results with stakeholders who don't use the tool.

Acceptance criteria:
- Report includes: network description, benchmark methodology, all metrics with charts, comparison tables, robustness curves, conclusion
- Charts are publication-quality (high DPI, clean typography)
- Report is auto-generated from benchmark results — no manual formatting needed
- Configurable sections: include/exclude comparison, robustness, encoding analysis
- Company logo and header customizable

---

## Backend Spec

### API Endpoints

All NeuroBench-specific endpoints live under `/api/neurobench/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurobench/benchmarks` | List available benchmarks (built-in + custom) |
| GET | `/api/neurobench/benchmarks/{id}` | Get benchmark definition and metadata |
| POST | `/api/neurobench/benchmarks` | Create a custom benchmark definition |
| POST | `/api/neurobench/run` | Run a benchmark (returns job ID) |
| GET | `/api/neurobench/run/{job_id}` | Poll benchmark job status and results |
| POST | `/api/neurobench/compare/targets` | Run cross-target comparison |
| POST | `/api/neurobench/compare/encoding` | Run encoding strategy comparison |
| POST | `/api/neurobench/faults/sweep` | Run fault injection sweep |
| POST | `/api/neurobench/perturbation/sweep` | Run input perturbation sweep |
| GET | `/api/neurobench/baselines` | List saved baselines |
| POST | `/api/neurobench/baselines` | Save a benchmark result as baseline |
| POST | `/api/neurobench/diff` | Diff current result against a baseline |
| GET | `/api/neurobench/results` | List all benchmark results (filterable) |
| GET | `/api/neurobench/results/{id}` | Get a specific result |
| POST | `/api/neurobench/report` | Generate a benchmark report (PDF/HTML) |

### Data Models

**BenchmarkDefinition**
```python
class BenchmarkDefinition(BaseModel):
    id: str                              # e.g., "grip_stability"
    name: str                            # e.g., "Grip Stability"
    description: str
    task_type: str                       # "control", "classification", "detection", "latency"
    input_spec: InputSpec                # How to generate or source input data
    assertions: list[str]                # CNL assertion strings
    scoring: ScoringConfig
    default_params: dict[str, Any]       # Default benchmark parameters
    builtin: bool                        # True for built-in, False for custom

class InputSpec(BaseModel):
    type: Literal["synthetic", "recording", "custom"]
    synthetic_config: dict | None = None   # Signal generator parameters
    recording_session_id: str | None = None  # NeuroSense session ID
    data_path: str | None = None           # Path to input data file

class ScoringConfig(BaseModel):
    primary_metric: str                  # e.g., "accuracy", "stopping_distance", "latency_ms"
    secondary_metrics: list[str]         # Additional metrics to track
    higher_is_better: bool               # For the primary metric
    pass_threshold: float                # Minimum acceptable value
```

**BenchmarkResult**
```python
class BenchmarkResult(BaseModel):
    id: str
    benchmark_id: str
    network_spec_hash: str
    timestamp: str
    target_id: str | None                # Hardware target (None = Nengo CPU)
    quantization_bits: int | None
    encoding_method: str | None
    params: dict[str, Any]               # Benchmark parameters used
    metrics: dict[str, float]            # All metrics: {"accuracy": 0.94, "latency_ms": 12.3, ...}
    spike_data: dict | None              # Optional spike raster data for visualization
    wall_time_seconds: float
    seed: int
```

**DiffResult**
```python
class DiffResult(BaseModel):
    baseline_id: str
    current_id: str
    metrics: list[MetricDiff]

class MetricDiff(BaseModel):
    name: str
    baseline_value: float
    current_value: float
    delta: float
    delta_pct: float
    status: Literal["improved", "regressed", "unchanged"]
    threshold_violated: bool
```

**RobustnessCurve**
```python
class RobustnessCurve(BaseModel):
    fault_type: str
    fault_rates: list[float]
    accuracies_mean: list[float]
    accuracies_ci_lower: list[float]
    accuracies_ci_upper: list[float]
    threshold_90pct: float | None
    n_seeds: int
```

**ComparisonResult**
```python
class TargetComparisonResult(BaseModel):
    benchmark_id: str
    network_spec_hash: str
    targets: list[TargetMetrics]
    pareto_optimal: list[str]            # Target IDs on the Pareto front

class TargetMetrics(BaseModel):
    target_id: str
    target_name: str
    quantization_bits: int
    accuracy: float
    accuracy_loss_pct: float
    estimated_power_mw: float
    estimated_latency_us: float
    memory_kb: float
    spike_fidelity: float
    warnings: list[str]
```

### Service Architecture

```
NeuroBench Frontend (Flutter)
       |
       | HTTP
       |
NeuroBench Backend (FastAPI)
       |
       ├── neurocnl (simulation, assertion validation)
       ├── neurodreamhand (fault injection, power profiling)
       ├── NeuroChip API (cross-target quantization + hardware profiles)
       ├── NeuroSense API (recorded session data for real-signal benchmarks)
       └── reportlab / weasyprint (PDF report generation)
```

NeuroBench calls NeuroChip and NeuroSense APIs over HTTP when cross-target or real-signal features are used. It operates independently for pure simulation benchmarks.

### Benchmark Definitions

Stored as JSON manifests in `neurobench/benchmarks/`:

```
benchmarks/
  builtin/
    grip_stability.json
    spike_classification.json
    reaction_latency.json
    wake_word_detection.json
    pattern_recognition.json
  custom/                            # User-created benchmarks
```

### CLI Interface

```bash
# Run a benchmark
neurobench run grip_stability --network prosthetic_reflex.cnl

# Run with baseline comparison
neurobench run grip_stability --network prosthetic_reflex.cnl --baseline results/baseline_v1.json

# Fail on regression (for CI)
neurobench run grip_stability --network prosthetic_reflex.cnl --baseline results/baseline_v1.json --fail-on-regression --threshold 0.02

# Cross-target comparison
neurobench compare --network prosthetic_reflex.cnl --targets teensy41,loihi2,akida --benchmark grip_stability

# Fault sweep
neurobench faults --network prosthetic_reflex.cnl --type dead_neuron --range 0:0.3:0.05 --seeds 5

# Generate report
neurobench report --result results/run_20260315.json --format pdf --output report.pdf
```

---

## Frontend Spec

### Screen Layout

```
┌──────────────────────────────────────────────────────┐
│ Toolbar: [Load Network] [Benchmark: Grip ▾] [Run]    │
├──────────┬───────────────────────────────────────────┤
│          │                                           │
│ Sidebar  │  Main Panel (tabs)                        │
│          │                                           │
│ Bench-   │  [Results] [Compare] [Robustness] [Report]│
│ marks    │                                           │
│ ─────    │  ┌─ Results ───────────────────────────┐  │
│ ✅ Grip  │  │                                     │  │
│ ○ Class. │  │  Accuracy: 94.2%  (+1.3% vs base)  │  │
│ ○ Latency│  │  Latency:  12.3ms (-0.8ms vs base) │  │
│ ○ Custom │  │  Power:    0.3mW  (no baseline)     │  │
│          │  │                                     │  │
│ Baselines│  │  [Spike Raster]  [Output Traces]    │  │
│ ─────    │  │                                     │  │
│ v1.0     │  └─────────────────────────────────────┘  │
│ v0.9     │                                           │
│          │  History: [run1] [run2] [run3] [run4]     │
├──────────┴───────────────────────────────────────────┤
│ Status: Benchmark complete (3.2s) | Last run: 14:32  │
└──────────────────────────────────────────────────────┘
```

### Key Widgets

| Widget | Purpose |
|---|---|
| `BenchmarkCatalog` | Sidebar listing benchmarks with status icons |
| `BenchmarkConfigPanel` | Parameter configuration before running |
| `ResultsSummaryCard` | Score + sub-metrics with baseline diff coloring |
| `MetricDiffTable` | Baseline vs. current comparison table |
| `TargetComparisonGrid` | Multi-target comparison with Pareto highlighting |
| `EncodingComparisonGrid` | Multi-encoding comparison |
| `RobustnessCurveChart` | Accuracy vs. fault rate with confidence bands |
| `PerturbationCurveChart` | Accuracy vs. noise level |
| `BaselineSelector` | Dropdown to select baseline for diffing |
| `RunHistoryTimeline` | Horizontal timeline of past benchmark runs |
| `ReportBuilder` | Configure and generate PDF/HTML reports |

### Providers (Riverpod)

| Provider | State |
|---|---|
| `benchmarkCatalogProvider` | Available benchmarks (built-in + custom) |
| `activeBenchmarkProvider` | Currently selected benchmark |
| `networkProvider` | Loaded network for benchmarking |
| `benchmarkJobProvider` | Running benchmark job status |
| `resultsProvider` | Latest benchmark result |
| `baselinesProvider` | Saved baselines for active benchmark |
| `diffProvider` | Diff between current result and selected baseline |
| `targetComparisonProvider` | Cross-target comparison results |
| `encodingComparisonProvider` | Encoding strategy comparison results |
| `robustnessProvider` | Fault sweep robustness curves |
| `perturbationProvider` | Input perturbation sweep results |
| `runHistoryProvider` | Past benchmark runs |

---

## File Structure

```
NeuroBench/
├── neurobench/                      # Python backend + CLI
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/
│   │   │   ├── benchmarks.py
│   │   │   ├── runner.py
│   │   │   ├── comparison.py
│   │   │   ├── faults.py
│   │   │   ├── perturbation.py
│   │   │   ├── baselines.py
│   │   │   ├── results.py
│   │   │   └── reports.py
│   │   ├── schemas/
│   │   │   ├── benchmarks.py
│   │   │   ├── results.py
│   │   │   ├── comparison.py
│   │   │   ├── robustness.py
│   │   │   └── reports.py
│   │   └── services/
│   │       ├── benchmark_runner.py      # Orchestrates: load network → simulate → score
│   │       ├── target_comparator.py     # Calls NeuroChip for quantization per target
│   │       ├── encoding_comparator.py   # Calls NeuroSense for encoding variants
│   │       ├── fault_sweeper.py         # Wraps neurodreamhand fault_injector
│   │       ├── perturbation_sweeper.py  # Input noise injection
│   │       ├── diff_engine.py           # Baseline comparison logic
│   │       ├── report_generator.py      # PDF/HTML report builder
│   │       └── result_store.py          # SQLite result + baseline storage
│   ├── benchmarks/                  # JSON benchmark definitions
│   │   ├── builtin/
│   │   │   ├── grip_stability.json
│   │   │   ├── spike_classification.json
│   │   │   ├── reaction_latency.json
│   │   │   ├── wake_word_detection.json
│   │   │   └── pattern_recognition.json
│   │   └── custom/
│   ├── cli/                         # CLI entry point
│   │   └── __main__.py
│   ├── pyproject.toml
│   └── tests/
├── frontend/                        # Flutter frontend
│   ├── lib/
│   │   ├── app.dart
│   │   ├── screens/
│   │   │   ├── benchmark_screen.dart
│   │   │   ├── comparison_screen.dart
│   │   │   ├── robustness_screen.dart
│   │   │   └── report_screen.dart
│   │   ├── widgets/
│   │   │   ├── benchmark_catalog.dart
│   │   │   ├── results_summary_card.dart
│   │   │   ├── metric_diff_table.dart
│   │   │   ├── target_comparison_grid.dart
│   │   │   ├── robustness_curve_chart.dart
│   │   │   ├── perturbation_curve_chart.dart
│   │   │   ├── baseline_selector.dart
│   │   │   ├── run_history_timeline.dart
│   │   │   └── report_builder.dart
│   │   ├── providers/
│   │   ├── models/
│   │   └── services/
│   │       └── api_client.dart
│   ├── pubspec.yaml
│   └── test/
├── docker-compose.yml
├── Dockerfile
└── README.md
```
