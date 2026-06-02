# ADR-0024: Validation gate for Train and Deploy actions

**Status:** Accepted  
**Date:** 2026-06-01

## Context

The Studio pipeline has three downstream action surfaces — **Train**, and the four **Deploy** workspaces (Akida, PYNQ, Lava, SC-NeuroCore) — that submit the CNL spec to backend services. The existing `runGenerateAndSimulate` path (`studio_screen.dart:144-150`) already requires `validateStatus == success && validateResult.overall == true` before proceeding. The Train auto-start and all Deploy action buttons lacked this guard, allowing them to be triggered while the spec carried validation errors.

## Decision

All actions that submit a spec to a downstream service (training backend, hardware deploy, simulator compile/run) are gated on:

```dart
pipeline.validateStatus == StepStatus.success &&
pipeline.validateResult?.overall == true
```

This is derived from `pipelineProvider` via `ref.watch` inside each workspace's `build()`, ensuring the guard updates reactively as validation state changes.

**Training:** `_autoStart()` in `TrainingInspectorPanel` is only called when the above condition holds. If capabilities load before validation passes, `_hasAutoStarted` is reset to `false` so the auto-start fires once validation succeeds on a subsequent edit.

**Deploy (Akida, PYNQ, Lava):** The `isValidated` flag is ANDed into all action button `onPressed` guards. The SC-NeuroCore FPGA workspace is exempt — it is an offline NIR artifact viewer with no live backend submission path.

## Rationale

- Prevents submitting malformed specs to training or hardware backends.
- Consistent with the existing guard on `runGenerateAndSimulate`.
- A single reactive bool (`isValidated`) keeps the condition DRY within each workspace.

## Consequences

- Training will not auto-start on page load if the cached spec is invalid or if validation has not yet run.
- Deploy action buttons (Generate Package, Install, Map Runtime, Run Inference, Check Readiness, Compile, Run) are visually disabled until validation passes.
- Once the user corrects the spec and validation succeeds, the buttons re-enable automatically without any additional interaction.
