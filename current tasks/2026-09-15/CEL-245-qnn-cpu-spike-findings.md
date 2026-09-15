# CEL-245: Qualcomm QNN CPU-Backend Spike

**Date:** 2026-09-15  
**Parent context:** [CEL-242](./CEL-242-arm-edge-accelerator-research.md) Phase 2 — Qualcomm QNN CPU path  
**Precedent:** Voyager compile spike ([CEL-237](../2026-09-14/CEL-237-voyager-compiler-phase2-findings.md))

## Executive Summary

Spike **infrastructure is ready** (`make qnn-cpu-spike`), mirroring the Voyager Docker workflow. The pipeline exports shared `yolov8n.onnx`, runs `qnn-onnx-converter` → `qnn-model-lib-generator` → `qnn-net-run` on `libQnnCpu.so`, and records per-step wall times in `timing_summary.txt`.

**Blocked on SDK acquisition:** direct Community-edition ZIP downloads from Qualcomm Software Center return **HTTP 403** from this environment (local Mac and dev host `192.168.2.90`). A free Qualcomm developer account + portal download (or QPM install) is required before the spike can produce real conversion/timing numbers.

---

## What Was Built

| Artifact | Purpose |
|---|---|
| [`scripts/qnn_fetch_qairt.sh`](../../scripts/qnn_fetch_qairt.sh) | Best-effort Community SDK zip fetch + extract |
| [`scripts/qnn_cpu_spike.sh`](../../scripts/qnn_cpu_spike.sh) | Docker wrapper (mounts `QAIRT_SDK_ROOT`, writes to `./qnn-cpu-out/`) |
| [`scripts/qnn_cpu_inner.sh`](../../scripts/qnn_cpu_inner.sh) | In-container convert + CPU inference + timing capture |
| `make qnn-fetch-qairt` | Entry point for SDK download helper |
| `make qnn-cpu-spike` | One-command spike once `QAIRT_SDK_ROOT` is set |

### Pipeline (once SDK is available)

1. **Export ONNX** — `YOLO("yolov8n.pt").export(format="onnx", imgsz=640)` (same model family as Voyager spikes)
2. **Convert** — `qnn-onnx-converter --input_network yolov8n.onnx --output_path yolov8n.cpp --input_dim <name> <shape>`
3. **Compile** — `qnn-model-lib-generator -c yolov8n.cpp -b yolov8n.bin -o model_libs -t x86_64-linux-clang`
4. **Run** — `qnn-net-run --backend libQnnCpu.so --model <lib*.so> --input_list input_list.txt`
5. **Timing** — `export_timing.txt`, `convert_timing.txt`, `compile_timing.txt`, `infer_timing.txt`, `timing_summary.txt`

---

## SDK Acquisition Blocker

| Attempt | Result |
|---|---|
| `softwarecenter.qualcomm.com/.../v2.47.0.260601.zip` | 301 → `apigwx-aws.qualcomm.com` → **403** |
| `apigwx-aws.qualcomm.com/.../v2.42.0.251225.zip` | **403** |
| Dev host `192.168.2.90` same URLs | **403** |
| `qpm-cli` on agent host | Not installed |

**Unblock path (board/user):**

1. Register free Qualcomm ID: https://myaccount.qualcomm.com/signup
2. Download **Qualcomm AI Runtime - Community Edition** from Qualcomm Software Center (docs list v2.47.0.260601 as current Community drop)
3. Extract and export:
   ```bash
   export QAIRT_SDK_ROOT=/path/to/qairt/2.47.0.260601
   make qnn-cpu-spike
   ```

Alternative: install via QPM CLI after license activation (`qpm-cli --license-activate qualcomm_ai_runtime_sdk`).

---

## Environment Notes

| Constraint | Impact |
|---|---|
| macOS ARM64 dev machine | Spike runs in `ubuntu:22.04` Docker (same as Voyager) |
| QAIRT verified on Ubuntu 22.04 + Python 3.10 | Inner script uses 22.04 system Python + SDK `check-*-dependency` helpers |
| `clang-14` required for x86 model libs | Installed in inner script before `qnn-model-lib-generator` |
| CPU timings are **non-representative** of HTP/DSP | Expected — this spike validates conversion + host CPU path only |
| Large SDK (~GB) | Do **not** bake into `suite_api` image; mount or cache on CI runner |

---

## Comparison to Voyager Spike Shape

| Step | Voyager (CEL-237) | QNN (CEL-245) |
|---|---|---|
| Model | YOLOv8n | YOLOv8n (shared) |
| Container | `ubuntu:22.04` | `ubuntu:22.04` |
| SDK install | `pip install axelera-devkit` (public PyPI) | QAIRT zip (portal gate) |
| Compile tool | `export(format="axelera")` | `qnn-onnx-converter` + `qnn-model-lib-generator` |
| No-hardware run | Pipeline Builder `op.onnx_model(cpu)` | `qnn-net-run` + `libQnnCpu.so` |
| Make target | `make voyager-compile-spike` | `make qnn-cpu-spike` |

---

## Next Steps

1. **Unblock:** obtain QAIRT SDK via portal/QPM and rerun `make qnn-cpu-spike`
2. Record real `timing_summary.txt` numbers in this doc
3. Decide whether YOLOv8n converts cleanly or needs a simpler ONNX (MobileNet) for Phase 2 CI
4. Hardware follow-up (HTP/DSP on Snapdragon board/phone) — separate spike after procurement

---

## References

- [CEL-242 ARM edge accelerator research](./CEL-242-arm-edge-accelerator-research.md)
- [Qualcomm QNN model porting](https://docs.qualcomm.com/bundle/publicresource/topics/80-70015-15B/qnn-port-model.html)
- [QAIRT Linux setup](https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-10/linux_setup.html)
- [QAIRT install (Community direct download)](https://docs.qualcomm.com/doc/80-80022-15B/topic/qairt-install.html)
