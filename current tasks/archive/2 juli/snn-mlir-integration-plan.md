# Goal: Integrate `snn-mlir` Compiler Toolchain into NMTK

## Verified Implementation Status (2026-07-04)

**Classification: PARTIAL — Phases 1, 2, and 4 substantially implemented (uncommitted/WIP); Phase 3 (edge deployment) NOT STARTED.**

Actual implementation diverges from the plan's exact file paths but delivers
the same functionality through different, more consistent locations:

- **Phase 1 (toolchain/env setup) — DONE, different location than planned.**
  Instead of `Dockerfile.snn-mlir` at repo root, there is a dedicated worker
  service `workers/snn_mlir_compiler/` (`Dockerfile`, `main.py`, `codegen.py`,
  `test_codegen.py`) — a FastAPI worker that lowers `.nir` -> MLIR via
  `snn-opt` and emits `main.c`/`snn_data.h`. It's wired into
  `docker-compose.yml` as service `snn-mlir-compiler` (port 8007, lines
  171-177), with `SNN_MLIR_COMPILER_WORKER_URL` env vars set for the
  `neurocnl` and `neurosim` services (lines 23, 74). The `snn-mlir` pip
  package is added to `neurocnl/pyproject.toml:62` (`studio` extra), not
  `requirements-docs.txt` as the plan specified.
- **Phase 2 (frontend/backend export integration) — DONE, different file
  names than planned.** The plan named `export_panel.dart` /
  `export_routes.py`, which don't exist under those names; the actual files
  are `neurocnl/frontend/lib/widgets/canvas/export_dialog.dart` (has an
  `'mlir'` dropdown option, "SNN-MLIR (.mlir)", lines 113-114) and
  `neurocnl/backend/app/routers/export.py` (`if request.format == "mlir":`
  branch, line 190, calling `neurocnl.generation.snn_mlir_generator.generate_mlir`).
  A parallel implementation exists in `neurocnl/neurosim/app/services/export_generators.py:147`
  (`generate_mlir_export`). The core generator
  `neurocnl/neurocnl/generation/snn_mlir_generator.py` and its test
  (`test_snn_mlir_generator.py`) exist and are currently **untracked** in the
  `neurocnl` submodule (`git status` shows `??`), i.e. work in progress, not
  yet committed.
- **Phase 3 (edge deployment, Neuro-Dream-Hand/Neurochip) — NOT STARTED.**
  `docs/Opus-dev-pipeline/neuro-dream-hand/contracts/hardware_contracts.py`,
  `Neuro-Dream-Hand/neurodreamhand/contracts/hardware_contracts.py`, and
  `Neurochip/neurochip/contracts/hardware_contracts.py` have zero mentions of
  `mlir`, `main.c`, or `snn_data.h`. A repo-wide search for `index_bits`
  (the planned 32-bit-index deployment parameter) returns no matches
  anywhere. No `Neurochip/backend/deployment.py` file exists at the path the
  plan names (Neurochip's deployment code lives under
  `Neurochip/neurochip/app/routers/deployments.py` /
  `services/deployment_store.py`, none of which reference snn-mlir).
- **Phase 4 (Neurobench fast-sim runner) — DONE, uncommitted/WIP.** The
  planned `Neurobench/backend/runners/snn_mlir_runner.py` exists at
  `Neurobench/neurobench/app/runners/snn_mlir_runner.py`
  (`SnnMlirBenchmarkRunner`, sends a compiled graph to the
  `snn-mlir-compiler` worker and measures native binary latency/spike count;
  accuracy is explicitly `None` — no labeled dataset wired up yet, a
  documented gap in the runner's own docstring). A router
  (`Neurobench/neurobench/app/routers/snn_mlir.py`, `POST /run`) and a test
  (`Neurobench/neurobench/tests/test_snn_mlir_runner.py`) also exist.
  `git status` in the `Neurobench` submodule shows these three files as
  untracked/uncommitted and `app/config.py`/`app/main.py` as modified —
  active WIP, not yet merged.
- Could not execute the new pytest suites in this environment — collection
  fails on an unrelated, pre-existing `matplotlib`/`nengo` circular-import
  error in the local miniconda install, not a defect in the snn-mlir code
  itself.

**What's still missing:** all of Phase 3 (edge deployment integration is
entirely absent), committing the Phase 1/2/4 work (currently untracked/WIP in
the `neurocnl` and `Neurobench` submodules), wiring real accuracy scoring into
the Neurobench runner, and the plan's two "Open Questions" (dedicated Docker
container vs. inline install — answered as dedicated container; deprecation
strategy for `Neuro-Dream-Hand` custom codegen — unanswered, since Phase 3
hasn't started).

---

This plan outlines the steps to integrate the `snn-mlir` compiler into the NeuroMorphicToolKit (NMTK) ecosystem. By doing so, NMTK will gain the ability to instantly compile exported `.nir` graphs into highly optimized, standalone C/LLVM executables for rapid simulation and edge device deployment, bypassing Python overhead.

## User Review Required

> [!IMPORTANT]
> Integrating `snn-mlir` will significantly simplify our deployment pipeline, particularly for `Neuro-Dream-Hand` and `Neurochip`. We will be able to deprecate any custom C/C++ generation scripts for edge devices in favor of `snn-mlir`'s robust C code generation (`main.c`, `snn_data.h`).

> [!WARNING]
> Building the full `snn-mlir` toolchain requires LLVM. We need to decide whether to ship the compiled LLVM/snn-opt binaries in a new Docker container (`Dockerfile.snn-mlir`) or append them to an existing worker.

## Open Questions

1. **Docker Architecture:** Should we create a dedicated Docker container for the MLIR compiler toolchain, or install the `snn-mlir` Python frontend directly into the existing `neurocnl` / `neurochip` backend workers?
2. **Deprecation Strategy:** Can we immediately deprecate custom microcontroller code generation in `Neuro-Dream-Hand`, or should we run both in parallel for a validation phase?

## Proposed Changes

---

### Phase 1: Toolchain and Environment Setup

- Update the backend Python environment to include the `snn-mlir` pip package.
- Set up the underlying `snn-opt` / LLVM build tools within the Docker Compose infrastructure to handle the final lowering to executable code.

#### [MODIFY] [requirements-docs.txt](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/requirements-docs.txt)
Add `snn-mlir` to the necessary `requirements.txt` or `pyproject.toml` files to ensure the Python frontend is available to the workers.

#### [NEW] [Dockerfile.snn-mlir](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docker/Dockerfile.snn-mlir)
Create a new Dockerfile (or update an existing one) to pre-compile and host the `snn-opt` compiler toolchain.

---

### Phase 2: NeuroStudio / Frontend Integration

Surface the new compiler target to users so they can export directly to C/LLVM from the visual canvas.

#### [MODIFY] [neurocnl/frontend/lib/widgets/export_panel.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/export_panel.dart)
Add `snn-mlir (Native Executable)` and `snn-mlir (Quantized Edge C-code)` as formal target options in the export UI alongside standard `.nir`.

#### [MODIFY] [neurocnl/backend/api/export_routes.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/api/export_routes.py)
Wire up the export endpoints to generate the standard `.nir` graph, then pass it to `snn_mlir.export(quantize=True/False)`.

---

### Phase 3: Edge Deployment (`Neuro-Dream-Hand` & `Neurochip`)

Replace custom Teensy C++ generation with the standardized MLIR C runtime.

#### [MODIFY] [docs/Opus-dev-pipeline/neuro-dream-hand/contracts/hardware_contracts.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neuro-dream-hand/contracts/hardware_contracts.py)
Update hardware contracts to expect `main.c` and `snn_data.h` from `snn-mlir`'s `_codegen.export()` instead of custom generator functions.

#### [MODIFY] [Neurochip/backend/deployment.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/backend/deployment.py)
Add the orchestration logic to compile the network for microcontrollers using 32-bit indices (`index_bits=32`) as natively supported by `snn-mlir`.

---

### Phase 4: Fast Simulation Backend (`Neurobench`)

Utilize the CPU executable for rapid benchmarking, bypassing SnnTorch/Python bottlenecks.

#### [MODIFY] [Neurobench/backend/runners/snn_mlir_runner.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurobench/backend/runners/snn_mlir_runner.py)
Create a new benchmark runner that invokes the compiled `snn-mlir` binary to measure raw inference latency and accuracy in C.

## Verification Plan

### Automated Tests
- Run integration tests validating that a simple `.nir` file successfully lowers to `network.mlir` using the Python API.
- Verify that the C files `main.c` and `snn_data.h` are correctly emitted for the `Neuro-Dream-Hand` edge target.

### Manual Verification
- Deploy a small visual network from `NeuroStudio`, export it via the `snn-mlir (Quantized)` option, and verify the resulting C code compiles successfully using standard `gcc`/`clang`.
