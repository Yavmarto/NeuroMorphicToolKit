# snnTorch Simulator End-to-End Plan

> **Date**: 2026-05-14  
> **Scope**: Run a CNL-authored NIR graph in a snnTorch simulator path. This is an inference/simulation plan, not a training workflow.

---

## Goal

Make snnTorch a real simulator backend in the user workflow:

`CNL model -> Generate NIR -> Run in snnTorch simulator -> Inspect spikes`

The first implementation should not depend on training. The user should be able to run the exact NIR graph produced from CNL with fixed weights and deterministic stimulus.

---

## Current Starting Point

Already present:

- `neurocnl.neurocnl.compile.compile_to_nir(...)` returns a `nir.NIRGraph`.
- `SnnTorchAdapter` exists at `neurocnl/neurocnl/training/snntorch_adapter.py`.
- The generic training API lists `snntorch` capabilities.
- Optional dependencies are modeled as training extras: `torch` and `snntorch`.

Key gaps:

- The current snnTorch path is a training adapter over a toy fixture, not a NIR simulator.
- There is no `NIRGraph -> snnTorch module` runtime adapter.
- There is no endpoint that runs CNL-generated NIR in snnTorch.
- The UI should not frame this as training when the user is only simulating.
- Local environment currently reports `torch` missing, so dependency preflight must be explicit.

---

## User Experience Target

In Studio:

1. User writes or opens a CNL model.
2. User clicks **Generate NIR**.
3. User opens **Run Simulation**.
4. Backend selector shows `snnTorch simulator`, status `Ready` or `Install torch + snnTorch`, and note `Runs fixed-weight NIR inference with surrogate-gradient framework primitives; no training is performed`.
5. User chooses timesteps and stimulus.
6. User clicks **Run**.
7. Result panel shows output spike raster, optional membrane traces, final spike counts, runtime duration, and warnings for approximated NIR semantics.

When torch or snnTorch is missing:

- The backend returns `optional_dependency_missing`.
- The UI keeps Generate NIR usable.
- The simulation run is blocked with a clear dependency message.

---

## Architecture

Preferred path:

```text
NeuroCNL backend
  CNL spec
    -> compile_to_nir()
    -> NIR support classification for snnTorch
    -> NIRGraph to fixed-weight torch.nn.Module
    -> snnTorch timestep loop
    -> shared SimulatorRunResult
```

Do not reuse the current `SnnTorchAdapter` directly for simulation. It is a training adapter and should remain under the training domain. Add a simulator adapter beside the runtime/simulator contracts.

---

## NIR to snnTorch Mapping

Initial supported subset:

- `nir.Input`
- `nir.Output`
- `nir.Linear`
- `nir.LIF` or `nir.CubaLIF`
- feed-forward graphs with deterministic ordering
- explicit dense weights from CNL matrix declarations

Initial unsupported subset:

- recurrent cycles unless a deterministic unroll contract is added
- metadata-only semantics such as advisory STDP, neuromodulation, and homeostasis
- unsupported delay semantics unless the simulator explicitly approximates them and marks the result approximate
- convolutions, pooling, flattening, and batchnorm unless intentionally added later

Recommended execution model:

- Convert each `nir.Linear` to `torch.nn.Linear` with fixed weights.
- Convert each LIF population to `snntorch.Leaky`.
- Run for `timesteps`.
- Inject input spikes from the shared stimulus contract.
- Collect spikes and membrane traces at named output populations.

---

## Implementation Plan

### Task 1: Add a snnTorch simulator adapter

Files likely involved:

- `neurocnl/neurocnl/runtime/snntorch_simulator.py`
- `neurocnl/neurocnl/runtime/nir_support.py`
- `neurocnl/backend/app/routers/simulators.py`
- `neurocnl/backend/tests/test_simulators_router.py`

Steps:

- [ ] Add `SnnTorchSimulatorAdapter` behind the shared simulator contract.
- [ ] Keep dependency checks separate from the training adapter.
- [ ] Return capability status for `torch` and `snntorch`.
- [ ] Normalize results into the shared `SimulatorRunResult`.

### Task 2: Implement NIR graph ordering and validation

Files likely involved:

- `neurocnl/neurocnl/runtime/nir_graph_ordering.py`
- `neurocnl/neurocnl/tests/test_snntorch_simulator.py`

Steps:

- [ ] Topologically sort supported feed-forward NIR graphs.
- [ ] Identify named input and output populations.
- [ ] Reject cycles and ambiguous graphs with structured diagnostics.
- [ ] Prove exact matrix weights survive into the torch module.

### Task 3: Implement fixed-weight snnTorch execution

Files likely involved:

- `neurocnl/neurocnl/runtime/snntorch_simulator.py`
- `neurocnl/neurocnl/runtime/stimulus.py`
- `neurocnl/neurocnl/tests/test_snntorch_simulator.py`

Steps:

- [ ] Build fixed `torch.nn.Linear` layers from `nir.Linear`.
- [ ] Build `snntorch.Leaky` layers from NIR LIF nodes.
- [ ] Execute a timestep loop with deterministic input spikes.
- [ ] Return spike times per output neuron.
- [ ] Include membrane traces when cheap and reliable.

### Task 4: Integrate with backend simulator API

Files likely involved:

- `neurocnl/backend/app/routers/simulators.py`
- `neurocnl/backend/app/main.py`
- `neurocnl/backend/tests/test_simulators_router.py`

Steps:

- [ ] Add `snntorch_sim` to simulator capabilities.
- [ ] Support `POST /api/simulators/run` for `backend_name: "snntorch_sim"`.
- [ ] Keep errors structured for missing dependencies, unsupported graph, and runtime failure.

### Task 5: Add Studio integration

Files likely involved:

- `neurocnl/frontend/lib/`
- `neurocnl/frontend/test/`

Steps:

- [ ] Show `snnTorch simulator` separately from training.
- [ ] Show dependency status before run.
- [ ] Render spike raster, spike counts, traces, and warnings.
- [ ] Add copy that says no training is happening in this simulator run.

---

## Verification

Default environment without torch:

```bash
cd neurocnl
PYTHONPATH=. pytest backend/tests/test_simulators_router.py -q
```

With training/snnTorch extras installed:

```bash
cd neurocnl
PYTHONPATH=. pytest neurocnl/tests/test_snntorch_simulator.py backend/tests/test_simulators_router.py -q
```

Regression gate for exact CNL matrix weights:

```bash
cd neurocnl
PYTHONPATH=. pytest neurocnl/export/test_nir_integration.py -q
```

Frontend gate after UI integration:

```bash
cd neurocnl/frontend
flutter test
```

---

## Acceptance Criteria

- A user can compile a supported CNL model to NIR and run that graph in snnTorch simulator mode.
- snnTorch simulation is clearly separate from snnTorch training.
- Missing `torch` or `snntorch` returns actionable unavailable status.
- Unsupported NIR graphs fail before simulation.
- Exact CNL-authored weights are preserved in the snnTorch module.
- The output uses the shared simulator result schema.
- Studio shows spikes, warnings, and support status without implying hardware deployment or training.
