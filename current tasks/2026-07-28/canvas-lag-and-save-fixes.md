# Canvas lag, save-on-pan, and node values flashing back to default

Date: 2026-07-28
Scope: `neurocnl/frontend`

## Symptoms reported

1. Canvas laggy/slow — was fine the day before.
2. Appears to save even when only panning/zooming.
3. Node parameter values flash back to defaults.

## Root causes found

### 1. Pan/zoom was stored inside the document
`CanvasController.updateViewport` wrote zoom/pan into `graph.metadata`, so every
pan frame minted a new `CanvasGraph` and a new `CanvasState`. Neither class
defines `operator ==`, so equality is identity and nothing downstream could
dedupe:

- `network_canvas.dart` `select((s) => (s.graph, …))` → full canvas build +
  `ConnectionPainter` + every node widget rebuilt per frame.
- `property_panel.dart` watching raw `s.graph` → inspector rebuilt per frame.
- `studio_screen.dart` `listenManual<CanvasState>` (no `select`) → the workspace
  autosave fired 300 ms after every pan.

### 2. The autosave became much more expensive the day before (why it was slow *that* day)
`neurocnl` commit `bd7a1e44` (2026-07-27, "Several fixes to connection") swapped
the workspace cache from `SharedPreferences` to a real file
(`workspace_cache_storage_io.dart`). `FileWorkspaceCacheStorage.write` does
`writeAsString(flush: true)` (fsync) plus a backup/rename/delete dance — ~8
syscalls including a flush — where it used to be an in-memory map write.

So a *pan* triggered: jsonEncode the whole workspace+canvas payload → fsync'd
cache file → `mergeJsonFile()` on the `.nmtk` file (second fsync) →
`scheduleServerSync()` (HTTP) → `autosaveStatusProvider` toggle → top bar rebuild.

### 3. Two paths overwrote local node values
- `canonical_doc_provider.dart` sets a bare `const AsyncLoading()` on every
  mutation. It carries no previous value, so `next.value` is `null` and the
  canvas mirror took its `projection == null` branch and published an *empty*
  graph. Guarded for canvas-originated pushes but not for CNL-panel edits — so a
  CNL keystroke blanked the canvas and repopulated a moment later.
- `_pushingToCanonical` was a bool, cleared in the `whenComplete` of a single
  future. With overlapping pushes, push #1 resolving cleared the flag while
  push #2 was still in flight, so #2's response mirrored back over the newer
  local graph and snapped freshly-edited parameters to backend-normalised values.

### 4. Leftover TEMP debug prints
`[embed-debug]` / `[stepper-debug]` `debugPrint`s from the previous day's
embed/stepper investigation, several in build/layout paths (`studio_top_bar`
build, `app_router` build, `studio_screen`'s `LayoutBuilder`,
`pipeline_stage_area` build). `debugPrint` writes to stdout — visible jank at
per-frame rates, and the top bar rebuilt on every autosave toggle, i.e. every pan.

## Changes made

| File | Change |
|---|---|
| `lib/providers/canvas/canvas_provider.dart` | New `CanvasState.viewport` field (+`copyWith`); `updateViewport` no longer touches `graph`; `_normalizeGraph` drops viewport normalisation; `_pushingToCanonical` bool → `_pendingPushes` counter; `next.isLoading` guard on the mirror; `_hydrateViewportFrom` at load boundaries; `graphForPersistence` getter |
| `lib/models/canvas/canvas.dart` | `operator ==`/`hashCode` on `CanvasViewport`; removed dead `CanvasGraph.viewport` getter and `copyWithViewport`; kept `fromMetadata`/`applyToMetadata` as the project serialization boundary |
| `lib/widgets/canvas/network_canvas.dart` | `_syncViewportFromGraph` → `_syncViewportFromState`, moved out of `build` into a `ref.listen` on the viewport selector |
| `lib/screens/studio_screen.dart` | Autosave listener now `select((s) => s.graph)`; removed `[embed-debug]` and `[stepper-debug]` prints |
| `lib/screens/canvas/canvas_screen.dart` | Reads `canvasState.viewport` instead of `graph.viewport` |
| `lib/screens/canvas/project_screen.dart` | Project save uses `graphForPersistence` so the camera is still stored |
| `lib/screens/studio/studio_top_bar.dart`, `lib/routing/app_router.dart`, `lib/screens/studio/pipeline_stage_area.dart`, `lib/providers/workspace_provider.dart` | Removed TEMP debug prints |
| `test/providers/canvas/canvas_viewport_isolation_test.dart` | **New** — 7 tests |

### Gotcha worth remembering
The initial assumption that "the viewport is never persisted" was only true of the
*workspace autosave* (`_buildCanvasSection` writes pipeline/sim/training/nodeLayout
and nothing else). A saved **project** *does* round-trip zoom/pan through
`graph.metadata`, which `project_screen_test.dart` caught. Hence
`_hydrateViewportFrom` on load (`setGraph` / `loadProjectGraph`) and
`graphForPersistence` on save. `_publishGraph` deliberately does *not* hydrate —
an ordinary edit's metadata has no zoom/pan, so hydrating there would reset the
camera to defaults on every keystroke.

## Verification

- `flutter analyze`: 3 errors remain, all pre-existing in
  `akida_deploy_panel.dart` / `learning_config_panel.dart` (arrived with
  `74957390 generator update`, files untouched here).
- Full suite compared against a stashed baseline: **68 failures before, 67 after,
  zero newly-failing tests.** The single difference is the new test file, which
  cannot compile at baseline. The 4 `network_canvas_stylus_test.dart` failures
  are pre-existing and unrelated.
- `test/providers/canvas/canvas_viewport_isolation_test.dart` — 7/7 pass:
  graph identity stable across pans; no zoom/pan keys in graph metadata; real
  edits still change graph identity; project load hydrates the camera;
  `graphForPersistence` round-trips it; no-op pans emit nothing; and the exact
  autosave selector fires on edits but not on pans.

## Still to check manually (needs the running app)

Not done here — requires `flutter run -d macos` against the dev backend:

1. Pan/zoom ~15 s and confirm
   `~/Library/Application Support/*/neurocnl/workspace-cache-v1.json` mtime does
   not change; moving a node updates it once.
2. With ~15+ nodes, pan continuously and confirm node widgets no longer rebuild
   per frame (DevTools "Track Widget Rebuilds").
3. Edit a node parameter, then a second one within ~200 ms (the overlapping-push
   window) — both must stick. Type in the CNL panel and confirm nodes do not
   blank out mid-keystroke.
4. Edit a node, wait >2 s, hot-restart, confirm the edit survived.

---

# Round 2 — canvas→CNL sync, step-change lag, canvas persistence parity

## Symptoms reported after round 1

1. Editing the canvas no longer updated the CNL, and CNL "did not get generated".
2. Step changes still lagged — ~40% CPU on an M1 Air, ~670MB resident.
3. "Do all 3 canvases save their state the same way? because they should."

## Root causes

### (1) One line dropped the document before every request

`canonical_doc_provider.dart` opened all three `updateFrom*` methods with a bare
`state = const AsyncLoading();`. A bare `AsyncLoading` carries no value, and
`AsyncError.copyWithPrevious` forwards that null through — so **one** failed
`canvas-to-canonical` call left `canonicalDocProvider.value == null` permanently:

- `spec_provider.dart` reads `doc.value?.cnlText ?? ''` → CNL editor blank forever;
- `notebook_generate_service` saw an empty spec → "No architecture to generate from".

Both halves of the report from that one line. The server returns a blanket 422 for any
importer exception (`neurosim/app/routers/generation.py`), so a single CNL-unrenderable
node poisoned every later edit — and the only handler was a `debugPrint`, so it was
entirely silent. `validation_overlay`/`validation_panel` derive solely from
`pipelineProvider`, and `AutosaveStatus` has no error variant.

### (2) Round-1 regression: Train/Eval edits stopped being autosaved

Round 1 narrowed the autosave listener to `select((s) => s.graph)`. A pipeline edit only
mutates `pipelinePhases`, so Train/Eval stopped being persisted entirely — the exact
"eval grid comes back empty after a hot restart" failure the surrounding comment warns
about. **Self-inflicted; fixed here.**

### (3) The three canvases genuinely do not persist alike

| | Model | Train | Eval |
|---|---|---|---|
| pushes to canonical/CNL | yes (11 mutators) | never | never |
| reaches a backend on edit | yes | no | no |
| undo/redo | yes | no (Undo button hits the architecture stack) | same |

`pipelineCnlProvider` exists but reads `s.pipeline` (settings config), not
`s.pipelinePhases`, uses a different client/prefix (`/api/notebook` vs `/api/neurosim`),
and its panel sits behind `CanvasTab.pipelineOverview` — unreachable, because
`_switchTab` is never called and `_CanvasTabBar` is never instantiated.

### (4) Step-change cost

- `animateToPage` at `viewportFraction: 1.0` dragged all 7 pages through the viewport per
  top-bar tap, building every step; `_KeepAliveWrapper` then pinned each alive. Five live
  `CanvasScreen`s (three with a 10000x10000 `InteractiveViewer`) plus a JupyterLab WebView.
- `unlockedStepsProvider` watched the whole `WorkspaceState` (a deep `==` walk including
  the base64 NIR blob) and returned a bare `Set` (no `==`), so every workspace mutation
  rebuilt `StudioScreen` and the top bar.
- `_persist()` ran a full `state.toJson()` + jsonDecode/Encode merge + fsync'd atomic swap
  + pretty-printed `.nmtk` rewrite, undebounced.

## Changes

| File | Change |
|---|---|
| `lib/providers/canonical_doc_provider.dart` | `_loadingPreservingDocument` (copyWithPrevious) at the 3 sites; `_releaseOptimisticEcho` clears the `pendingCnlEditProvider` pin on supersession/wrong-file but **not** on parse error (that text is the user's draft) |
| `lib/services/canvas_api_client.dart` | `.timeout(timeout)` on the 3 raw canonical calls — they bypassed `basePost`, so a stall wedged `_pendingPushes > 0` forever |
| `lib/screens/studio_screen.dart` | Autosave selector widened to `(graph, pipelinePhases, pipeline)`; snackbar listener so a failed sync is visible |
| `lib/screens/studio/pipeline_stage_area.dart` | `animateToPage` → `jumpToPage` for top-bar taps |
| `lib/providers/workspace_provider.dart` | `_persist()` debounced 300ms; `debugSetDebounces` seam |
| `lib/providers/step_unlock_provider.dart` | Whole-state watch → 5 field `select`s |
| `lib/providers/running_notebook_tasks_provider.dart` | `debugSetPollInterval` seam for the periodic 3s poller |
| `test/screens/studio_screen_test.dart` | Zero the debounces + disable the poller; `_NoOpPipelineController` given real `@override`s (its `noSuchMethod` never intercepted concrete inherited members, so it suppressed nothing) |
| `test/providers/canvas/canonical_doc_failure_preservation_test.dart` | **New** — 2 tests |
| `test/providers/canvas/canvas_viewport_isolation_test.dart` | +1 test for Train/Eval autosave |

### Test-seam semantics worth remembering
`Duration.zero` means **synchronous, no timer** for `_persist` (tests assert the write) and
**disabled** for `scheduleServerSync` (tests never assert the upload, and firing it eagerly
made every suite attempt real network calls). A zero-duration `Timer` is still a *pending*
timer at the point `flutter_test` checks invariants, which is the whole problem being solved.

### Why the 18 StudioScreen tests were failing
Not a logic bug: a leaked 1500ms `_serverSyncTimer` plus a periodic 3s notebook poller.
Both are cancelled only in `ref.onDispose`, which runs *after* `_verifyInvariants`, so the
tests died on "A Timer is still pending" before reaching any assertion. Pre-existing since
`5f5fbd80` (2026-07-19).

## Verification

- `flutter analyze`: **0 errors** (the `StableNmtkTextInput` errors were fixed by a separate
  background task that landed in `akida_deploy_panel.dart` / `learning_config_panel.dart`).
- Full suite: **1722 passing, 48 failing, 18 fixed, zero regressions** vs the round-1
  baseline (66). Both `StudioScreen syncs canvas parameter edits back to CNL` and
  `Canvas→CNL: cnlSpecProvider change updates specTextProvider` now pass.
- The new preservation test was confirmed to **fail** when `_loadingPreservingDocument` is
  reverted to a bare `AsyncLoading()`, so it genuinely guards the bug.

## Still to check manually (needs the running app)

1. Edit a node → CNL updates. Then break the backend: CNL must keep the **last good** text,
   a snackbar must name the failure, and reconnecting must resume without a restart.
2. Edit only the Train canvas, wait >2s, hot-restart — the DAG must survive. Repeat for Eval.
3. Tap through steps: intermediate steps must not build; resident memory well under 670MB.

## Deferred (flagged, not done)

- **CNL for Train/Eval is a feature, not a bug fix** — needs `pipelineCnlProvider` rebound to
  `s.pipelinePhases` and a reachable host tab. Design question: should a training DAG have a
  CNL representation at all?
- Undo on pipeline canvases undoes an *architecture* edit.
- `autoLayoutGraph` bypasses `_publishGraph` and `_recordLayout`, so auto-laid-out positions
  are reset by the next mirror; four architecture `CanvasScreen`s each measure width
  independently, so opening step 5/6 fires a full BFS relayout of the shared graph.
- `initDefaultPhases` guards on `train.nodes.isNotEmpty` even when seeding *eval*.
