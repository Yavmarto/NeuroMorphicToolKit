# CEL-247: Google Tensor (Pixel) Scoping Spike

**Date:** 2026-09-15
**Parent:** CEL-240 — Wider Edge Computing/ARM
**Related:** CEL-242 (ARM Edge Accelerator Research — this spike is the "separate track" flagged there)

Research only. No code, scripts, or dependencies added. Question to answer: is a Google Tensor
(Pixel NPU) path worth pursuing later?

## 1. What the path actually looks like

- **Access mechanism:** Google Tensor NPU access is not via classic NNAPI. NNAPI was deprecated in
  Android 15 (still runs for back-compat on existing apps, but Google steers new work away from it).
  The current path is the **Tensor ML SDK** (beta as of 2026), which plugs into **LiteRT** (the
  successor to TensorFlow Lite) via a dedicated Tensor delegate.
- **Model path:** export to LiteRT format → run through the CompiledModel API with **ahead-of-time
  (AOT) compilation** targeting the Tensor chip. On-device/JIT compilation is not yet supported by
  the SDK — models must be precompiled per Tensor generation (G2/G3/G4) before shipping.
- **Model Garden:** Google ships 100+ precompiled reference models for Pixel 10's Tensor chip, but a
  custom NMTK model would need to go through the same AOT compile step, not just reuse a garden model.
- **Packaging:** this is Android-app-only. There is no CLI/binary/server-side entry point — the only
  way to exercise the delegate is inside an Android app process on a real Tensor-equipped Pixel.
  Same conclusion as CEL-242 section 1: no headless or CI-friendly compile-only step exists here,
  unlike Coral's `edgetpu_compiler` or Qualcomm QNN's CPU-backend simulator.

## 2. Why this doesn't fit the Voyager/Jetson/Qualcomm/Coral shape

CEL-242's phased rollout works because every other platform has a **compiler-only, no-hardware
validation step** (ONNX Runtime + TensorRT EP for Jetson, `libQnnCpu.so` for Qualcomm,
`edgetpu_compiler` for Coral) that proves export/graph compatibility before any procurement decision.
Google Tensor has no equivalent:

- The Tensor ML SDK's AOT compiler is not documented as runnable standalone outside an Android
  build/app context as of this research (2026-09-15) — compilation appears tied to the app packaging
  flow, not a bare CLI like `trtexec` or `edgetpu_compiler`.
- Even if graph compatibility could be checked, there is no way to get a real benchmark number without
  a physical Pixel device with a Tensor chip (G2 or newer) and an Android build environment (Android
  Studio / Gradle / NDK), which is a materially different toolchain from the Python/Linux stack the
  rest of Neurochip's target backends use.
- The `ConventionalAccelerator` interface proposed in CEL-242 section 2 (`export → compile →
  benchmark`, `requires_hardware: bool`) technically fits, but Google Tensor would be the *only*
  target where `requires_hardware` gates the entire pipeline including compilation, not just the
  final benchmark — it can't share Phase 1–3's no-hardware validation pattern at all.

## 3. Cost/access

- **Hardware:** a Pixel phone with a Tensor chip (Pixel 6 or later for Tensor G1–G4; Tensor G4/G5 on
  Pixel 9/10 for the newer SDK beta). Street price for a usable dev unit: roughly $400–$700 new, less
  used/refurbished.
- **Software:** Android Studio + Android NDK + signup for the experimental Tensor ML SDK access
  (self-serve signup as of 2026, not a paid program, but it is a beta gate that could change scope
  or availability).
- **Skill gap:** requires Android app development competency (Kotlin/Java + Gradle + NDK), which is
  a different skillset than the Python/Linux accelerator work in CEL-242. NMTK's launcher is already
  a Flutter app with Android as a target platform, so this isn't a cold start, but the LiteRT/Tensor
  delegate integration itself is native Android, not something reachable through Flutter's existing
  plugin surface without a platform channel.

## 4. Recommendation

**Not worth pursuing now.** Reasons:

1. No headless/CI-compatible validation path exists — every other accelerator in CEL-242 can be
   partially de-risked for ~$0 before buying hardware; Tensor cannot.
2. The SDK is in beta with AOT-only compilation (no on-device compile yet), so the integration
   surface is still moving — building against it now risks rework before it stabilizes.
3. It requires a distinct skillset (native Android/Kotlin + Gradle) and toolchain from the rest of
   the conventional-accelerator work, so it wouldn't benefit from the shared interface being built
   for Voyager/Jetson/Qualcomm/Coral — it would be a standalone effort, not a drop-in fifth backend.
4. Market fit is narrower than the other targets: it only ever runs inside an NMTK mobile app on a
   Pixel-family phone, not on any embedded/server deployment NMTK currently targets.

**Revisit trigger:** re-scope once the Tensor ML SDK exits beta and either (a) ships a standalone
AOT compiler usable outside an app build, or (b) NMTK has a concrete Android-app use case that
specifically needs on-device NPU inference (not just CPU/GPU), rather than pursuing it speculatively
alongside the embedded-Linux accelerator track.

## Sources

- [Google Tensor SDK Beta with LiteRT — Google Developers Blog](https://developers.googleblog.com/google-tensor-sdk-beta-with-litert/)
- [Google Tensor with LiteRT — Google AI Edge docs](https://ai.google.dev/edge/litert/next/tensor-sdk)
- [NPU acceleration with LiteRT — Google AI Edge docs](https://ai.google.dev/edge/litert/next/npu)
- [LiteRT delegate for NPUs — overview](https://developers.google.com/edge/litert/android/npu/overview)
- [NNAPI Migration Guide — Android NDK docs](https://developer.android.com/ndk/guides/neuralnetworks/migration-guide)
- [LiteRT delegate for Pixel Phones (Tensor G2/G3/G4) — tracking issue](https://github.com/google-ai-edge/LiteRT/issues/969)
