# CEL-246: Jetson TensorRT Compile-Only Validation (Phase 3)

**Date:** 2026-09-15  
**Parent:** [CEL-240](/CEL/issues/CEL-240) — Wider Edge Computing/ARM  
**Research:** [CEL-242](./CEL-242-arm-edge-accelerator-research.md) Phase 3  
**Precedent:** [CEL-237](../2026-09-14/CEL-237-voyager-compiler-phase2-findings.md) Voyager compile spike

## Goal

Prove that a standard NMTK export path (YOLOv8n → ONNX) is **TensorRT-parseable** on any host with an NVIDIA GPU — without a Jetson board. This catches unsupported ops and shape issues before Jetson hardware procurement (Phase 4a).

**Important constraint:** a `.engine` built on a desktop GPU is **not** portable to Jetson. This phase validates graph compatibility only; Jetson-specific engines must be built on-target or in an L4T cross-compile container matching JetPack.

## Workflow

```bash
make jetson-compile-spike
# or: bash scripts/jetson_compile_spike.sh ./jetson-compile-out
```

### Requirements

| Requirement | Why |
|---|---|
| Docker + nvidia-container-toolkit | Runs official TensorRT 24.08 image with GPU passthrough |
| Any NVIDIA GPU (desktop or server) | `trtexec` and ORT TensorRT EP need CUDA |
| Network (first run) | Pull `nvcr.io/nvidia/tensorrt:24.08-py3` + pip deps + YOLO weights |

**Not required:** Jetson board, JetPack, L4T.

### Steps inside the container

| Step | What | Pass criteria |
|---|---|---|
| 1 | `YOLO("yolov8n.pt").export(format="onnx", opset=17)` | `yolov8n.onnx` > 1 KB |
| 2 | `onnx.checker.check_model` | Structural ONNX OK |
| 3 | `trtexec --onnx=... --skipInference --saveEngine=...` | `.engine` file produced |
| 4 | ORT `TensorrtExecutionProvider` session + one inference | Session builds and runs |

Exit code `2` from the outer script means **no GPU host available** (blocked), not a graph failure.

## Run Results (2026-09-15)

| Host | GPU | Docker | Result |
|---|---|---|---|
| Dev Mac (Paperclip agent, CEL-249) | None (`nvidia-smi` absent) | Daemon unavailable in agent sandbox | **BLOCKED** — cannot run container |
| `192.168.2.90` dev backend (CEL-249 re-check) | None (`nvidia-smi` absent) | OK | **BLOCKED** — `jetson_compile_spike.sh` exit **2** (no GPU visible to Docker) |
| `dev.noomi.space` + siblings | — | — | **UNREACHABLE** — SSH no route to host from agent network |

**Unblock:** any Linux host with NVIDIA GPU + `nvidia-container-toolkit`. Run `make jetson-compile-spike`, then fill the success row below.

| Host | TensorRT version | Engine file | Engine size | ONNX size | Notes |
|---|---|---|---|---|---|
| *(pending first green run)* | | `yolov8n_desktop.engine` | | `yolov8n.onnx` | Desktop GPU engine is not Jetson-portable |

**Next:** run `make jetson-compile-spike` on any Linux box with an NVIDIA GPU (e.g. self-hosted CI `gpu` runner, GitHub larger GPU runner, or a workstation). Update the success table with engine size and TensorRT version on first green run.

## Comparison to Voyager Phase 2

| | Voyager (CEL-237) | Jetson (CEL-246) |
|---|---|---|
| Container | `ubuntu:22.04` + pip | `nvcr.io/nvidia/tensorrt:24.08-py3` |
| GPU needed | No (compiler-only) | Yes (TensorRT parse) |
| Output artifact | `.axm` (Metis-ready) | `.engine` (desktop GPU — not Jetson-portable) |
| Hardware spike | Phase 3 Metis board | Phase 4a Jetson Orin |

## NMTK Integration Recommendation

| When | What | Where |
|---|---|---|
| **Now** | `make jetson-compile-spike` + this doc | Root `Makefile` + `scripts/` |
| **After first green GPU run** | Record engine size + TRT version in this doc | Findings table above |
| **Phase 4a** | Build engine on Jetson / L4T container + benchmark | `workers/neurochip_hw/` (future) |
| **Not yet** | Bake TensorRT into `suite_api` image | Large, GPU-specific, long compile |

## Scripts

- [`scripts/jetson_compile_spike.sh`](../scripts/jetson_compile_spike.sh) — outer wrapper (GPU detect + Docker)
- [`scripts/jetson_compile_inner.sh`](../scripts/jetson_compile_inner.sh) — export + trtexec + ORT TRT EP

## References

- [CEL-242 Jetson research](./CEL-242-arm-edge-accelerator-research.md)
- [Ultralytics Jetson guide](https://docs.ultralytics.com/guides/nvidia-jetson)
- NVIDIA TensorRT container: `nvcr.io/nvidia/tensorrt`
