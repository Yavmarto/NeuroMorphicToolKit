# CML Studio Workspace + Hub Integration Plan

## Verified Implementation Status (2026-07-04)

**Overall: PARTIAL — substantially more built than the doc's "not started" framing suggests, but not fully closed out per the plan's own acceptance criteria.**

- **Task 1 (Setup ← Hub workspace import): DONE.** `neurocnl/frontend/lib/screens/studio/steps/setup_step.dart` has a working "Load from Hub" flow: `_openWorkspaceFromHub()` (line 976), `_HubWorkspacePickerDialog` (line 1139) backed by `hubStudioWorkspaceProvider` in `neurocnl/frontend/lib/providers/hub_asset_provider.dart:9`. It distinguishes `hub_workspace` vs `hub_benchmark_workspace` (setup_step.dart:1007-1023), matching the plan's "shared vs benchmark workspace" split.
- **Task 2 (Bench inside Studio workspace lifecycle): PARTIAL.** `neurocnl/frontend/lib/src/features/studio/domain/workspace_file.dart:186-192` carries `selectedBenchmarkId`, `selectedBenchmarkName`, `benchmarkResultSummary` on the workspace artifact, so benchmark data is workspace-owned as planned. However `Neurobench/frontend/lib/app.dart` still defines its own standalone route tree (with `_legacyWorkbenchRedirect`) rather than resolving purely into Studio; `nmtk/neuro_toolkit/lib/workspace/native_surface_registry.dart:32` still registers a distinct `Neurobench` shell adapter, i.e. Bench is compatibility-redirected, not fully absorbed.
- **Task 3 (Share → publish-back-to-Hub): DONE.** `neurocnl/frontend/lib/screens/studio/steps/results_step.dart:416` implements `_shareToHub()` calling `hubClient.publishWorkspace(...)` (line 455), wired to a "Share to Hub" button (lines 94, 317, 327) triggered from Studio results, not a separate Share screen. `Neurohub/frontend/lib/screens/share_model_screen.dart:13,97-224` independently supports `studio_workspace` type with a "Benchmark workspace" toggle that sets `workspace_kind: benchmark`.
- **Task 4 (Compatibility redirects): PARTIAL.** `Neurobench/frontend/lib/app.dart` has `_legacyWorkbenchRedirect` wired on multiple routes, showing legacy-entry-point redirection exists, but this wasn't traced all the way to confirm it lands specifically in Studio setup/publish flows as the plan specifies; `nmtk/neuro_toolkit/lib/routing/router.dart` routes everything through a generic `/workspace` root rather than the Bench/Share-specific redirects described in Task 4.
- **Task 5 (NeuroSim left unresolved): DONE (by omission).** `neurocnl/frontend/lib/screens/canvas_host_screen.dart` and `neurocnl/frontend/lib/routing/app_router.dart` still reference `NeurosimRouteTarget`/`NeuroSimShellAdapter` unchanged, with no merge into the new Setup/publish model found — consistent with "leave unresolved."
- **Test Plan items:** Not verified — no widget/route tests specifically named for "Hub-backed workspace selection" or "publish workspace to Hub" were located in this pass; this needs a follow-up grep of `neurocnl/frontend/test/` and `Neurohub/frontend/test/` before claiming test coverage.
- **What's missing vs. plan:** Full collapse of Bench into a single Studio-owned shell (Task 2/4 currently a compatibility layer, not the described unification); no direct evidence of `Neurohub/frontend/lib/shell/neurohub_deep_link.dart` carrying Hub-selected-workspace payloads into Studio setup as Task 1 describes deep-link-side.

**Note:** Since the doc's own "Status" line says "not started," this doc appears stale relative to the codebase — Tasks 1 and 3 are functionally implemented under different concrete file names/flows than the plan enumerates (e.g. via `setup_step.dart` and `results_step.dart` rather than `studio_screen.dart` directly), which the plan should be updated to reflect.

---

**Goal:** Make CML Studio start from a Hub-backed workspace file, let the user run the full Studio workflow on that workspace, and then share the updated workspace plus benchmark results back to the Hub.

**Architecture:** Treat "shared workspace file" and "benchmark workspace file" as the same core workspace artifact. Studio setup becomes the entry point for selecting or importing that artifact from Hub, Bench becomes a capability inside the same workspace lifecycle, and Share becomes the publish/export path for the completed workspace. `NeuroSim` is explicitly left unresolved and must not be forced into this redesign yet.

**Tech Stack:** Flutter, Riverpod, GoRouter, `neurocnl` workspace state, `Neurohub` share flows, existing Studio workspace import/export plumbing.

---

## Product Direction

### What the user should experience

1. Open CML Studio.
2. In Setup, choose a workspace source from Hub.
3. Pick either:
   - a shared workspace file, or
   - a benchmark workspace file.
4. Studio loads that workspace and uses it as the starting point for architecture, training, deployment, and benchmark work.
5. When finished, the user publishes the updated workspace back to Hub, optionally including benchmark results in the same shared artifact.

### What this plan deliberately does not decide

- `NeuroSim` placement is still open.
- This plan must not hard-code `NeuroSim` into Setup, navigation, or final workflow framing.
- Any `NeuroSim` work should be isolated behind compatibility routes or existing Studio canvas entry points until a separate product decision is made.

---

## Core Model

### Workspace artifact

- Introduce or standardize one Studio-owned workspace artifact shape.
- A benchmark workspace file should be treated as a workspace variant, not as a separate product type from the user’s perspective.
- The artifact must be able to carry:
  - workspace metadata,
  - Studio authoring state,
  - selected datasets/platforms,
  - benchmark configuration,
  - benchmark outputs/results summary,
  - publishable Hub metadata.

### Hub relationship

- Hub becomes the source and sink for these workspace artifacts.
- "Share" is no longer a standalone destination in the primary workflow.
- "Share" becomes:
  - browse/import from Hub during Setup,
  - publish/export to Hub at the end of the workflow.

---

## Implementation Tasks

### Task 1: Rewrite Setup around Hub workspace import

**Files:**
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `nmtk/neuro_toolkit/lib/routing/router.dart`
- Modify: `Neurohub/frontend/lib/shell/neurohub_deep_link.dart`

- [ ] Replace the current setup assumptions with a workspace-source decision.
- [ ] Add a Setup surface in Studio that offers:
  - open shared workspace from Hub,
  - open benchmark workspace from Hub,
  - optional local workspace import only as a secondary path.
- [ ] Reuse the existing Studio workspace open/replace flow instead of inventing a second bootstrap state model.
- [ ] Make launcher or deep-link entry points land on Studio setup in a way that can carry a Hub-selected workspace payload.

### Task 2: Make Bench part of the Studio workspace lifecycle

**Files:**
- Modify: `neurocnl/frontend/lib/src/features/studio/domain/workspace_file.dart`
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `Neurobench/frontend/lib/app.dart`
- Modify: `nmtk/neuro_toolkit/lib/workspace/native_surface_registry.dart`

- [ ] Move benchmark-starting data into the Studio workspace model.
- [ ] Represent benchmark configuration and results as workspace-owned data, not a separate launcher destination concept.
- [ ] Keep legacy Bench entry points working, but have them resolve into Studio with benchmark intent.
- [ ] Avoid forcing a standalone Bench shell as the main user path.

### Task 3: Turn Share into publish-back-to-Hub

**Files:**
- Modify: `Neurohub/frontend/lib/screens/share_model_screen.dart`
- Modify: `neurocnl/frontend/lib/widgets/export_menu.dart`
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`

- [ ] Replace the generic "share a file" framing with "publish this workspace".
- [ ] Allow Studio to package:
  - the current workspace artifact,
  - benchmark result payloads,
  - summary metadata for Hub.
- [ ] Trigger Hub publish from Studio completion/export actions rather than requiring the user to leave the workflow.
- [ ] Keep the Hub API contract stable unless the current share endpoint cannot support the workspace payload.

### Task 4: Preserve compatibility without freezing the wrong IA

**Files:**
- Modify: `nmtk/neuro_toolkit/lib/screens/tool_view.dart`
- Modify: `nmtk/neuro_toolkit/lib/routing/router.dart`
- Modify: `Neurohub/frontend/lib/app.dart`
- Modify: `Neurobench/frontend/lib/app.dart`

- [ ] Keep old entry points functional during development.
- [ ] Redirect legacy Bench/Share opens into Studio setup, Studio workspace, or Studio publish flows as appropriate.
- [ ] Do not spend more design effort on launcher-wide chrome until the workflow merge is correct.
- [ ] Any shell changes should support the workspace flow, not define it.

### Task 5: Leave NeuroSim intentionally unresolved

**Files:**
- Modify only if needed for compatibility:
  - `neurocnl/frontend/lib/routing/app_router.dart`
  - `neurocnl/frontend/lib/screens/canvas_host_screen.dart`

- [ ] Preserve current Studio/canvas access for `NeuroSim`.
- [ ] Do not merge `NeuroSim` into the new Setup or publish model in this pass.
- [ ] Document the unresolved decision in code comments or follow-up docs where needed.

---

## Test Plan

### Studio setup

- Add widget tests that verify Setup offers Hub-backed workspace selection.
- Add tests for loading:
  - a shared workspace artifact,
  - a benchmark workspace artifact,
  into the same Studio workspace state path.

### Workspace model

- Add serialization tests for workspace artifacts that include benchmark configuration and benchmark results.
- Verify existing workspace open/save behavior still works with the expanded artifact shape.

### Compatibility

- Add route/deep-link tests showing legacy Bench and Share entry points land in the correct Studio flow.
- Keep current `NeuroSim` entry points working unchanged unless a compatibility fix is required.

### Publish flow

- Add tests that verify Studio can publish a workspace artifact back to Hub with result metadata.
- Verify failed Hub publish states produce actionable user-facing errors.

---

## Acceptance Criteria

- A user can start CML Studio from a Hub-provided shared workspace artifact.
- A user can start CML Studio from a Hub-provided benchmark workspace artifact.
- Both flows hydrate the same Studio workspace model.
- Benchmark work happens inside the Studio workspace lifecycle.
- The completed workspace can be published back to Hub together with benchmark outputs.
- `NeuroSim` is not incorrectly forced into this merge.

---

## Assumptions

- The correct first priority is workflow correctness, not shell polish.
- "Benchmark workspace file" can be normalized into the same workspace artifact family as a shared workspace file.
- Existing Studio workspace import/export code is the right foundation and should be extended rather than replaced.
