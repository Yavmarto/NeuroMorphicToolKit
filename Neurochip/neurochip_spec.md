# NeuroChip — Hardware Deployment & Compilation Toolkit
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

> **Status (2026-05-14):** The standalone Flutter frontend described below was the
> original product plan. The active architecture integrates the NeuroChip backend
> into CNL Studio. Sections describing Flutter screens, Riverpod providers, and
> standalone frontend build are historical and do not reflect the current
> implementation. See `README.md` for the current role of this module.

---

## Overview

NeuroChip is a dedicated tool for compiling, constraining, and deploying SNN models to neuromorphic chips and embedded microcontrollers. It targets neuroscience researchers and SNN algorithm developers who can design networks in simulation but have no experience with chip architectures, weight quantization, memory constraints, or firmware toolchains.

Workflow ownership note:

- NeuroChip owns target-specific execution, packaging, flashing, and diagnostics.
- In the canonical suite workflow, deployment target selection happens earlier in `neurocnl` `Studio`.
- NeuroChip should open in the imported target context by default and offer `Change target` only as an explicit override.
- The suite-level contract for this flow is documented in
  [docs/ADR-claude/0020-studio-owns-deployment-target-selection.md](/NeuroMorphicToolKit/docs/ADR-claude/0020-studio-owns-deployment-target-selection.md).

---

## Repository

`neuro-space/NeuroChip` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package — for CNL parsing, validation, Nengo generation
- `neurodreamhand` Python package — for crossbar export, fault injection, power profiling
- `neuro-flutter-ui` shared Flutter design system package

---

## User Stories

### Target Selection

**NC-T1 · Browse hardware targets**
As a neuroscience researcher unfamiliar with chip architectures,
I want to browse available hardware targets with plain-language descriptions of their capabilities and constraints,
so that I can understand or explicitly override the imported deployment context without reading chip datasheets.

Acceptance criteria:
- Target gallery shows cards for each supported platform: Teensy 4.1, Intel Loihi 2, BrainChip Akida, SpiNNaker, BrainScaleS
- Each card displays: name, photo/icon, neuron capacity, supported neuron models, weight bit-width, on-chip memory, I/O count, power envelope, cost/access notes
- Cards are filterable by: neuron capacity, bit-width, availability (open vs. restricted access)
- Selecting a target loads its hardware profile for constraint analysis
- When opened from `Studio`, the imported target is already selected and visible before the gallery is used

**NC-T2 · Compare targets side by side**
As a product team lead evaluating deployment options,
I want to compare two or more hardware targets on the same network,
so that I can see tradeoffs (capacity, power, latency, quantization loss) at a glance.

Acceptance criteria:
- Multi-select targets → comparison table auto-populates
- Comparison columns: neuron capacity fit, weight quantization required, estimated power, estimated latency, compatibility warnings
- Rows highlight where a target fails constraints (e.g., "Network exceeds neuron capacity — requires partitioning")
- Export comparison as PDF or CSV

### Constraint Analysis

**NC-C1 · Automatic compatibility report**
As a researcher loading my Nengo model,
I want to see an immediate compatibility report for my selected target,
so that I know what needs to change before deployment.

Acceptance criteria:
- Load a network (via CNL spec, Nengo export, or direct from NeuroSim)
- Report shows: neuron count vs. target capacity, weight bit-width vs. target bit-width, memory usage estimate, unsupported features (if any)
- Each constraint is green (pass), yellow (requires modification), or red (incompatible)
- Yellow items link to the relevant tool (e.g., "Weights are 32-bit → open Quantization Explorer")

**NC-C2 · Network partitioning suggestions**
As an engineer deploying a large network to a small target,
I want automatic partitioning suggestions when my network exceeds the target's neuron capacity,
so that I don't have to manually split the network.

Acceptance criteria:
- When neuron count exceeds target capacity, suggest partition strategies: by population, by function, by connectivity clusters
- Show partition diagram with: sub-network boundaries, inter-partition communication overhead, estimated latency impact
- User can accept a suggestion or manually adjust partition boundaries
- Partitioned network exports as multiple deployment packages

### Quantization

**NC-Q1 · Interactive weight quantization explorer**
As a researcher who has never quantized weights,
I want to interactively adjust bit-width and see accuracy impact in real time,
so that I can find the best tradeoff without understanding quantization theory.

Acceptance criteria:
- Slider for bit-width: 2, 4, 6, 8, 16, 32 bits
- Live chart: accuracy metric vs. bit-width curve
- Side-by-side spike raster: original (float32) vs. quantized at selected bit-width
- Accuracy metric is task-specific (e.g., grip stability for prosthetic, classification accuracy for pattern recognition)
- Summary text: "8-bit quantization: 1.2% accuracy loss, 4x memory reduction"

**NC-Q2 · Batch quantization comparison**
As an engineer optimizing for power/area,
I want to run all quantization levels at once and compare in a table,
so that I can present options to my team.

Acceptance criteria:
- "Run All" button runs simulations at 4-bit, 6-bit, 8-bit, 16-bit
- Results table: bit-width, accuracy, memory size, estimated power, spike fidelity score
- Export table as CSV or include in PDF report
- Highlight the Pareto-optimal choices

### Fault Tolerance

**NC-F1 · Fault injection analysis**
As an engineer designing for reliability,
I want to inject hardware faults (dead neurons, stuck-at values, weight noise) and see how my network degrades,
so that I can verify robustness before committing to silicon.

Acceptance criteria:
- Fault types: dead neuron (random N%), stuck-at-zero, stuck-at-max, Gaussian weight noise (configurable sigma)
- Sweep fault rate from 0% to 30% in configurable steps
- Output: robustness curve (accuracy vs. fault rate) with confidence intervals
- Threshold line: "Network maintains >90% accuracy up to X% dead neurons"
- Compare robustness across quantization levels

### Firmware Generation & Deployment

**NC-FW1 · One-click Teensy firmware generation**
As a researcher who has never written C firmware,
I want to click one button to generate compilable Teensy firmware from my validated network,
so that I can deploy to hardware without learning embedded development.

Acceptance criteria:
- "Generate Firmware" button produces a complete Arduino/PlatformIO project: `.ino` file, `network_params.h`, `lif_engine.h`, `README.md`
- Generated code compiles without errors in Arduino IDE or PlatformIO
- `network_params.h` contains all weights, thresholds, time constants as C arrays
- `lif_engine.h` contains the LIF update loop matching the network topology
- README explains: how to compile, how to flash, pin mappings for sensors/actuators

**NC-FW2 · Flash to Teensy via serial**
As an engineer with a Teensy connected via USB,
I want to compile and flash the generated firmware directly from NeuroChip,
so that I don't need to switch to another IDE.

Acceptance criteria:
- Serial port auto-detection shows available Teensy devices
- "Compile & Flash" button triggers PlatformIO build + upload via backend
- Progress indicator: compiling → uploading → verifying → done
- Error messages are human-readable (not raw compiler output)
- Fallback: download the project as a .zip for manual compilation

**NC-FW3 · Loihi 2 deployment package**
As a lab with Loihi 2 access,
I want to generate a complete NxSDK deployment package,
so that I can run my network on Loihi without learning the NxSDK API from scratch.

Acceptance criteria:
- "Export for Loihi 2" generates: NxSDK Python script, crossbar HDF5 file, configuration JSON, README
- Script handles: board allocation, network compilation, spike probe setup, run execution
- HDF5 file contains quantized weights in Loihi crossbar format
- README documents: prerequisites (NxSDK version, board access), how to run, expected output

### Power & Latency Estimation

**NC-P1 · Pre-deployment power estimate**
As a product designer with a power budget,
I want to see estimated energy per inference before deploying,
so that I can verify my network fits within the product's power envelope.

Acceptance criteria:
- Power estimate based on: spike count per inference, target's pJ/spike-op, network topology
- Display: total energy (pJ), per-population breakdown, comparison to target's power envelope
- Warning if estimated power exceeds target's typical operating range
- Estimates are clearly labeled as "estimated — measure on real hardware for production"

**NC-P2 · Latency estimate**
As a real-time systems engineer,
I want worst-case latency estimates for my network on each target,
so that I can verify timing constraints.

Acceptance criteria:
- Latency estimate based on: network depth (longest path in timesteps), target's clock speed, inter-core communication overhead
- Display: best-case, typical, worst-case latency in microseconds
- Comparison across targets in the comparison view

### Deployment Tracking

**NC-DT1 · Deployment log**
As a team managing multiple hardware prototypes,
I want to see a log of what model was deployed to which device, when, and with what parameters,
so that I can reproduce any deployment.

Acceptance criteria:
- Log entry records: timestamp, network CNL spec hash, target, quantization settings, firmware version, serial port/device ID
- Log is searchable and filterable
- Clicking a log entry shows full deployment details and lets you re-deploy the same configuration
- Export log as CSV

---

## Backend Spec

### API Endpoints

All NeuroChip-specific endpoints live under `/api/neurochip/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurochip/targets` | List all hardware target profiles |
| GET | `/api/neurochip/targets/{id}` | Get a specific hardware profile |
| POST | `/api/neurochip/analyze` | Run constraint analysis (network + target → compatibility report) |
| POST | `/api/neurochip/partition` | Suggest network partitioning for a target |
| POST | `/api/neurochip/quantize` | Run quantization analysis at specified bit-widths |
| POST | `/api/neurochip/quantize/batch` | Run all quantization levels and return comparison |
| POST | `/api/neurochip/faults` | Run fault injection sweep |
| POST | `/api/neurochip/estimate/power` | Estimate power consumption for network + target |
| POST | `/api/neurochip/estimate/latency` | Estimate latency for network + target |
| POST | `/api/neurochip/export/teensy` | Generate Teensy firmware project |
| POST | `/api/neurochip/export/loihi` | Generate Loihi 2 NxSDK deployment package |
| POST | `/api/neurochip/export/lava` | Generate Intel Lava deployment script |
| POST | `/api/neurochip/export/neuroml` | Export to NeuroML format |
| GET | `/api/neurochip/serial/ports` | List available serial ports |
| POST | `/api/neurochip/serial/flash` | Compile and flash firmware to connected Teensy |
| GET | `/api/neurochip/serial/flash/{job_id}` | Poll flash job status |
| GET | `/api/neurochip/deployments` | List deployment log entries |
| POST | `/api/neurochip/deployments` | Record a deployment |
| POST | `/api/neurochip/compare` | Compare multiple targets for the same network |

### Data Models

**HardwareProfile**
```python
class HardwareProfile(BaseModel):
    id: str  # e.g., "teensy41"
    name: str  # e.g., "Teensy 4.1"
    manufacturer: str
    description: str  # Plain-language capability summary
    neuron_capacity: int  # Max neurons
    supported_neuron_models: list[str]  # e.g., ["LIF", "AdaptiveLIF"]
    weight_bit_widths: list[int]  # e.g., [8, 16, 32]
    on_chip_memory_kb: int
    io_pins: int
    clock_speed_mhz: float
    power_envelope_mw: float  # Typical operating power
    pj_per_spike_op: float  # Energy per synaptic operation
    access: Literal["open", "academic", "commercial"]  # Availability
    notes: str  # Access instructions, cost, etc.
```

**ConstraintReport**
```python
class ConstraintReport(BaseModel):
    target_id: str
    network_neurons: int
    target_capacity: int
    neuron_fit: Literal["pass", "warn", "fail"]
    weight_bit_width_required: int
    quantization_needed: bool
    memory_usage_kb: float
    memory_available_kb: float
    memory_fit: Literal["pass", "warn", "fail"]
    unsupported_features: list[str]
    warnings: list[str]
    recommendations: list[str]  # Actionable next steps
```

**QuantizationResult**
```python
class QuantizationResult(BaseModel):
    bit_width: int
    accuracy: float  # Task-specific metric, 0-1
    accuracy_loss_pct: float  # vs. float32 baseline
    memory_size_kb: float
    memory_reduction_factor: float
    spike_fidelity: float  # 0-1, how closely quantized spikes match original
    power_estimate_pj: float
```

**FaultSweepResult**
```python
class FaultSweepResult(BaseModel):
    fault_type: str
    fault_rates: list[float]  # e.g., [0.0, 0.05, 0.10, ...]
    accuracies: list[float]  # Accuracy at each fault rate
    accuracy_ci_lower: list[float]  # Confidence interval lower bound
    accuracy_ci_upper: list[float]  # Confidence interval upper bound
    threshold_90pct: float | None  # Fault rate where accuracy drops below 90%
```

**DeploymentRecord**
```python
class DeploymentRecord(BaseModel):
    id: str
    timestamp: str  # ISO 8601
    network_spec_hash: str  # SHA256 of CNL spec
    target_id: str
    quantization_bits: int
    firmware_version: str
    serial_port: str | None
    device_id: str | None
    notes: str | None
```

### Service Architecture

```
NeuroChip Frontend (Flutter)
       |
       | HTTP
       |
NeuroChip Backend (FastAPI)
       |
       ├── neurocnl (CNL parsing, validation, Nengo generation)
       ├── neurodreamhand (crossbar export, fault injection, power profiling)
       ├── platformio (firmware compilation — subprocess call)
       └── pyserial (serial port communication)
```

### Hardware Profiles

Defined as JSON manifests in `neurochip/targets/`:

```
targets/
  teensy41.json
  loihi2.json
  akida.json
  spinnaker.json
  brainscales.json
```

Community can contribute new hardware profiles via PR. Profiles are validated against the `HardwareProfile` schema on load.

---

## Frontend Spec

### Screen Layout

```
┌──────────────────────────────────────────────────────┐
│ Toolbar: [Load Network] [Target: Loihi 2 ▾] [Compare]│
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌─ Constraint Report ─────────────────────────────┐ │
│  │ Neurons: 500 / 131072  ✅                       │ │
│  │ Weights: 32-bit → 8-bit needed  ⚠️  [Quantize]  │ │
│  │ Memory: 48 KB / 2048 KB  ✅                     │ │
│  │ Unsupported: None  ✅                           │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Tabs ──────────────────────────────────────────┐ │
│  │ [Quantization] [Fault Tolerance] [Power/Latency]│ │
│  │                                                  │ │
│  │  (active tab content here)                      │ │
│  │                                                  │ │
│  └──────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Actions ───────────────────────────────────────┐ │
│  │ [Generate Firmware] [Flash to Device] [Export]   │ │
│  └──────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────┤
│ Deployment Log (collapsible)                         │
└──────────────────────────────────────────────────────┘
```

### Key Widgets

| Widget | Purpose |
|---|---|
| `TargetSelector` | Dropdown/gallery for selecting hardware target |
| `ConstraintReportCard` | Color-coded summary of compatibility analysis |
| `QuantizationExplorer` | Slider + live accuracy chart + side-by-side rasters |
| `BatchQuantizationTable` | All bit-widths compared in a sortable table |
| `FaultInjectionPanel` | Fault type/rate configuration + robustness curve chart |
| `PowerLatencyPanel` | Per-population power breakdown + latency estimates |
| `TargetComparisonTable` | Multi-target side-by-side comparison |
| `FirmwareGeneratorPanel` | Configure and trigger firmware generation |
| `FlashProgressIndicator` | Compile → upload → verify progress bar |
| `DeploymentLogTable` | Searchable/filterable deployment history |

### Providers (Riverpod)

| Provider | State |
|---|---|
| `networkProvider` | Loaded network (CNL spec + parsed graph) |
| `targetProvider` | Selected hardware target profile |
| `constraintReportProvider` | Constraint analysis result |
| `quantizationProvider` | Quantization analysis results |
| `faultProvider` | Fault injection sweep results |
| `powerEstimateProvider` | Power/latency estimates |
| `serialPortsProvider` | Available serial ports |
| `flashJobProvider` | Firmware flash job status |
| `deploymentLogProvider` | Deployment history |

---

## File Structure

```
NeuroChip/
├── neurochip/                       # Python backend
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/
│   │   │   ├── targets.py
│   │   │   ├── analysis.py          # Constraint analysis, partitioning
│   │   │   ├── quantization.py
│   │   │   ├── faults.py
│   │   │   ├── estimation.py        # Power/latency
│   │   │   ├── export.py            # Teensy, Loihi, Lava, NeuroML
│   │   │   ├── serial.py            # Port listing, flashing
│   │   │   └── deployments.py       # Deployment log
│   │   ├── schemas/
│   │   │   ├── targets.py
│   │   │   ├── analysis.py
│   │   │   ├── quantization.py
│   │   │   ├── faults.py
│   │   │   ├── estimation.py
│   │   │   └── deployments.py
│   │   └── services/
│   │       ├── constraint_analyzer.py
│   │       ├── partitioner.py
│   │       ├── quantizer.py         # Wraps neurodreamhand crossbar_exporter
│   │       ├── fault_runner.py      # Wraps neurodreamhand fault_injector
│   │       ├── power_estimator.py   # Wraps neurodreamhand power_profiler
│   │       ├── teensy_generator.py  # Firmware code generation
│   │       ├── loihi_generator.py   # NxSDK package generation
│   │       ├── flash_service.py     # PlatformIO build + upload
│   │       └── deployment_store.py  # SQLite deployment log
│   ├── targets/                     # JSON hardware profiles
│   │   ├── teensy41.json
│   │   ├── loihi2.json
│   │   ├── akida.json
│   │   ├── spinnaker.json
│   │   └── brainscales.json
│   ├── firmware_templates/          # C/C++ templates for firmware generation
│   │   ├── teensy/
│   │   │   ├── main.ino.j2
│   │   │   ├── network_params.h.j2
│   │   │   ├── lif_engine.h.j2
│   │   │   └── platformio.ini.j2
│   │   └── loihi/
│   │       ├── deploy.py.j2
│   │       └── config.json.j2
│   ├── pyproject.toml
│   └── tests/
├── frontend/                        # Flutter frontend
│   ├── lib/
│   │   ├── app.dart
│   │   ├── screens/
│   │   │   ├── target_gallery_screen.dart
│   │   │   ├── analysis_screen.dart
│   │   │   ├── comparison_screen.dart
│   │   │   └── deployment_log_screen.dart
│   │   ├── widgets/
│   │   │   ├── target_selector.dart
│   │   │   ├── constraint_report_card.dart
│   │   │   ├── quantization_explorer.dart
│   │   │   ├── fault_injection_panel.dart
│   │   │   ├── power_latency_panel.dart
│   │   │   ├── firmware_generator_panel.dart
│   │   │   ├── flash_progress_indicator.dart
│   │   │   ├── target_comparison_table.dart
│   │   │   └── deployment_log_table.dart
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
