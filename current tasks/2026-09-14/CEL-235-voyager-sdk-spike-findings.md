# CEL-235: Voyager SDK No-Hardware Spike Findings

**Date:** 2026-09-14  
**Parent:** [CEL-234](/CEL/issues/CEL-234) — Integrate Axelera Voyager SDK  
**Repo:** https://github.com/axelera-ai-hub/voyager-sdk

## Executive Summary

The Voyager SDK **compiler-only + Pipeline Builder CPU path works end-to-end without Metis hardware**. We validated `op.onnx_model('yolov8n.onnx', provider='cpu')` on a YOLOv8n ONNX model exported from Ultralytics, with 5 detections on the standard `bus.jpg` test image.

**Recommendation:** Proceed with a phased integration into NMTK — start with the CPU-only Pipeline Builder path for development/CI and model validation; defer AIPU runtime integration until Metis hardware is available on a target host.

---

## Host Compatibility

| Environment | OS | Python | Result |
|-------------|-----|--------|--------|
| Local dev Mac (ARM64) | macOS 26.6 | 3.14 | **Not supported** — SDK docs require Ubuntu 22.04+ Linux |
| Dev host `192.168.2.90` | Ubuntu 26.04 x86_64 | 3.14 only | **Python version blocker** — SDK supports 3.10–3.13 only |
| Ubuntu 22.04 Docker on dev host | Ubuntu 22.04 | 3.10.12 | **Works** — used for all spike validation |

**Blockers for native dev-host install:**
1. Ubuntu 26.04 is newer than documented/tested (22.04/24.04 apt repos); Docker 22.04 sidesteps this.
2. System Python is 3.14; SDK max is 3.13. Need `python3.12` via deadsnakes or containerized workflow.

---

## What Works Without Metis Hardware

| Capability | Package | Verified | Notes |
|------------|---------|----------|-------|
| `pip install axelera-devkit` (compiler-only) | axelera-devkit | ✅ | Imports cleanly; no driver/board needed |
| `pip install axelera-rt` (runtime libs) | axelera-rt | ✅ | Installs without Metis driver |
| Pipeline Builder `op.*` operators (pre/post) | axelera-rt | ✅ | letterbox, decode, nms, ax_detection all work |
| **CPU inference via `op.onnx_model()`** | axelera-rt + onnxruntime | ✅ | **Primary no-hardware path** — 5 detections on bus.jpg |
| Ultralytics ONNX export | ultralytics | ✅ | `YOLO("yolov8n.pt").export(format="onnx")` |
| Model Zoo catalog download | axdownloadmodel | ✅ | CLI available after devkit install; downloads `.axm` files |
| YAML/GStreamer `inference.py` eval (CPU fallback) | axelera-rt | ⚠️ Not tested this spike | Docs describe CPU fallback with `--disable-opencl --disable-vaapi` |

### CPU Spike Command (reproducible)

Run inside `ubuntu:22.04` container:

```bash
pip install --no-cache-dir \
  --extra-index-url https://software.axelera.ai/artifactory/api/pypi/axelera-pypi/simple \
  axelera-devkit axelera-rt opencv-python-headless onnxruntime ultralytics

# Export ONNX from Model Zoo weights
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt').export(format='onnx')"

# Pipeline Builder CPU inference
python -c "
from axelera.runtime import op
import cv2, urllib.request
urllib.request.urlretrieve('https://github.com/ultralytics/assets/releases/download/v0.0.0/bus.jpg', 'bus.jpg')
image = cv2.imread('bus.jpg')
pipeline = op.seq(
    op.color_convert('RGB', src='BGR'),
    op.letterbox(640, 640),
    op.to_tensor(),
    op.onnx_model('yolov8n.onnx', provider='cpu'),
    op.decode_detections(algo='yolov8', num_classes=80),
    op.nms(),
    op.to_image_space(),
    op.ax_detection(class_id_type=op.CocoClasses),
)
dets = pipeline(image)
print(f'{len(dets)} detections')
for d in dets[:5]: print(d.class_id.name, d.score)
"
```

**Result:** 5 detections (4 person, 1 bus) — PASS.

---

## What Hard-Requires Metis Hardware

| Capability | Why hardware is required | Observed behavior without board |
|------------|--------------------------|--------------------------------|
| `axdevice` / Metis kernel driver (`metis-dkms`) | PCIe device enumeration + firmware | `ERROR: No target device found in lspci output` |
| `op.load('model.axm')` AIPU inference | `.axm` runs on Metis AIPU via axelera-rt | Expected to fail (not fully re-tested after axm download; docs + axdevice error confirm) |
| `op.load('model.axe')` bundled AIPU pipelines | Same as above | Requires AIPU |
| Ultralytics `model.export(format='axelera')` | Compiles to `.axm` for AIPU | Compiler may work without board, but **running** `.axm` needs AIPU |
| `create_inference_stream()` / `examples/application.py` | Production GStreamer pipelines target AIPU | Requires runtime + device |
| `axmonitor` device metrics | Reads Metis telemetry | N/A without device |
| Full-performance benchmarks | AIPU is the target accelerator | CPU path is explicitly alpha / not for production benchmarks |

**No full AIPU emulator exists.** There is no software substitute for Metis inference throughput or driver-level device management.

---

## Integration Recommendation for NMTK

### Phase 1 — Dev/CI without hardware (now)

1. Add optional `axelera-devkit` + `axelera-rt` as a **dev dependency group** (not in production backend image unless needed).
2. Use **Pipeline Builder + `op.onnx_model(provider='cpu')`** for:
   - Model compatibility smoke tests in CI
   - Pre/post-processing operator validation
   - Prototyping detection pipelines before hardware arrives
3. Run in **Ubuntu 22.04 container** (pin Python 3.10–3.12) — do not rely on host Python 3.14.
4. Document container-based workflow in neurochip deployment docs.

### Phase 2 — Compiler integration (needs dev box, no board)

1. Use `axelera-devkit` compiler-only on a Linux CI runner to compile ONNX → `.axm`.
2. Store compiled `.axm` artifacts in model registry / Box builds.
3. Validate accuracy with CPU ONNX path before shipping `.axm` to hardware targets.

### Phase 3 — AIPU runtime (blocked on hardware)

1. Procure Metis board (PCIe/M.2) for `192.168.2.90` or a dedicated Axelera test host.
2. Install `metis-dkms` driver + `axelera-rt` runtime.
3. Integrate `op.load('.axm')` and/or `create_inference_stream()` into Neurochip worker.
4. Benchmark against CPU baseline; Pipeline Builder is **alpha** — YAML pipelines may be better for production throughput until PB reaches GA.

### Do not integrate yet

- Do not add Voyager SDK to the default `suite_api` Docker image — large dependency, Linux-only, Artifactory index required.
- Do not block CEL-234 on hardware — CPU path unblocks API/design work.

---

## Blockers and Risks

| Blocker | Severity | Mitigation |
|---------|----------|------------|
| No Metis board on dev infra | High for Phase 3 | Order hardware or use Axelera dev kit; CPU path unblocks Phase 1–2 |
| Dev host Python 3.14 | Medium | Docker `ubuntu:22.04` or install `python3.12` via deadsnakes |
| macOS dev machines unsupported | Medium | All Voyager work must use Linux container or remote Linux host |
| Pipeline Builder is **Alpha** | Medium | Use for prototyping; production may need YAML pipeline API |
| Private PyPI index (`software.axelera.ai`) | Low | Requires network access + index URL in pip config; no auth observed |
| Ubuntu 26.04 untested | Low | Use 22.04 container until Axelera documents 26.04 support |

---

## Next Steps for CEL-234

1. Fold these findings into [CEL-234](/CEL/issues/CEL-234) description/plan.
2. Decide: containerized Voyager dev environment vs. deadsnakes Python 3.12 on dev host.
3. Spike a minimal Neurochip adapter wrapping Pipeline Builder CPU detection (optional child issue).
4. Track Metis hardware procurement separately if AIPU runtime is on the roadmap.

---

## References

- SDK install: `docs/user-guides/sdk-install.md` — compiler-only vs runtime-only table
- Pipeline Builder CPU: `docs/reference/pipeline-builder/api/axelera.runtime.op.inference.md` — `op.onnx_model(provider='cpu')`
- Pipeline overview: `docs/reference/pipeline-builder/pipeline-overview.md`
- Examples: `examples/pipeline_builder/detection.py`, `docs/tutorials/examples/application.md` (requires full SDK + hardware for AIPU path)
