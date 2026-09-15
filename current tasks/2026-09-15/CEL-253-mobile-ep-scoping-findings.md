# CEL-253: Mobile-first ONNX Runtime EP Scoping — NNAPI (Android) + CoreML (iOS)

**Date:** 2026-09-15
**Parent:** CEL-240 — Wider Edge Computing/ARM
**Related:** CEL-247 (Google Tensor, deprioritized — this is the mature alternative), CEL-250 (ORT
scoping memo, flagged NNAPI/CoreML as "not applicable now" with a one-line dismissal this spike
re-checks), CEL-252 (ArmNN EP, generic embedded-Linux ARM — do not conflate)

Research only. No code, scripts, or dependencies added. Question to answer: can ORT's NNAPI and
CoreML execution providers (EPs) be exercised from NMTK's existing Flutter launcher
(`nmtk/neuro_toolkit/`) without a native Android/iOS app rewrite, and is there a no-hardware
validation path?

## 1. Can this be reached from Flutter without a rewrite?

CEL-250 dismissed NNAPI/CoreML in one line as "same Android-app-only, no headless path limitation
CEL-247 already ruled out for Google Tensor." That comparison doesn't hold up: Google Tensor has no
CLI/SDK path at all outside an Android app build, but NNAPI and CoreML are just ORT execution
providers reached through ORT's normal session API — no app-specific SDK, no beta signup, no
AOT-compile-then-ship step. The relevant question isn't "does it need an app," it's "does it need a
**native** app," and the answer is no.

**[`flutter_onnxruntime`](https://pub.dev/packages/flutter_onnxruntime)** (MIT, published by
`masic.ai`, verified publisher, latest version 1.8.5 as of this research) is a maintained Flutter
plugin that wraps native ORT builds per platform (Android/iOS/macOS/Linux/Windows, Web in progress)
behind a single Dart API. Its `OrtProvider` enum
([API docs](https://pub.dev/documentation/flutter_onnxruntime/latest/flutter_onnxruntime/OrtProvider.html))
lists both targets directly:

```
ACL, ARM_NN, AZURE, CORE_ML, CPU, CUDA, DIRECT_ML, DNNL, NNAPI, OPEN_VINO, QNN, ROCM,
TENSOR_RT, XNNPACK, WEB_ASSEMBLY, WEB_GL, WEB_GPU, WEB_NN
```

Session creation takes a `providers: [OrtProvider.NNAPI]` or `providers: [OrtProvider.CORE_ML]` list
on `OrtSessionOptions`, same shape as the C++/Java/Objective-C APIs ORT documents natively. This is a
Dart-level call from the existing launcher, not a platform channel NMTK would need to author — the
plugin already owns that boundary. A rival plugin, `onnxruntime_v2`, exists as a fork with the same
shape; `flutter_onnxruntime` is the more actively maintained option (6 days old at time of writing,
per pub.dev) and is the one to prototype against if this is picked up later.

**Net finding:** no native Android/iOS app rewrite is needed. The integration surface is "add a
pub.dev dependency and pick an enum value," not "build a Kotlin/Swift bridge," which is a materially
different (and much smaller) lift than the Google Tensor path in CEL-247.

## 2. No-hardware / emulator-only validation

**Android (NNAPI): a real no-hardware path exists.** ORT's NNAPI EP has a documented
`NNAPI_FLAG_CPU_ONLY` option
([ORT docs](https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html)): it forces
NNAPI to run through its CPU reference implementation instead of dispatching to GPU/DSP/NPU, "useful
for validation." This is gated to Android API 29+ and works on the standard x86_64 emulator image
Android Studio ships — no physical device or accelerator needed. This validates graph
compatibility (does NNAPI accept every op in the exported graph, does inference produce correct
output) but says nothing about real NPU/DSP throughput or latency, since CPU-only mode never touches
the accelerator path. That's the same shape as CEL-245's QNN CPU-backend simulator: a genuine
graph-compatibility check with a large, clearly-labeled asterisk on performance numbers.

**iOS (CoreML): no equivalent gap-free path — confirmed, as the issue anticipated.** ORT's CoreML EP
docs specify `MLComputeUnits` options (`CPUAndNeuralEngine`, `CPUAndGPU`, `CPUOnly`) but the
Simulator was not found to be a supported target in ORT's own CoreML EP documentation — only "iOS
devices" and "Mac computers" are listed. Practically: a `CPUOnly` compute-unit run inside the
Simulator (or on macOS directly, since NMTK's launcher already targets macOS) would validate that a
graph loads and executes through the CoreML EP's op-conversion path, but it proves nothing about
Neural Engine dispatch or performance — the docs don't distinguish "runs in Simulator with CPU
fallback" from "CoreML EP is unavailable in Simulator entirely," so this would need to be verified
empirically (build a minimal test target) before relying on it. Flag this as the one open question a
follow-up spike would need to close before writing test infrastructure around it.

## 3. Cost/access

- **Hardware:** none required for the compatibility-only validation step above. A physical
  Neural-Engine-equipped iPhone/iPad and an NNAPI-accelerator-equipped Android device (most phones
  from ~2019 onward) are needed for real performance numbers, but NMTK's own dev hardware likely
  already covers Android; iOS needs a real device in the loop for anything beyond CPU op-compat.
- **Software:** `flutter_onnxruntime` (or `onnxruntime_v2`) as a `pubspec.yaml` dependency — no SDK
  signup, no beta gate, no separate native toolchain beyond what building the Flutter app for
  Android/iOS already requires.
- **Skill gap:** none beyond what NMTK's launcher team already has. This is Dart application code
  calling a published plugin, not native Android/iOS development — the opposite situation from CEL-247's
  Google Tensor path, which required a distinct Kotlin/Gradle/NDK skillset the launcher work doesn't
  otherwise touch.
- **Model format:** both EPs consume ONNX directly, consistent with CEL-250's finding that NMTK's
  conventional-accelerator export path (Voyager/QNN/Jetson) already standardizes on ONNX.

## 4. Recommendation

**Go — worth a small follow-up prototype, not a full build-out yet.** Reasons:

1. Unlike Google Tensor (CEL-247), there is no beta SDK, no app-store-only packaging constraint, and
   no AOT-only compile step blocking a path to validation — this is ORT's standard, stable EP
   mechanism, reachable from Flutter via an existing, actively maintained plugin.
2. A genuine no-hardware graph-compatibility check exists for Android (`NNAPI_FLAG_CPU_ONLY` on the
   emulator), matching the bar CEL-242's phased rollout set for the other accelerator targets.
3. iOS has a real, disclosed gap: the Simulator's ability to exercise the CoreML EP at all (even in
   CPU-only mode) is unconfirmed from documentation alone and needs a small empirical check, not a
   scoping-level guess — do not write test infrastructure that assumes Simulator coverage until that's
   verified.
4. CEL-250's one-line dismissal of NNAPI/CoreML was based on an incorrect analogy to Google Tensor's
   packaging constraints; this spike corrects that record.

**Suggested next step (small, not full build-out):** a short spike that adds `flutter_onnxruntime` to
a throwaway branch, exports one existing NMTK ONNX model, and runs it through
`OrtProvider.NNAPI` with `CPU_ONLY` on the Android emulator plus `OrtProvider.CORE_ML` on the iOS
Simulator and/or macOS build, to (a) confirm the plugin's provider-selection API works as documented
end-to-end and (b) resolve the open CoreML-Simulator question in section 2. That's a half-day
prototype, not the multi-day conventional-accelerator interface work CEL-243 already delivered for
the embedded-Linux targets — no code or dependency change is being made as part of this scoping issue
itself, per the issue's own scope bar.

**Revisit trigger:** if/when NMTK has a concrete on-device inference need for the launcher's Android
or iOS builds (as opposed to the current server-side Python inference model), open a build issue to
add `flutter_onnxruntime`, run the half-day prototype above, and decide whether this becomes a real
launcher dependency.

## Sources

- [ONNX Runtime NNAPI Execution Provider](https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html)
- [ONNX Runtime CoreML Execution Provider](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)
- [flutter_onnxruntime — pub.dev](https://pub.dev/packages/flutter_onnxruntime)
- [flutter_onnxruntime — OrtProvider API docs](https://pub.dev/documentation/flutter_onnxruntime/latest/flutter_onnxruntime/OrtProvider.html)
- [flutter_onnxruntime — API usage guide](https://github.com/masicai/flutter_onnxruntime/blob/main/doc/api_usage.md)
- [onnxruntime_v2 — pub.dev](https://pub.dev/packages/onnxruntime_v2)
- CEL-247, CEL-250 (this repo, `current tasks/2026-09-15/`)
