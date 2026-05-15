# CNL to NIR Simulator Contract Plan

> **Date**: 2026-05-14  
> **Scope**: Define the shared user-facing and backend contract for creating a CNL model, compiling it to NIR, and running that same NIR graph in simulator backends.

---

## Goal

A user should be able to stay inside CNL Studio and complete this flow:

1. Create or open a CNL model.
2. Click **Generate NIR** and see the compiled topology.
3. Select **Run Simulation**.
4. Choose **Lava simulator** or **snnTorch simulator**.
5. Provide simple runtime settings.
6. Run the simulation and inspect spikes, voltages where available, timing, warnings, and the exact backend support level.

This plan creates the common contract that the Lava and snnTorch simulator plans build on. It is not a hardware deployment plan and it is not a training-workflow plan.

---

## User Experience Target

The Studio should show a compact pipeline:

`CNL -> Validate -> Generate NIR -> Simulate`

The simulation panel should include:

- backend selector: `Lava simulator`, `snnTorch simulator`
- runtime settings: timesteps, input stimulus source, random seed, and optional input population override
- read-only support status: `ready`, `missing optional dependency`, `unsupported NIR primitive`, `approximate semantics`, or `failed`
- result tabs: spike raster, output summary, backend log, and NIR support notes

### First successful demo

The first end-to-end demo should use a small model that both simulators can run:

```text
The input population MUST contain 2 excitatory neurons
The output population MUST contain 2 excitatory neurons
The connection from input to output MUST use weight matrix [[1.0, 0.0], [0.0, 1.0]]
The input neuron MUST fire ONLY IF membrane potential exceeds 1.0
The output neuron MUST fire ONLY IF membrane potential exceeds 1.0
```

Expected user-visible behavior:

- Generate NIR succeeds.
- The NIR graph shows input/output populations and one exact 2 by 2 dense connection.
- Lava simulator can run the graph when the Lava runtime is available.
- snnTorch simulator can run the same graph when torch and snnTorch are available.
- If either dependency is missing, the UI shows an actionable install/preflight message without failing the base app.
- Results show at least output spike times per neuron and a deterministic run summary.

---

## Product Boundary

In scope:

- CNL authoring for the simulator-supported subset.
- `CNL -> NetworkIR -> NIRGraph` as the only compiler spine.
- A shared simulator request/response contract.
- Simulator support classification before execution.
- Deterministic fixture input for repeatable local runs.
- Clear UI labeling for exact, approximate, unsupported, and missing-dependency states.

Out of scope:

- Loihi 2 hardware execution.
- Training loops.
- Benchmark scoring.
- Quantization-aware deployment.
- Multi-chip partitioning.
- Any path that bypasses `NetworkIR` and writes runtime-specific graphs directly from CNL.

---

## Required Shared Contracts

### Simulator capability response

Every simulator backend should expose:

- `backend_name`
- `display_name`
- `available`
- `unavailable_reason`
- `supported_nir_nodes`
- `unsupported_nir_nodes`
- `approximate_semantics`
- `max_timesteps`
- `supports_spike_output`
- `supports_voltage_trace`
- `requires_optional_dependency`

### Simulation request

Recommended shape:

```json
{
  "spec": "CNL text",
  "backend_name": "lava_sim",
  "timesteps": 100,
  "seed": 1,
  "stimulus": {
    "type": "spike_train",
    "population": "input",
    "spikes": {
      "0": [0, 10, 20],
      "1": [5, 15, 25]
    }
  }
}
```

The backend compiles `spec` to NIR internally so the request cannot drift from the compiled artifact shown in Studio. Later, a workspace-scoped cached NIR id can be added, but the first implementation should prefer correctness and reproducibility.

### Simulation response

Recommended shape:

```json
{
  "backend_name": "lava_sim",
  "status": "completed",
  "support_level": "exact",
  "timesteps": 100,
  "duration_seconds": 0.02,
  "spikes": {
    "output": {
      "0": [10, 20],
      "1": [15, 25]
    }
  },
  "voltages": {},
  "warnings": [],
  "nir_summary": {
    "node_count": 4,
    "edge_count": 3,
    "unsupported_nodes": []
  },
  "metadata": {
    "seed": 1,
    "runtime_mode": "simulator"
  }
}
```

Failures should use the same structured diagnostic style as validate/generate/export.

---

## NIR and CNL Gaps to Close First

1. Define the simulator-supported NIR subset.
   Initial subset: `nir.Input`, `nir.Output`, `nir.LIF` or `nir.CubaLIF`, `nir.Linear`, and simple delay only if both simulators can honor it or label it approximate.

2. Add a runtime support classifier.
   Input: `nir.NIRGraph`, backend name. Output: exact, approximate, unsupported, plus diagnostics.

3. Normalize input/output population discovery.
   The runtime layer needs deterministic names for input and output populations. Synthetic NIR boundary nodes should not confuse simulator population names.

4. Add deterministic stimulus generation.
   If the user does not provide a stimulus, generate a small seeded spike train for the first input population.

5. Make results serializable and backend-neutral.
   Use one response schema for Lava and snnTorch. Keep backend-specific details in `metadata`.

---

## Implementation Order

### Task 1: Define simulator contracts

Files likely involved:

- `neurocnl/backend/app/schemas/`
- `neurocnl/backend/app/routers/`
- `neurocnl/neurocnl/simulation/` or `neurocnl/neurocnl/runtime/`
- `neurocnl/neurocnl/backends/capabilities.py`
- `neurocnl/docs/support_matrix.md`

Steps:

- [ ] Add `SimulatorCapability`, `SimulatorRunRequest`, `SimulatorRunResult`, and `SimulatorDiagnostic` contracts.
- [ ] Add shared enum values for status and support level.
- [ ] Add tests for serialization and error payload shape.

### Task 2: Add NIR runtime support classification

Files likely involved:

- `neurocnl/neurocnl/runtime/nir_support.py`
- `neurocnl/neurocnl/ir/test_materializer.py`
- `neurocnl/neurocnl/tests/`

Steps:

- [ ] Implement backend-specific support classification for `lava_sim` and `snntorch_sim`.
- [ ] Return unsupported diagnostics for NIR primitives the simulator cannot execute honestly.
- [ ] Add regression tests for exact, approximate, and unsupported graphs.

### Task 3: Add shared stimulus helpers

Files likely involved:

- `neurocnl/neurocnl/runtime/stimulus.py`
- `neurocnl/neurocnl/tests/`

Steps:

- [ ] Parse explicit spike-train stimuli.
- [ ] Generate deterministic default stimuli from seed, timesteps, and input population size.
- [ ] Validate population names and neuron indices before runtime dispatch.

### Task 4: Add backend-neutral API endpoints

Files likely involved:

- `neurocnl/backend/app/routers/simulators.py`
- `neurocnl/backend/app/main.py`
- `neurocnl/backend/tests/test_simulators_router.py`

Steps:

- [ ] Add `GET /api/simulators/capabilities`.
- [ ] Add `POST /api/simulators/run`.
- [ ] Preserve the old `/api/simulate` unsupported response until the new simulator surface is ready.
- [ ] Make missing optional dependencies return 422 or 503 with structured diagnostics, not 500.

### Task 5: Add Studio simulation UI

Files likely involved:

- `neurocnl/frontend/lib/`
- `neurocnl/frontend/test/`

Steps:

- [ ] Add a simulation panel after NIR generation.
- [ ] Show backend capability status before the user runs anything.
- [ ] Render spike rasters and warnings from the backend-neutral result.
- [ ] Keep missing-dependency and unsupported-graph states visible and non-destructive.

---

## Verification

Focused backend gates:

```bash
cd neurocnl
PYTHONPATH=. pytest backend/tests/test_simulators_router.py neurocnl/tests -q
```

Existing NIR gates:

```bash
cd neurocnl
PYTHONPATH=. pytest neurocnl/export/test_nir_integration.py neurocnl/ir/test_materializer.py -q
```

Frontend gate when the Studio surface is implemented:

```bash
cd neurocnl/frontend
flutter test
```

Suite-visible integration gates after API/UI wiring:

```bash
python3 -m pytest tests/integration/test_cross_module.py
python3 -m pytest tests/integration/test_teensy_e2e.py
```

---

## Acceptance Criteria

- A user can create a supported CNL model and generate NIR from it.
- The Studio shows simulator availability for Lava and snnTorch before execution.
- The same compiled NIR graph is used for both simulator backends.
- Unsupported NIR semantics fail before runtime dispatch with structured diagnostics.
- Missing optional dependencies never crash the base backend.
- Both simulator result payloads share one response shape.
- The UI makes clear whether the run was exact, approximate, unsupported, failed, or blocked by missing dependencies.
