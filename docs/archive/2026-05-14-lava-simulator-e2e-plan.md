# Lava Simulator End-to-End Plan

> **Date**: 2026-05-14  
> **Scope**: Run a CNL-authored NIR graph in the Lava software simulator. This is not a Loihi 2 hardware plan.

---

## Goal

Make Lava a real simulator backend in the user workflow:

`CNL model -> Generate NIR -> Run in Lava simulator -> Inspect spikes`

The implementation should use the existing NIR and Neurochip Lava pieces, but the product promise must stay simulator-focused:

- no physical Loihi 2 board required
- no `Loihi2HwCfg` path in the default user flow
- no deployment ZIP required for the first working simulator path
- missing `lava-nc` should produce a clear unavailable status

---

## Current Starting Point

Already present:

- `neurocnl.neurocnl.compile.compile_to_nir(...)` returns a `nir.NIRGraph`.
- `neurocnl/neurocnl/converter/lava_io.py` can generate Lava code from NIR, build a Neurochip-compatible runtime payload from NIR, and call remote `/compile` and `/run` endpoints.
- `Neurochip/neurochip/app/services/lava_backend.py` can compile and run a structured Lava session.
- `Neurochip/neurochip/app/routers/lava.py` exposes `/compile`, `/run`, and `/stop`.
- Tests cover missing dependency behavior, mocked compile/run success, and remote compile/run payload shape.

Key gaps:

- Lava runtime is not exposed as a first-class NeuroCNL simulator backend.
- The user-facing flow still says simulation is unsupported on the old `/api/simulate` surface.
- The Lava backend needs stronger support classification before dispatch.
- The local environment may need an isolated Python runtime because `lava-nc` is constrained to Python `<3.11` in Neurochip while much of the suite runs on newer Python.
- Results need to be normalized into the shared simulator response shape.

---

## User Experience Target

In Studio:

1. User writes a small CNL model.
2. User clicks **Generate NIR**.
3. User opens **Run Simulation**.
4. Backend selector shows `Lava simulator`, status `Ready` or `Install lava runtime`, and note `Runs in Lava software simulation, not Loihi hardware`.
5. User clicks **Run**.
6. Result panel shows output spike raster, timesteps, runtime duration, generated/default stimulus, and warnings about any approximate semantics.

When `lava-nc` is missing:

- The run button is disabled or returns a structured preflight error.
- The user sees that the CNL and NIR are valid, but the Lava simulator runtime is not installed.
- The app does not imply hardware failure.

---

## Architecture

Preferred path:

```text
NeuroCNL backend
  CNL spec
    -> compile_to_nir()
    -> LavaIO.to_runtime_payload()
    -> Lava simulator dispatch
       -> local Neurochip LavaBackend if available
       -> or isolated lava worker over HTTP
    -> shared SimulatorRunResult
```

The first robust implementation should support an isolated worker because Lava's dependency constraints are awkward for the main NeuroCNL process.

Recommended runtime options:

1. Local in-process adapter for tests and compatible environments.
2. Remote worker URL for real Lava installs.

The response must identify which path was used:

- `runtime_mode: "in_process_lava_sim"`
- `runtime_mode: "remote_lava_sim_worker"`
- `runtime_mode: "unavailable"`

---

## Implementation Plan

### Task 1: Add a Lava simulator adapter in NeuroCNL

Files likely involved:

- `neurocnl/neurocnl/runtime/lava_simulator.py`
- `neurocnl/neurocnl/converter/lava_io.py`
- `neurocnl/backend/app/routers/simulators.py`
- `neurocnl/backend/tests/test_simulators_router.py`

Steps:

- [ ] Add a `LavaSimulatorAdapter` behind the shared simulator contract.
- [ ] Compile CNL to NIR using public `compile_to_nir()`.
- [ ] Convert NIR to a Lava runtime payload with `LavaIO.to_runtime_payload()`.
- [ ] Dispatch to local or remote Lava execution.
- [ ] Normalize output into `SimulatorRunResult`.

### Task 2: Harden Lava support classification

Files likely involved:

- `neurocnl/neurocnl/runtime/nir_support.py`
- `neurocnl/neurocnl/converter/lava_io.py`
- `neurocnl/neurocnl/backends/capabilities.py`

Steps:

- [ ] Classify supported NIR nodes before calling Lava.
- [ ] Treat metadata-only concepts as non-executable unless explicitly mapped.
- [ ] Add diagnostics for unsupported NIR primitives.
- [ ] Ensure `run_config` defaults to simulator mode only.

### Task 3: Make Lava execution deterministic

Files likely involved:

- `Neurochip/neurochip/app/services/lava_backend.py`
- `Neurochip/neurochip/tests/test_lava.py`
- `neurocnl/neurocnl/runtime/stimulus.py`

Steps:

- [ ] Accept explicit input spike trains in the runtime payload.
- [ ] Define how input populations inject spikes into Lava processes.
- [ ] Record the exact stimulus in the result payload.
- [ ] Keep fallback/mock spike output out of production success paths unless explicitly marked `mock`.

### Task 4: Add an isolated Lava worker path

Files likely involved:

- `workers/lava_backend/main.py`
- `Dockerfile.lava`
- `docker-compose.yml`
- `nmtk/neuro_toolkit/assets/modules.json` only if launcher-visible worker orchestration changes

Steps:

- [ ] Define a small HTTP worker API compatible with `LavaIO.compile_remote()` and `run_remote()`.
- [ ] Make the worker image use a Python version compatible with `lava-nc`.
- [ ] Add health/preflight endpoint returning Lava version and runtime mode.
- [ ] Keep the main backend startup independent from this worker.

### Task 5: Add user-facing Studio integration

Files likely involved:

- `neurocnl/frontend/lib/`
- `neurocnl/frontend/test/`

Steps:

- [ ] Show `Lava simulator` as a simulator backend, not a hardware target.
- [ ] Show dependency/preflight state before run.
- [ ] Render Lava result spikes through the shared result panel.
- [ ] Label `Loihi hardware` as out of scope for this flow.

---

## Verification

No-Lava default environment:

```bash
cd neurocnl
PYTHONPATH=. pytest backend/tests/test_simulators_router.py -q
```

Neurochip Lava router/backend tests:

```bash
cd Neurochip
poetry run pytest neurochip/tests/test_lava.py -q
```

With Lava worker available:

```bash
cd neurocnl
PYTHONPATH=. pytest neurocnl/export/test_lava_integration.py -q
```

Manual smoke target:

```bash
curl -s http://127.0.0.1:<lava-worker-port>/health
```

Then run a CNL spec through:

```text
POST /api/simulators/run
backend_name = lava_sim
```

---

## Acceptance Criteria

- A user can compile a supported CNL model to NIR and run that graph in Lava simulator mode.
- The Lava path never requires physical Loihi hardware.
- Missing `lava-nc` returns actionable unavailable/preflight status.
- Unsupported NIR nodes fail before Lava dispatch.
- Lava outputs use the shared simulator result schema.
- The Studio labels Lava as a simulator backend and shows exact/approximate/unsupported status.
- Any remote Lava worker dependency is optional and does not break base NeuroCNL or Neurochip startup.
