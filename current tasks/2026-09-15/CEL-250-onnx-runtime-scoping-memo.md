# CEL-250: ONNX Runtime Scoping Memo for Shared Accelerator Interface

**Date:** 2026-09-15
**Parent:** CEL-240 — Wider Edge Computing/ARM
**Related:** CEL-249 (this memo's origin comment), CEL-243 (shared `ConventionalAccelerator` interface, delivered), CEL-244/245/246/247 (Coral/QNN/Jetson/Tensor spikes)

Scoping only — no code changes. Question: does ONNX Runtime (ORT) belong under CEL-243's
`ConventionalAccelerator` interface, and if so, when?

## 1. Build CEL-243 on ORT's execution-provider model, or keep it independent?

**Keep it independent for now.** CEL-243's `ConventionalAccelerator` ABC
(`Neurochip/neurochip/conventional_accelerators/interface.py`) already models
`export → compile → benchmark` as three separate stages with vendor-specific compile commands
(`edgetpu_compiler`, `qnn-onnx-converter` + `qnn-model-lib-generator`, `trtexec`, Voyager's
`axcompile`). ORT's execution-provider (EP) model is a *runtime dispatch* abstraction — one
process picks a provider (`QNNExecutionProvider`, `TensorrtExecutionProvider`, `CoreMLExecutionProvider`,
`NnapiExecutionProvider`, `ArmNNExecutionProvider`) and ORT routes ops to it, falling back to CPU
for unsupported ops. These are different problems: CEL-243 already produces vendor-native artifacts
(`.axm`, `libyolov8n.so`, `*_edgetpu.tflite`, `.engine`) ahead of time for deployment; ORT's EP model
is for a single process that wants to *pick a backend at inference time* without pre-compiling per
target. Folding EP selection into the `compile()` stage would conflate "produce a deployable artifact"
with "configure a runtime session," and none of the four spikes so far needed that — Jetson's own
spike (CEL-246) already validates ORT + `TensorrtExecutionProvider` as one of its *four* pass criteria,
alongside `trtexec` directly, without touching the shared interface at all.

Where ORT EPs are a genuine option is inference-time, in the eventual `benchmark()` implementations:
ORT + QNN EP could replace the raw `qnn-net-run` path (CEL-245), and ORT + TensorRT EP already runs
inside CEL-246. That's additive, not architectural — it would only change what `benchmark()` shells
out to, not the interface shape.

## 2. What NMTK model formats would need to convert to/from ONNX

NMTK's conventional-accelerator export path is already ONNX-centric in practice — every spike so far
(Voyager, QNN, Jetson) starts from Ultralytics `YOLO(...).export(format="onnx")`. The gaps are:

| Current NMTK format | ONNX path today | Gap for ORT adoption |
|---|---|---|
| PyTorch (`.pt`) → ONNX | Working (`ultralytics` export, opset 12–17) | None — already the default export target |
| TFLite (INT8, Coral path, CEL-244) | No converter used today; Coral goes PyTorch → TFLite directly, bypassing ONNX | Would need `onnx2tf` reversed (ONNX → TFLite) or a maintained ORT↔TFLite bridge; ORT itself does not consume TFLite, so this path stays outside ORT regardless |
| QNN `.bin`/context binary (CEL-245) | ONNX is already the QNN converter's input format | None — QNN path is ONNX-native already |
| TensorRT `.engine` (CEL-246) | ONNX is already `trtexec`'s input format | None |
| Neurochip's native SNN target-spec formats (`neurochip/targets/*.json`, PYNQ etc.) | Not applicable | Out of scope — CEL-242 already drew this line; SNN targets don't go through ONNX or the conventional-accelerator interface at all |

**Net finding:** NMTK doesn't have a model-format problem to solve for ORT adoption. Three of the
four conventional-accelerator spikes already standardized on ONNX as the export target before this
memo existed. The only format that stays outside ONNX's reach is Coral/TFLite, because ORT has no
TFLite EP or converter — that path is unaffected by an ORT decision either way.

## 3. Rough integration effort and licensing

**Licensing:** ONNX Runtime is Apache 2.0 (not MIT as the issue assumed — same permissive family,
no copyleft, no attribution burden beyond the standard NOTICE file). No conflict with NMTK's existing
dependency set or distribution model. Confirmed via the [onnxruntime repository LICENSE](https://github.com/microsoft/onnxruntime/blob/main/LICENSE).

**Effort, if adopted:**

| Item | Estimate | Notes |
|---|---|---|
| `pip install onnxruntime-qnn` / `onnxruntime-gpu` (TensorRT EP) as optional extras | ~0.5 day | Both already installed transitively for CEL-245/246 spikes; formalizing as a pinned extra is small |
| Wire ORT EP as an alternate `benchmark()` backend for QNN | ~1 day | Replaces/augments `qnn-net-run`; useful because CEL-245's raw QNN CPU run already failed on YOLOv8n graph execution (exit 17) — ORT's fallback-to-CPU-op behavior might succeed where the raw backend didn't |
| Wire ORT + TensorRT EP as Jetson's primary graph-validation check | 0 days | Already done — CEL-246 step 4 does this today, outside any shared-interface change |
| Coral / NNAPI / CoreML EPs | Not applicable now | Coral has no ORT EP (TFLite-only, EOL per CEL-242); NNAPI EP targets Android — same "Android-app-only, no headless path" limitation CEL-247 already ruled out for Google Tensor |
| ARM NN EP (generic ARM Cortex-A/Mali path) | ~2–3 days research spike | Not yet scoped by any existing spike; would need its own CEL-24x-style compiler-only validation before any interface change — this is the one genuinely new surface ORT opens up |

Total incremental effort to *use* ORT where it already fits (QNN, Jetson) is under 2 days and doesn't
require touching the `ConventionalAccelerator` interface. The only net-new scope ORT would add is an
ARM NN EP spike, which is a new vendor target, not an architecture change.

## 4. Recommendation

**Revisit after the four vendor spikes land — do not adopt or restructure CEL-243 now.**

1. Three of four spikes (QNN, Jetson, Voyager) are already on the ONNX export path; ORT integration
   at the `benchmark()` level is a small, backend-swap-only change that can happen inside any single
   backend's existing file without touching the shared interface.
2. ORT's EP abstraction solves a different problem (runtime backend dispatch) than CEL-243 solves
   (ahead-of-time compile artifact production per vendor). Building the interface *on top of* ORT
   would force every future vendor target through ORT's EP model even where a vendor's native compiler
   (Voyager's `axcompile`, `edgetpu_compiler`) is the only path that produces a real deployable artifact.
3. The one genuinely new opportunity — ARM NN EP as a generic Cortex-A/Mali path — isn't validated by
   any current spike and deserves its own CEL-24x-style compiler-only scoping spike before it's worth
   a decision either way.
4. No blocker exists to revisiting later: adopting ORT for QNN/Jetson benchmarking today or in three
   months costs the same ~1 day either way, since it doesn't touch the interface shape.

**Revisit trigger:** once Coral/QNN/Jetson/Tensor spikes are all closed out (CEL-244–247, on track),
open a short follow-up to (a) swap QNN's `benchmark()` to try ORT + QNN EP as a fallback for graphs
that fail raw `qnn-net-run`, and (b) scope an ARM NN EP compiler-only spike as a fifth conventional
target — both additive, neither requires reworking `interface.py`.

## Sources

- [ONNX Runtime execution providers overview](https://onnxruntime.ai/docs/execution-providers/)
- [ONNX Runtime QNN Execution Provider](https://onnxruntime.ai/docs/execution-providers/QNN-ExecutionProvider.html)
- [ONNX Runtime TensorRT Execution Provider](https://onnxruntime.ai/docs/execution-providers/TensorRT-ExecutionProvider.html)
- [ONNX Runtime ArmNN Execution Provider](https://onnxruntime.ai/docs/execution-providers/ArmNN-ExecutionProvider.html)
- [ONNX Runtime NNAPI Execution Provider](https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html)
- [onnxruntime LICENSE (Apache 2.0)](https://github.com/microsoft/onnxruntime/blob/main/LICENSE)
- CEL-242/244/245/246/247 (this repo, `current tasks/2026-09-15/`)
