# CEL-242: ARM Edge Accelerator Research — Jetson, Qualcomm, Coral/Tensor

**Date:** 2026-09-15
**Parent:** CEL-240 — Wider Edge Computing/ARM
**Precedent:** Axelera Voyager SDK spike (CEL-234/235/237/238) — same export→compile→benchmark shape

Research only. No code, scripts, or dependencies added.

## 1. Per-platform toolchain

### NVIDIA Jetson (TensorRT)

- **Export path:** train in PyTorch → export ONNX (opset 12–17 depending on TensorRT version) → `trtexec` or the TensorRT Python API builds a `.engine` file.
- **Key constraint:** a TensorRT engine is tied to the exact GPU architecture and TensorRT/CUDA version it was built on. An engine built on an x86 desktop GPU will **not** run on a Jetson's iGPU — engines must be built on the target board (or in an NVIDIA-provided L4T cross-compile container matching the Jetson's JetPack version).
- **Compiler-only path without a board:** partial. You can validate that an ONNX graph is TensorRT-parseable (op coverage, shape inference) using `onnxruntime` with the TensorRT execution provider on any x86 machine with an NVIDIA GPU, or run `trtexec --onnx=... --skipInference` to catch unsupported ops. This proves export/graph compatibility but produces no artifact usable on real Jetson hardware and no real timing numbers.
- **Hardware need:** required for both the final compiled artifact and any real benchmark. No practical Jetson emulator exists.
- **Cost:** Jetson Orin Nano dev kit ≈ $250–$500. Cheapest hardware requirement of the three.
- **2026 status:** actively developed; JetPack 6.2 (Orin) and 7.x (Thor/Blackwell) are current, INT8 quantization has known gaps on TensorRT 10.x. ([Ultralytics Jetson guide](https://docs.ultralytics.com/guides/nvidia-jetson), [NVIDIA forums](https://forums.developer.nvidia.com/t/tensorrt-engine-produces-distorted-outputs-on-jetson-orin-nx-jetpack-6-2-ampere-but-matches-onnx-on-dgx-spark-jetpack-7-0-grace-blackwell/366014))

### Qualcomm (SNPE / QNN)

- **Export path:** ONNX (or TFLite/PyTorch via converter) → `qnn-onnx-converter` (or legacy `snpe-onnx-to-dlc`) → target-specific context binary via `qnn-context-binary-generator` → run with `qnn-net-run`.
- **SDK status:** SNPE is being superseded by QNN/QAIRT (Qualcomm AI Runtime); Qualcomm and ONNX Runtime both point new integrations at QNN. Treat SNPE as legacy, target QNN. ([Qualcomm QAIRT docs](https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-10/SNPE_general_overview.html), [ONNX Runtime SNPE EP discussion](https://github.com/microsoft/onnxruntime/discussions/16214))
- **Compiler-only path without a board:** yes — the QNN SDK ships an x86 Linux CPU backend (`libQnnCpu.so`) plus `qnn-net-run` in a simulator/reference mode, so conversion + graph validation + a non-representative CPU-path timing run work without a Snapdragon device. This is the closest available analogue to Voyager Phase 1/2.
- **Hardware need:** representative accelerator (HTP/DSP) benchmarks require an actual Snapdragon device — a dev kit board (e.g. Qualcomm RB3/RB5) or an Android phone with `adb push`-based deployment. Licensing/registration for the full QAIRT SDK download is required (Qualcomm developer account, no cost, but a registration gate).
- **Cost:** Snapdragon dev boards run $150–$400; a mid-range Android phone can substitute for early validation.

### Google Coral / Tensor (TFLite / Edge TPU)

- **Export path:** TensorFlow/Keras or PyTorch-via-`ai-edge-torch` → TFLite (int8 quantized) → `edgetpu_compiler` for Coral, or bundle as a LiteRT model with the NNAPI/Tensor delegate for Pixel's Google Tensor NPU.
- **Compiler-only path without a board:** yes, and it's the cheapest of the three — `edgetpu_compiler` runs on any x86/ARM Linux host with no accelerator attached; it only fails to run inference, not compile.
- **Critical finding — do not plan around Coral hardware:** the Coral product line is **discontinued and effectively abandoned by Google**. Core libraries haven't been updated since ~2022, the upstream `gasket` kernel driver was archived in April 2026, and it does not run on Linux kernels newer than 6.2 without community patches. Community projects (e.g. Frigate) keep it alive, but this is an end-of-life supply-chain risk, not an actively maintained vendor path. ([Frigate discussion](https://github.com/blakeblackshear/frigate/discussions/18564), [Coral FAQ](https://gweb-coral-full.uc.r.appspot.com/docs/edgetpu/faq/))
- **Google Tensor is a different target than Coral**, despite the shared "Tensor" name in the parent issue: it's the NPU inside Pixel phones, reached only via an Android app using LiteRT + the NNAPI/Tensor delegate — not a headless dev-board flow. It's actively maintained but requires Android app packaging and a physical Pixel phone; there is no server-side or embedded-Linux path to it.
- **Recommendation:** treat "Coral" (compiler-only, cheap, EOL hardware) and "Google Tensor" (active, but Android-app-only, no compiler-only path) as two distinct, smaller efforts rather than one platform — see rollout below.

## 2. Shared backend interface: extract now, but scoped narrowly

Neurochip's existing pattern (`neurochip/targets/*.json` + a bespoke Python backend/router per device, e.g. `pynq_z2.json` + `test_pynq_backend_*`) is built for **neuromorphic** hardware: fields like `neuron_capacity`, `synapse_capacity`, `overlay_id`, `weight_bit_widths` describe SNN-specific properties that don't apply to Jetson/Qualcomm/Coral at all. Reusing that JSON schema as-is for conventional accelerators would mean leaving most fields empty or repurposing them awkwardly — not a good fit.

However, Jetson, Qualcomm, and Coral (plus the in-flight Axelera Voyager target) all share one concrete lifecycle: **export model → vendor compiler produces an artifact → benchmark artifact vs. a CPU/ONNX baseline**, exactly the shape `workers/neurochip_hw/` already uses for Voyager (`make voyager-compile-spike` / `make voyager-aipu-spike`). With four accelerators now following this shape, it is worth extracting a small shared interface — but only for this "conventional DNN accelerator" lifecycle, not by generalizing the existing SNN target-spec pattern:

- A minimal `ConventionalAccelerator` interface: `export(model) -> intermediate_format`, `compile(intermediate) -> artifact`, `benchmark(artifact, baseline) -> metrics`, plus a small JSON manifest per target (id, vendor, required_format, compile_cmd, requires_hardware: bool).
- Each vendor backend (Voyager, Jetson, Qualcomm, Coral) implements this interface; Neurochip's existing SNN target registry is untouched.
- **Cost:** small — roughly 1 day to define the interface + retrofit the existing Voyager scripts into it.
- **Benefit:** the compile-spike/hardware-spike Make target pattern, CI wiring, and benchmark-recording table (as in the CEL-238 runbook) get written once instead of four times, and new conventional accelerators (there will likely be more) drop in without re-deriving the pattern.

Recommendation: do the small extraction now, scoped only to conventional-DNN accelerators, and leave the SNN JSON-spec pattern alone.

## 3. Recommended phased rollout

Mirrors the Voyager phase split — cheapest, no-hardware path first, hardware spikes gated behind procurement.

| Phase | Platform | Why first/next | Blocked by |
|---|---|---|---|
| 1 | **Coral (compiler-only)** | Cheapest possible validation — `edgetpu_compiler` needs no device at all; proves the TFLite export path and shared-interface shape end-to-end before spending on hardware. Explicitly time-boxed: do not procure Coral hardware. | Nothing — can start immediately |
| 2 | **Qualcomm QNN (CPU-backend compile + sim path)** | No hardware required for conversion/graph validation via `libQnnCpu.so`; establishes the interface's second implementation with a real (if non-representative) benchmark number. | Qualcomm developer account registration (free, but a gate) |
| 3 | **Jetson (TensorRT), compile validation only** | Graph/op-compatibility check via ONNX Runtime + TensorRT EP; needs an NVIDIA GPU host (may already exist for other CV work) but not a Jetson board. | Access to any x86 host with an NVIDIA GPU for the EP check |
| 4a | **Jetson hardware benchmark** | Cheapest real hardware of the three ($250–500), most actively maintained ecosystem — highest ROI hardware spike. | Jetson Orin Nano dev kit procurement |
| 4b | **Qualcomm hardware benchmark** | Real HTP/DSP numbers once a dev board or spare Android phone is available. | Snapdragon dev board or Android phone procurement |
| Deprioritized | **Coral hardware benchmark** | Explicitly not recommended — EOL, unmaintained driver, kernel-version risk. Only pursue if a specific customer requirement demands it. | N/A — policy decision, not procurement |
| Separate track | **Google Tensor (Pixel NPU)** | Different integration shape entirely (Android app + LiteRT/NNAPI delegate, no headless/CI path). Should be scoped as its own follow-up, not bundled with Coral. | Pixel device + Android build tooling — worth a small separate research spike before committing effort |

## 4. Rough effort estimates

| Item | Estimate |
|---|---|
| Shared conventional-accelerator interface (Section 2) | ~1 day |
| Coral compiler-only spike (Phase 1) | ~1–2 days |
| Qualcomm QNN CPU-backend spike (Phase 2) | ~2–3 days (SDK registration/download friction likely) |
| Jetson TensorRT compile-validation spike, no board (Phase 3) | ~1–2 days |
| Jetson hardware benchmark spike (Phase 4a), once board arrives | ~2–3 days |
| Qualcomm hardware benchmark spike (Phase 4b), once board/phone arrives | ~2–3 days |
| Google Tensor scoping spike (separate track) | ~1 day (research only, to decide if it's worth pursuing) |

Total no-hardware research/spike effort (Phases 1–3 + interface): **~1.5–2 weeks**, entirely unblocked by procurement.

## Sources

- [Qualcomm AI Runtime (QAIRT) SDK overview](https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-10/SNPE_general_overview.html)
- [ONNX Runtime: SNPE EP deprecation discussion](https://github.com/microsoft/onnxruntime/discussions/16214)
- [Coral TPU abandoned — Frigate discussion](https://github.com/blakeblackshear/frigate/discussions/18564)
- [Coral Edge TPU FAQ](https://gweb-coral-full.uc.r.appspot.com/docs/edgetpu/faq/)
- [Ultralytics: YOLO on NVIDIA Jetson](https://docs.ultralytics.com/guides/nvidia-jetson)
- [NVIDIA Developer Forums: TensorRT engine JetPack 6.2 vs 7.0](https://forums.developer.nvidia.com/t/tensorrt-engine-produces-distorted-outputs-on-jetson-orin-nx-jetpack-6-2-ampere-but-matches-onnx-on-dgx-spark-jetpack-7-0-grace-blackwell/366014)
