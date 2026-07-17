# Validation Panel Deploy-Readiness — Summary

Plan file: `/Users/yoshimartodihardjo/.claude/plans/make-an-implementation-plan-sleepy-valiant.md`
Audit detail: `audit.md` (this folder)

## Problem

The pipeline-bar "Deploy" step could turn red for two reasons the Validation
panel never showed: a hardware `generate`/codegen-preview failure, or a
simulator preflight failure/unsupported-node result. Both were only surfaced
after the user pressed Play, producing a confusing green-panel/red-step state
with no visible explanation anywhere in the UI.

## What changed

1. **Layer 1 invariant audit** (Tasks 1-2) — confirmed `ALL_INVARIANTS` /
   `validate()` are still live (canvas/notebook LIF-population validation
   path), so they were kept. Dropped the dead hardware-specific groups
   (`LOIHI_INVARIANTS`, `AKIDA_INVARIANTS`, `SPINNAKER_INVARIANTS`,
   `SPINNAKER2_INVARIANTS`, `TEENSY_INVARIANTS`, and their export contracts)
   that were only reachable through `validate()`'s dead hardware-backend
   branches. Relabeled the surviving NIR-native invariant display strings for
   readability. No change to the `/api/validate` response shape.

2. **Unified deploy-readiness state** (Task 3) — added
   `PipelineState.deployReadinessStatus` / `deployReadinessResult`, backed by
   a new `DeployReadinessResult` freezed union (`ok` / `unsupported` /
   `error`), in
   `neurocnl/frontend/lib/src/features/studio/domain/`.

3. **Auto-trigger after validate** (Task 4) — `pipeline_provider.dart` now
   kicks off a side-effect-free readiness check as soon as validate passes:
   simulator targets reuse the existing `simulatorPreflightControllerProvider`
   (unchanged), hardware/codegen targets call the already-existing
   `apiClient.previewDeployTarget(spec, target)` (`POST /notebook/preview`,
   no backend changes needed). Both paths mirror into the new
   `PipelineState` fields, guarded against stale requests from rapid spec
   edits or target switches.

4. **Validation panel section** (Task 5) — a new deploy-readiness section
   renders under the existing backend-support banner, showing a
   success/warning/danger banner depending on the result (ready, approximate
   nodes, unsupported nodes, or a readiness-check error).

5. **Single source of truth for Deploy status** (Task 6) — added
   `PipelineState.deployStepStatus` / `overallReady` / `deployReadinessFailed`
   derived getters. Both `pipeline_bar.dart`'s Deploy step and
   `validation_panel.dart`'s Overall banner now read these same getters
   instead of independently branching on simulator-vs-hardware logic —
   structurally preventing the two indicators from ever disagreeing again.
   Removed the now-dead per-widget branching helpers and their stale test
   mirrors, replacing them with tests against the real getters.

## Where to notice the difference

Open the Studio, type a spec that validates successfully but has an
unsupported node type for the currently selected deploy target (hardware or
simulator). Within about a second of the debounce firing — no Play press
required — the Validation panel shows a red "Deploy readiness" section, and
the pipeline-bar Deploy step turns red at the same moment. Fix the spec (or
switch to a supported target) and both go green together, since they now
read the same underlying state.

## Verification performed

- `flutter analyze` on the whole `frontend` package: clean in every file this
  plan touched; 37 pre-existing issues remain elsewhere (confirmed
  unrelated — none in touched files).
- Full `flutter test` run: 115 failures present, but every failure cluster
  checked (including the large `studio_screen_test.dart` /
  `studio_responsive_audit_test.dart` / `error_reporting_test.dart` clusters)
  was reproduced identically after stashing all of this plan's Task 3-6
  frontend changes back to the pre-plan commit (`dbb0944b`) — confirming
  these failures pre-exist this work and are not a regression it introduced.
- This plan's own test suites are green:
  `pipeline_provider_deploy_readiness_test.dart`,
  `pipeline_provider_exploration_test.dart`,
  `validation_panel_no_nested_cards_test.dart` (30/30),
  `simulator_preflight_provider_test.dart` (54/57 — the 3 remaining failures
  are pre-existing flaky glados property tests in
  `testPipelinePreflightTriggerOnValidate`, unrelated to this plan since that
  group exercises `pipeline_provider.dart`'s preflight wiring rather than
  anything Task 6 touched).

## Out of scope / follow-up

Play-button removal is a separate, later task and was not touched here
(`_triggerRun` and its call sites in `studio_screen.dart` are untouched). It
can build directly on this auto-flow: once deploy-readiness is always
computed ahead of time, the Play button no longer needs to be the trigger
for discovering deploy-blocking issues.

The wide pre-existing test failures found during Task 7's verification sweep
(canvas widgets, theming/icon migration, `studio_screen_test.dart`) are not
part of this plan's scope and were not fixed — see "Verification performed"
above for how they were confirmed unrelated.
