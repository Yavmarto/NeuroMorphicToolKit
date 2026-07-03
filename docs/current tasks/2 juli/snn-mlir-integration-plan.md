# Goal: Integrate `snn-mlir` Compiler Toolchain into NMTK

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
