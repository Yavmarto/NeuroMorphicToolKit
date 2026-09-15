# CEL-237: Voyager SDK Compiler-Only Pipeline (Phase 2)

**Date:** 2026-09-14  
**Parent:** [CEL-234](/CEL/issues/CEL-234) — Integrate Axelera Voyager SDK  
**Depends on:** [CEL-236](/CEL/issues/CEL-236) (Phase 1 dev deps), [CEL-235](/CEL/issues/CEL-235) (no-hardware spike)

## Executive Summary

The Voyager SDK **compiler-only path works end-to-end without Metis hardware**. We compiled YOLOv8n to a valid `.axm` artifact (19 MB) inside Ubuntu 22.04 Docker using `axelera-devkit` only — no runtime driver, no board.

**Recommended compile path:** `YOLO("yolov8n.pt").export(format="axelera")` via Ultralytics integration. Raw `axcompile` on default Ultralytics ONNX (opset 18) fails on unsupported `Split` ops.

**CI/dev workflow:** `make voyager-compile-spike` → `scripts/voyager_compile_spike.sh` (Ubuntu 22.04 container, ~6 min on dev host i5).

---

## What Was Verified

| Step | Command / path | Result |
|------|----------------|--------|
| Install compiler-only | `pip install axelera-devkit` | ✅ Import OK, `axcompile` on PATH |
| Export ONNX | `YOLO("yolov8n.pt").export(format="onnx")` | ✅ 12.3 MB `yolov8n.onnx` |
| Direct `axcompile` | `axcompile -i yolov8n.onnx -o compiled_axcompile/` | ❌ Quantization failed — ONNX opset 18 `Split` not supported |
| **Ultralytics AIPU compile** | `YOLO("yolov8n.pt").export(format="axelera")` | ✅ **19 MB `yolov8n.axm`** + metadata |
| Artifact format | `file yolov8n.axm` | Zip archive (Axelera model bundle) |

### Successful compile output

```
yolov8n_axelera_model/
├── yolov8n.axm              # 19,877,459 bytes — Metis-ready compiled model
├── metadata.yaml            # task type, class names, input shape
└── compiler_config_final.toml
```

Compile time: ~315 s (includes coco128 calibration download + INT8 calibration on 128 images). LowerTIR logged a memory-fit warning but export completed successfully.

---

## Compiler Paths Compared

### Path A: Ultralytics `format="axelera"` (recommended for YOLO)

```python
from ultralytics import YOLO
model = YOLO("yolov8n.pt")
model.export(format="axelera")
# → yolov8n_axelera_model/yolov8n.axm
```

- Handles calibration dataset (coco128), INT8 quantization, and compiler config internally.
- Embeds Ultralytics metadata for runtime postprocessing (`op.load()` auto-selects decode).
- **Use this in CI** for YOLO-family models.

### Path B: `axcompile` CLI (generic ONNX)

```bash
axcompile -i model.onnx -o output/
# → output/compiled_model/manifest.json + kernel artifacts
```

- Works for ONNX models the compiler supports.
- **Failed** on default Ultralytics ONNX export because opset 18 `Split` nodes are not implemented in the onnx2torch importer.
- Mitigation: export ONNX at a lower opset, or use Axelera's supported model zoo ONNX, or use the Python compiler API with `extract_ultralytics_metadata()`.

### Path C: Python compiler API

Documented in `voyager-sdk/docs/reference/pipeline-builder/model-compilation.md` — same engine as Path A, for non-Ultralytics frameworks.

---

## Dev / CI Workflow Sketch

### Local or remote Linux host with Docker

```bash
make voyager-compile-spike
# or: bash scripts/voyager_compile_spike.sh ./voyager-compile-out
```

Requirements:
- Docker (daemon running)
- Network access to `software.axelera.ai` PyPI index
- ~2 GB disk for container + deps; ~6 min CPU time per YOLOv8n compile

### Proposed CI integration (not wired yet)

1. **Optional CI job** on `ubuntu-22.04` runner (not macOS, not default backend image):
   - `make voyager-compile-spike`
   - Assert `voyager-compile-out/yolov8n_axelera_model/yolov8n.axm` exists and size > 1 MB
   - Upload `.axm` as build artifact (Box / model registry) — **do not** bake into `suite_api` image

2. **Pre-hardware artifact pipeline:**
   - Developer exports ONNX or trains YOLO → CI compiles to `.axm` → artifact stored for Phase 3 hardware validation

3. **Do not add to default backend Docker image** — large, Linux-only, Artifactory index, long compile times.

---

## NMTK Module Recommendation

| When | What to wire | Where |
|------|--------------|-------|
| **Now (Phase 2)** | `make voyager-compile-spike` + docs | Root Makefile + `scripts/` (done) |
| **Next** | Optional CI job on Linux runner | `.github/workflows/` or dev-update gate |
| **Phase 3 (hardware)** | `op.load('.axm')` in Neurochip worker | `workers/neurochip_hw/` after Metis board procured |
| **Not yet** | Runtime in `suite_api` | Blocked — no Metis on dev infra |

**Verdict:** Compiler-only integration is **ready for dev workflow** via the Make target. Full NMTK module wiring should wait for Phase 3 (AIPU runtime on hardware) — the `.axm` artifact is the handoff point between compile-time and runtime.

---

## Environment Notes

| Constraint | Impact |
|------------|--------|
| macOS ARM64 local Docker | Works with `--platform linux/amd64` if daemon running; validated on dev host x86_64 |
| Dev host Python 3.14 | Irrelevant — compile runs inside Ubuntu 22.04 container |
| No Metis board | Compile works; running `.axm` on AIPU is Phase 3 |
| `axcompile` on raw ONNX | Fails for default Ultralytics ONNX — use `format="axelera"` |

---

## Scripts Added

- [`scripts/voyager_compile_spike.sh`](../scripts/voyager_compile_spike.sh) — outer wrapper (Docker mount)
- [`scripts/voyager_compile_inner.sh`](../scripts/voyager_compile_inner.sh) — in-container compile steps
- `make voyager-compile-spike` — one-command entry point

---

## References

- [CEL-235 findings](./CEL-235-voyager-sdk-spike-findings.md) — CPU inference path (Phase 1)
- Axelera compiler CLI: `docs/reference/compiler/compiler-cli.md`
- Model compilation: `docs/reference/pipeline-builder/model-compilation.md`
- Ultralytics integration: https://docs.ultralytics.com/integrations/axelera/
