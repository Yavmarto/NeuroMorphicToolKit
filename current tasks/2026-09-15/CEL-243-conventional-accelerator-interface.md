# CEL-243: Shared ConventionalAccelerator Interface

**Date:** 2026-09-15  
**Parent proposal:** [CEL-242](./CEL-242-arm-edge-accelerator-research.md) Section 2

## Delivered

- `Neurochip/neurochip/conventional_accelerators/` — `ConventionalAccelerator` ABC with `export` / `compile` / `benchmark`, pydantic manifest schema, registry, Voyager backend wrapping existing spike scripts.
- `Neurochip/neurochip/conventional_targets/*.json` — manifests for Voyager (wired), Jetson, Qualcomm QNN, Coral (manifest-only until spikes land).
- `Neurochip/neurochip/tests/test_conventional_accelerator.py` — 7 unit tests (manifest load, Voyager wiring, benchmark log parser).

## Usage

```python
from neurochip.conventional_accelerators import get_accelerator, list_manifests
from neurochip.conventional_accelerators.interface import CompileRequest

for manifest in list_manifests():
    print(manifest.id, manifest.compile_cmd)

voyager = get_accelerator("voyager_axelera")
# compile runs `bash scripts/voyager_compile_spike.sh` from repo root
# result = voyager.compile(CompileRequest(intermediate_path=None, output_dir=Path("./voyager-compile-out")))
```

Existing Make targets unchanged: `make voyager-compile-spike` / `make voyager-aipu-spike`.

## Verification

```bash
cd Neurochip && poetry run pytest neurochip/tests/test_conventional_accelerator.py -q
```
