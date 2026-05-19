# Requirements Document

## Introduction

The NIR-VM (NIR-Native Virtual Hardware) is a software emulation layer that acts as a virtual backend within the `Neurochip` and `neurocnl` modules. It allows users to test and profile neuromorphic models natively within NMTK without requiring physical hardware deployment. Users can execute `.nir` graphs, validate behavior, and analyze performance estimates before deploying to real chips.

The feature consists of two workstreams:
1. **Bit-Accurate NIR Executor** — a standalone runtime within `Neurochip` that executes `.nir` graphs with cycle-accurate timing simulation, registered as a virtual backend alongside real hardware backends (Akida, Loihi, Xylo, Teensy, PYNQ).
2. **Telemetry Dashboard** — extensions to `nmtk_ui_core` and the `neurocnl` CNL Studio frontend that visualize spike-train activity and power consumption estimates during virtual execution.

---

## Glossary

- **NIR_VM**: The NIR-Native Virtual Hardware backend; a software emulator registered as a `HardwareProfile` with `id: "nir_vm"` in the `Neurochip` target registry.
- **NIR_Executor**: The Python service within `Neurochip` responsible for loading a `.nir` graph and simulating it cycle-by-cycle, producing spike-train outputs and telemetry data.
- **NIR_Graph**: A `.nir` file produced by `neurocnl`'s `CNL → IR → NIR` pipeline, encoded in the standard NIR HDF5 format.
- **Spike_Train**: A time-ordered sequence of binary firing events per neuron, indexed by timestep.
- **Virtual_Execution_Session**: A single invocation of the NIR_Executor for a given NIR_Graph, producing a `VirtualExecutionResult`.
- **VirtualExecutionResult**: The complete output of a Virtual_Execution_Session, containing spike trains, timing metadata, and power estimates.
- **Power_Estimate**: A derived energy-consumption figure (in pJ) calculated from the NIR_VM's hardware profile fields `pj_per_spike_op` and `power_envelope_mw`, analogous to the estimates produced by the existing `power_estimator.py` service.
- **Telemetry_Dashboard**: The `NirVmTelemetryPanel` widget and its supporting provider added to `neurocnl`'s CNL Studio frontend.
- **SpikeRasterPlot**: A 2D chart widget displaying neuron index on the Y-axis and timestep on the X-axis, with a marker at each spike event.
- **Execution_Job**: A background task managed by the `Neurochip` backend that runs a Virtual_Execution_Session and streams progress via Server-Sent Events (SSE).
- **Bit_Accuracy**: The property that the NIR_Executor's LIF neuron state updates produce membrane potential values and spike decisions identical, within floating-point tolerance, to the reference equations encoded in the NIR graph's node parameters.

---

## Requirements

### Requirement 1: NIR-VM Hardware Profile Registration

**User Story:** As a neuromorphic engineer, I want to select the NIR-VM as a deployment target in the `Neurochip` target gallery, so that I can run virtual executions through the same interface I use for real hardware.

#### Acceptance Criteria

1. THE `Neurochip` backend SHALL include a hardware profile JSON file at `neurochip/targets/nir_vm.json` whose contents pass Pydantic validation against the `HardwareProfile` model in `neurochip/contracts/hardware_contracts.py`, including the `validate_memory_fit` and `validate_bit_widths` validators, with `access` set to `"open"` and `id` set to `"nir_vm"`.
2. WHEN `GET /api/neurochip/targets` is called, THE `Neurochip` backend SHALL include an entry with `id: "nir_vm"` in the returned list alongside all other registered targets.
3. WHEN `GET /api/neurochip/targets/nir_vm` is called, THE `Neurochip` backend SHALL return the full NIR_VM profile including `pj_per_spike_op` and `power_envelope_mw` fields with non-zero values derived from a reference LIF simulation configuration.
4. THE NIR_VM profile registration code SHALL NOT contain any `import` of `pynq`, `akida`, `lava`, or any other hardware-only package; the `Neurochip` backend SHALL start and serve the NIR_VM profile without errors when no physical hardware is attached.

---

### Requirement 2: Bit-Accurate NIR Graph Execution

**User Story:** As a researcher, I want to execute a `.nir` graph against the NIR-VM backend and receive neuron-level spike-train outputs, so that I can validate my model's behavior before committing to real hardware.

#### Acceptance Criteria

1. WHEN `POST /api/neurochip/nir_vm/execute` is submitted with a valid `.nir` file, THE `NIR_Executor` SHALL load the graph using the `nir` Python package and begin a Virtual_Execution_Session.
2. THE `NIR_Executor` SHALL update each LIF node's membrane potential at every timestep using: `v[t] = v[t-1] * exp(-dt / tau) + I[t]`, where `tau` is the node's `tau` parameter and `dt` is the simulation timestep in seconds.
3. WHEN a neuron's membrane potential `v[t]` reaches or exceeds `v_threshold`, THE `NIR_Executor` SHALL record a spike event for that neuron at timestep `t` and immediately reset `v[t]` to `0.0`.
4. WHEN a `nir.Delay` node is present, THE `NIR_Executor` SHALL hold the upstream spike vector in a FIFO buffer of length equal to the delay node's `delay` parameter (in timesteps) before forwarding it to downstream nodes.
5. THE `NIR_Executor` SHALL multiply `nir.Linear` weight matrices by incoming spike vectors at each timestep to produce synaptic input current `I[t]` for downstream LIF nodes.
6. WHEN the Virtual_Execution_Session completes, THE `NIR_Executor` SHALL return a `VirtualExecutionResult` containing: spike trains per population as arrays of shape `[n_neurons, n_timesteps]`, total spike count per population, simulation wall-clock duration in milliseconds, and power estimate in pJ.
7. THE `NIR_Executor` SHALL produce identical `VirtualExecutionResult` outputs when the same NIR_Graph is executed twice with identical input spike vectors (determinism property); this applies to graphs containing only `nir.Input`, `nir.Output`, `nir.LIF`, `nir.Linear`, and `nir.Delay` nodes.
8. IF a submitted `.nir` file contains any node type not in `{nir.Input, nir.Output, nir.LIF, nir.Linear, nir.Delay}`, THEN THE `NIR_Executor` SHALL return HTTP 422 with a JSON error listing each unsupported node type by its class name.
9. IF a submitted file is not a valid HDF5 file or does not conform to the NIR schema, THEN THE `NIR_Executor` SHALL return HTTP 422 with a descriptive error message identifying the parse failure by field or node name.
10. IF any LIF node's `tau` parameter is zero or negative, THEN THE `NIR_Executor` SHALL return HTTP 422 with a message identifying the invalid node and the constraint before beginning the simulation.

---

### Requirement 3: Bit-Accuracy Validation Against Neurochip Hardware Interface

**User Story:** As a hardware engineer, I want the NIR-VM's simulation output to be verifiable against the existing `Neurochip` constraint analysis results, so that I can trust the virtual execution is consistent with real hardware profiles.

#### Acceptance Criteria

1. THE `NIR_Executor` SHALL expose `POST /api/neurochip/nir_vm/validate` accepting a `.nir` file body and a `target_id` query parameter; upon invocation it SHALL run a Virtual_Execution_Session and then invoke the existing `POST /api/neurochip/analyze` logic for the same graph against `target_id`, returning both results in a single response.
2. WHEN `target_id` is `"nir_vm"` and the NIR_Graph's total neuron count ≤ the NIR_VM profile's `neuron_capacity`, THE `ConstraintReport` SHALL set `neuron_fit: "pass"`; WHEN the count exceeds `neuron_capacity`, it SHALL set `neuron_fit: "fail"`.
3. WHEN `target_id` is a real hardware target (e.g., `"loihi2"`, `"akida"`), THE `Neurochip` backend SHALL return the `ConstraintReport` produced by the existing constraint analyzer without modification.
4. WHEN a Virtual_Execution_Session completes successfully, THE `NIR_Executor` SHALL record a `DeploymentRecord` via `POST /api/neurochip/deployments` with `target_id: "nir_vm"` and `firmware_version` equal to the NIR_VM executor's current semantic version string.
5. IF `POST /api/neurochip/deployments` returns a non-2xx status, THE `NIR_Executor` SHALL log the failure at WARN level and still return the `VirtualExecutionResult` to the caller without surfacing the deployment-record failure.

---

### Requirement 4: Power Consumption Estimation

**User Story:** As a power-constrained systems engineer, I want the NIR-VM to produce power consumption estimates after virtual execution, so that I can evaluate whether my network fits within a target chip's power envelope before deploying.

#### Acceptance Criteria

1. WHEN a Virtual_Execution_Session completes, THE `NIR_Executor` SHALL compute `total_energy_pj = total_spike_count * pj_per_spike_op` using `pj_per_spike_op` read from `neurochip/targets/nir_vm.json`.
2. THE `VirtualExecutionResult` SHALL include a `population_energy` map where each entry's value is `population_spike_count * pj_per_spike_op`.
3. WHEN `total_spike_count > 0` AND `simulation_duration_ms > 0` AND `(total_energy_pj / simulation_duration_ms * 1000) > power_envelope_mw`, THE `VirtualExecutionResult` SHALL include `power_envelope_exceeded: true`; in all other cases (including zero spikes or zero duration), THE `VirtualExecutionResult` SHALL include `power_envelope_exceeded: false`.
4. THE `Neurochip` backend SHALL include the string `"estimated — validate on real hardware for production"` in a `disclaimer` field on every API response that contains power figures.
5. WHEN `POST /api/neurochip/estimate/power` is called with `target_id: "nir_vm"`, THE `Neurochip` backend SHALL use the NIR_VM profile's `pj_per_spike_op` and `power_envelope_mw` values for the calculation.
6. IF `pj_per_spike_op` is missing or zero in the NIR_VM profile, THEN THE `NIR_Executor` SHALL return HTTP 500 with a message identifying the missing profile field before beginning execution.

---

### Requirement 5: Streaming Execution Progress via SSE

**User Story:** As a developer running long simulations, I want to receive real-time progress updates during NIR-VM execution, so that I can monitor progress without polling.

#### Acceptance Criteria

1. WHEN `POST /api/neurochip/nir_vm/execute?stream=true` is submitted, THE `Neurochip` backend SHALL return a `text/event-stream` response with one SSE progress event per completed batch of timesteps; the batch size SHALL be configurable between 1 and 1000 timesteps, defaulting to 100.
2. WHEN streaming, each SSE progress event's `data` field SHALL be a JSON object containing: `timestep` (integer, current last timestep in batch), `total_timesteps` (integer), `spike_counts_so_far` (object mapping population name to integer), and `percent_complete` (float 0.0–100.0).
3. WHEN the Virtual_Execution_Session completes, THE `Neurochip` backend SHALL emit a final SSE event with `event: complete` and `data` containing the full serialized `VirtualExecutionResult`.
4. WHEN a client disconnects or an internal error occurs during streaming, THE `Neurochip` backend SHALL stop simulation processing and release all associated memory within 5 seconds.
5. THE `Neurochip` backend SHALL emit a heartbeat SSE comment line (`: heartbeat`) every 15 seconds during an active stream.
6. IF the SSE stream cannot be established (e.g., response write error at stream start), THEN THE `Neurochip` backend SHALL return HTTP 500 with a JSON error body before any SSE bytes are written.

---

### Requirement 6: Telemetry Dashboard — Spike-Train Visualization

**User Story:** As a neuroscience researcher, I want to see a live spike-raster plot of my network's activity during virtual execution directly in CNL Studio, so that I can inspect population dynamics without leaving the design tool.

#### Acceptance Criteria

1. THE `neurocnl` frontend SHALL include a `NirVmTelemetryPanel` widget at `neurocnl/frontend/lib/widgets/nir_vm_telemetry_panel.dart`.
2. THE `NirVmTelemetryPanel` SHALL render a `SpikeRasterPlot` with neuron index on the Y-axis, timestep on the X-axis, a visible dot or tick marker at each spike event, and one distinct color per population derived from the population name.
3. WHEN a `VirtualExecutionResult` is passed to the panel, THE `NirVmTelemetryPanel` SHALL populate the `SpikeRasterPlot` within 500 ms; IF the spike train data is malformed or missing required fields, THE panel SHALL display an error message and leave the chart area empty.
4. THE `NirVmTelemetryPanel` SHALL display a summary row showing: total spike count, simulation duration in ms, and estimated total energy in pJ (or `"N/A"` if the energy field is absent from the result).
5. WHEN the total spike count in the `VirtualExecutionResult` exceeds 10,000, THE `NirVmTelemetryPanel` SHALL render only the first 10,000 spike events by ascending timestep order and display a non-dismissible truncation notice; IF truncation itself fails, THE panel SHALL display an error state without rendering any spike data.
6. THE `NirVmTelemetryPanel` widget SHALL accept all data via constructor parameters and callbacks, with zero imports from `provider`, `flutter_riverpod`, or any module-specific app state package.
7. WHERE the NIR-VM target is active in CNL Studio's hardware panel, THE `neurocnl` frontend SHALL display `NirVmTelemetryPanel` as a dedicated tab within the hardware panel or simulation dashboard area.

---

### Requirement 7: Telemetry Dashboard — Power Estimate Visualization

**User Story:** As a power-constrained systems engineer, I want to see a breakdown of estimated power consumption per population during virtual execution in CNL Studio, so that I can identify which populations consume the most energy.

#### Acceptance Criteria

1. THE `NirVmTelemetryPanel` SHALL render an `EnergyBarChart` with one bar per population, where each bar's value is the corresponding `population_energy_pj` from the `VirtualExecutionResult`; IF the result contains zero populations, the chart area SHALL display an informational message instead of an empty chart.
2. WHEN `power_envelope_exceeded` is `true` in the `VirtualExecutionResult`, THE `NirVmTelemetryPanel` SHALL render a warning indicator using amber color and `Icons.warning_amber_rounded` positioned above the `EnergyBarChart`.
3. THE `NirVmTelemetryPanel` SHALL display: the sum of all `population_energy_pj` values labelled "Total estimated energy (pJ)", the NIR_VM profile's `power_envelope_mw` value labelled "Power envelope (mW)", and the string `"estimated — validate on real hardware for production"` as a visible disclaimer.
4. WHEN no `VirtualExecutionResult` has been passed to the panel, THE `NirVmTelemetryPanel` SHALL render only an empty-state message (e.g., "Run a virtual execution to see telemetry") with no charts, no energy values, no power envelope reference, and no disclaimer text visible.

---

### Requirement 8: NIR-VM Registration in `neurocnl` Studio Target Registry

**User Story:** As a CNL Studio user, I want the NIR-VM to appear in the Studio's target selection panel alongside real hardware targets, so that I can start a virtual execution without leaving the Studio workflow.

#### Acceptance Criteria

1. THE `StudioTargetRegistryService` SHALL expose a `fetchNirVmProfile()` method that calls `GET /api/neurochip/targets/nir_vm` and returns the parsed `HardwareProfile` on HTTP 200.
2. WHEN `fetchNirVmProfile()` returns successfully, THE CNL Studio hardware panel SHALL display a target card labelled `"NIR-VM (Virtual)"` with a visual treatment (icon or badge) that is observably different from physical hardware target cards.
3. WHEN the NIR-VM target card is selected AND a compiled NIR_Graph is available in the current Studio session, THE CNL Studio SHALL display a `"Run on NIR-VM"` button that on click submits the compiled graph to `POST /api/neurochip/nir_vm/execute`; WHEN no compiled NIR_Graph is available, THE button SHALL be disabled with a tooltip stating that compilation is required first.
4. IF `fetchNirVmProfile()` fails (network error, HTTP non-200, or parse error), THEN THE CNL Studio hardware panel SHALL display the NIR-VM card in a visually distinct error state with a human-readable failure message and a "Retry" button; this error state SHALL not affect the display or behaviour of other target cards.

---

### Requirement 9: Existing Neurochip Contract Compliance

**User Story:** As a platform maintainer, I want the NIR-VM backend to comply with all existing `Neurochip` contract invariants, so that adding a virtual backend does not break existing hardware workflows or test suites.

#### Acceptance Criteria

1. THE `neurochip/targets/nir_vm.json` profile SHALL pass Pydantic validation by `HardwareProfile` including `validate_memory_fit` (neuron_capacity consistent with on_chip_memory_kb) and `validate_bit_widths` (weight_bit_widths is a non-empty list of positive integers).
2. THE `Neurochip` backend SHALL pass all pre-existing tests in `neurochip/tests/` without modification to any existing test file after the NIR-VM feature is introduced; the NIR-VM feature is considered "introduced" when `neurochip/targets/nir_vm.json` and `NIR_Executor` are present.
3. THE NIR-VM feature code SHALL NOT contain a top-level `import` of `pynq`, `akida`, `lava`, or any other hardware-only optional dependency; the `Neurochip` backend SHALL start and serve the NIR-VM profile successfully on a machine where none of those packages are installed.
4. WHEN the `Neurochip` backend starts with `NIR_VM_ENABLED=true` (or equivalent configuration flag), THE `GET /health` endpoint SHALL return HTTP 200 and the launcher doctor (`python3 scripts/launcher_control_service.py --doctor --json`) SHALL report `fatalCount: 0`.

---

### Requirement 10: Round-Trip NIR Graph Fidelity

**User Story:** As a researcher, I want a NIR_Graph compiled from CNL via `neurocnl` to execute identically on the NIR-VM as it would when the same graph is re-imported and re-compiled, so that I can trust the execution result reflects my CNL specification.

#### Acceptance Criteria

1. THE `NIR_Executor` SHALL produce spike trains that are element-wise identical (exact integer equality for spike presence/absence per neuron per timestep) when the same valid NIR_Graph (containing only the supported node types) is executed twice with the same input spike vectors (round-trip execution property).
2. WHEN a NIR_Graph is saved to disk and reloaded using the `nir` Python package, then executed on the NIR_Executor with the same inputs as the original graph, THE resulting spike trains SHALL be element-wise identical to those from executing the original in-memory graph.
3. WHEN `neurocnl` performs a `NIR → CNL → NIR` round-trip on a NIR_Graph and both the original and regenerated graphs are executed on the NIR_Executor with identical inputs, THE spike trains SHALL be element-wise identical; this property requires that the `neurocnl` round-trip preserves all LIF parameters, Linear weights, and Delay values without loss.
4. THE `NIR_Executor` SHALL serialize `VirtualExecutionResult` to JSON and deserialize it back to a `VirtualExecutionResult` such that all integer and string fields are exactly equal and all float fields are equal within IEEE 754 double precision (serialization round-trip property).
