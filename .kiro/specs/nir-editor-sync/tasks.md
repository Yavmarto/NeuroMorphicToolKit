# Implementation Plan

## Overview

This plan implements the NIR Editor Sync bugfix using the exploratory bug-condition methodology.
Tasks are ordered so that exploration and preservation tests are written and run on unfixed code
**first**, followed by the four implementation fixes (scaffold, guard narrow, new notifier
methods, new widgets, template patch, comment cleanup), and finally unit, widget, and
integration tests to validate the fix end-to-end.

## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "tasks": ["1", "2"],
      "description": "Exploration and preservation tests — written and run on UNFIXED code before any implementation"
    },
    {
      "wave": 2,
      "tasks": ["3.1"],
      "description": "Scaffolding: _syncingNirToCanvas flag + _nirDebounce timer + dispose cleanup"
    },
    {
      "wave": 3,
      "tasks": ["3.2", "3.3"],
      "description": "Guard narrow + new notifier methods (depend on 3.1; can land in parallel)"
    },
    {
      "wave": 4,
      "tasks": ["3.4", "3.5"],
      "description": "Widget editable UI + template-load patch (depend on 3.3; can land in parallel)"
    },
    {
      "wave": 5,
      "tasks": ["3.6"],
      "description": "Remove stale workaround comment (depends on 3.4)"
    },
    {
      "wave": 6,
      "tasks": ["3.7", "3.8"],
      "description": "Verify exploration and preservation tests pass on fixed code"
    },
    {
      "wave": 7,
      "tasks": ["4", "5", "6"],
      "description": "Unit, widget, and integration tests (depend on 3.1–3.5; can run in parallel)"
    },
    {
      "wave": 8,
      "tasks": ["7"],
      "description": "Final checkpoint — all tests pass"
    }
  ]
}
```

## Tasks

- [x] 1. Write bug-condition exploration test (run BEFORE implementing the fix)
  - **Property 1: Bug Condition** - NIR Parameter Edit Propagates to Canvas and CNL
  - **CRITICAL**: This test MUST FAIL on unfixed code — failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behaviour — it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists (missing editable fields + blocked CNL update)
  - **Scoped PBT Approach**: For each of the four root-cause defects, scope the property to the concrete failing case to ensure reproducibility
  - **Sub-cases to cover:**
    - 1a — No editable fields: mount `NirImporterTab` with a non-empty `CanvasGraph` (e.g., one LIF node) and assert that at least one `TextField` is present in the widget tree. Expected on unfixed code: FAILS because `_LoadedView` only renders `_NirTreeView`
    - 1b — NIR→CNL blocked by guard: call `studioSyncNotifier.onCanvasCnlSpec(prev, next)` with `viewMode == StudioViewMode.nir` and assert that `specTextProvider` IS updated. Expected on unfixed code: FAILS because the guard contains `|| viewMode == StudioViewMode.nir`
    - 1c — No live update in NIR mode: update `canvasProvider` while NIR is active and assert that `nirImportProvider.status` transitions to reflect the new graph. Expected on unfixed code: FAILS because no canvas listener exists on the NIR tab
    - 1d — Template not reflected in NIR: call `applyTemplateToWorkspace` while NIR is active and assert that `nirImportProvider.result` is refreshed. Expected on unfixed code: FAILS because the post-load NIR sync block is absent
  - Property assertion: for all LIF nodes with `threshold ∈ [0.1, 2.0]`, committing a new threshold via the (not-yet-existing) NIR editor results in `canvasProvider.graph.nodes[id].parameters['threshold'] == newValue`
  - Run test suite on UNFIXED code
  - **EXPECTED OUTCOME**: Tests FAIL — this is correct; it proves the bugs exist
  - Document every counterexample found (e.g., "no TextField in tree", "specTextProvider unchanged", "nirImportProvider not refreshed")
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.6, 1.7_

- [x] 2. Write preservation property tests (run BEFORE implementing the fix)
  - **Property 2: Preservation** - Non-NIR-Edit Inputs Are Unaffected
  - **IMPORTANT**: Follow observation-first methodology — run these tests on unfixed code first to capture baseline, then assert the same on fixed code
  - **Observation step** (on UNFIXED code):
    - Observe: loading a `.nir` file updates CNL + canvas graph ✓
    - Observe: `onCanvasCnlSpec` with `viewMode == cnl` does NOT update `specTextProvider` ✓
    - Observe: `specTextProvider` change triggers debounced canvas update ✓
    - Observe: `syncCnlToCanvas` fires on tab-switch from CNL → canvas ✓
    - Observe: `applyTemplateToWorkspace` while canvas active updates canvas + CNL ✓
    - Observe: idle NIR placeholder shows when no source loaded ✓
  - **Write property-based tests:**
    - P2a — File-import write-back preserved: for any `.nir` file bytes, assert CNL and canvas update exactly as before
    - P2b — `onCanvasCnlSpec` guard preserved in CNL mode: for any canvas mutation while `viewMode == cnl`, assert `specTextProvider` is NOT updated
    - P2c — CNL→Canvas debounced sync preserved: for any CNL string, assert canvas is updated within 400 ms debounce and the round-trip CNL matches
    - P2d — Tab-switch one-shot syncs preserved: switch CNL→canvas, assert `syncCnlToCanvas` called; switch canvas→NIR, assert `syncFromCanvas` called
    - P2e — Template load in CNL/canvas mode unchanged: call `applyTemplateToWorkspace` while CNL/canvas active; assert existing behaviour identical
    - P2f — Pipeline auto-populate guard unchanged: set `pipelineProvider.nir_code`; assert NIR tab updates only when `source == NirSource.none || source == NirSource.pipeline`
  - Run all preservation tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS — confirms baseline behaviour to preserve
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Fix: NIR Editor three-way sync (four root causes)

  - [x] 3.1 `lib/providers/studio_sync_notifier.dart` — add `_syncingNirToCanvas` flag and update `dispose`
    - Declare `bool _syncingNirToCanvas = false;` as a private instance field alongside the existing sync flags
    - Add `Timer? _nirDebounce;` alongside existing debounce timers
    - Cancel `_nirDebounce` in the `dispose` method
    - No logic changes yet — this is purely scaffolding for changes 3.2 and 3.3
    - _Bug_Condition: isBugCondition(input) where input.interactionType == EXTERNAL_CHANGE AND viewMode == NIR AND nirTabNotRefreshed_
    - _Requirements: 2.5_

  - [x] 3.2 `lib/providers/studio_sync_notifier.dart` — narrow `onCanvasCnlSpec` guard
    - Current guard: `if (viewMode == StudioViewMode.cnl || viewMode == StudioViewMode.nir) return;`
    - New guard: `if (viewMode == StudioViewMode.cnl) return;`
    - This allows canvas-generated CNL to propagate to `specTextProvider` and `workspaceProvider` when NIR is the active view (NIR edits flow through canvas, and the resulting CNL must be stored)
    - Verify the CNL-mode guard is still intact after the change
    - _Bug_Condition: isBugCondition(input) where input.interactionType == PARAMETER_EDIT AND viewMode == NIR_
    - _Expected_Behavior: cnlSpecProvider change → specTextProvider.set(next) + workspaceProvider.updateActiveFileContent(next) when viewMode == nir_
    - _Preservation: guard still returns early when viewMode == cnl (user owns CNL editor)_
    - _Requirements: 2.2, 2.3_

  - [x] 3.3 `lib/providers/studio_sync_notifier.dart` — add `scheduleNirFromCanvasDebounced`, `beginNirEdit`, `endNirEdit`
    - Add `beginNirEdit()`: sets `_syncingNirToCanvas = true`
    - Add `endNirEdit()`: sets `_syncingNirToCanvas = false`
    - Add `scheduleNirFromCanvasDebounced(CanvasGraph graph)`:
      - Guard: `if (_syncingNirToCanvas) return;` — skip when a NIR-originated change is in flight (loop prevention for **Property 3**)
      - Guard: read `studioViewModeProvider`; return if `viewMode != StudioViewMode.nir`
      - Cancel any pending `_nirDebounce`
      - Schedule 400 ms `Timer` → `ref.read(nirImportProvider.notifier).syncFromCanvas(graph)` when `mounted && !_syncingNirToCanvas`
    - _Bug_Condition: isBugCondition(input) where interactionType == EXTERNAL_CHANGE AND viewMode == NIR AND nirTabNotRefreshed_
    - _Expected_Behavior: canvas change while NIR active → nirImportProvider.syncFromCanvas called within 400 ms_
    - _Preservation: _syncingNirToCanvas = true during NIR edit prevents re-entry loop_
    - _Requirements: 2.5, 2.7_

  - [x] 3.4 `lib/widgets/nir_importer_tab.dart` — add editable UI and live-update listener
    - **Header**: rename title from `'NIR Inspector'` to `'NIR Editor'`
    - **Live-update listener**: inside the widget's `build` (or `ConsumerStatefulWidget` `didChangeDependencies`), add:
      ```dart
      ref.listen<CanvasState>(canvasProvider, (prev, next) {
        final viewMode = ref.read(studioViewModeProvider).viewMode;
        if (viewMode != StudioViewMode.nir) return;
        ref.read(studioSyncNotifierProvider.notifier)
            .scheduleNirFromCanvasDebounced(next.graph);
      });
      ```
    - **`_NirGraphEditorPanel` widget** (`ConsumerWidget`):
      - Reads `canvasProvider.graph.nodes` and `nirNodeTypeMapProvider`
      - Renders a scrollable `ListView` of `_NirNodeCard` widgets, one per canvas node
      - "Add Node" button at bottom: opens a dialog with a `DropdownButtonFormField` of available `NirNodeType`s, then calls `canvasProvider.notifier.addNode(...)` wrapped in `beginNirEdit`/`endNirEdit`
    - **`_NirNodeCard` widget** (`ConsumerWidget`):
      - Wraps an `ExpansionTile`; header row shows node label, NIR type badge, delete `IconButton`
      - Body: for each `NirParameterDef`, renders the matching field type (mirrors `canvas/property_panel.dart`):
        - `int` / `float` → `TextFormField` with numeric keyboard and range validation
        - `text` → `TextFormField`
        - `bool` → `SwitchListTile`
        - `enum` → `DropdownButtonFormField`
      - On field commit (`onFieldSubmitted` / `onChanged`):
        ```dart
        ref.read(studioSyncNotifierProvider.notifier).beginNirEdit();
        ref.read(canvasProvider.notifier).updateNodeParameters(node.id, updatedParams);
        ref.read(studioSyncNotifierProvider.notifier).endNirEdit();
        ```
      - Delete button: same `beginNirEdit`/`endNirEdit` pattern around `canvasProvider.notifier.removeNode(node.id)`
    - **`_NirEdgeList` widget** (`ConsumerWidget`):
      - Compact `ListView` of edges (source → target, weight, delay)
      - Each row: editable weight/delay fields + delete `IconButton`
      - "Add Edge" row: source/target dropdowns + confirm button
      - All structural mutations wrapped in `beginNirEdit`/`endNirEdit` around `addEdge`/`removeEdge`
    - **Preserve** idle / loading / error state branches — these are untouched
    - _Bug_Condition: isBugCondition(input) where noEditableFieldsPresent(nirTab) OR noStructuralControlsPresent(nirTab)_
    - _Expected_Behavior: every parameter field commit calls updateNodeParameters; every structural control calls addNode/removeNode/addEdge/removeEdge; all wrapped in beginNirEdit/endNirEdit_
    - _Preservation: idle placeholder unchanged; file-import write-back path unchanged_
    - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.7_

  - [x] 3.5 `lib/services/template_load_guard.dart` — trigger NIR refresh after template load
    - After the existing `await Future.wait([...syncToCanvas()])` block, append:
      ```dart
      final viewMode = ref.read(studioViewModeProvider).viewMode;
      if (viewMode == StudioViewMode.nir) {
        final canvasGraph = ref.read(canvasProvider).graph;
        if (canvasGraph.nodes.isNotEmpty) {
          ref.read(nirImportProvider.notifier).syncFromCanvas(canvasGraph);
        }
      }
      ```
    - No changes to the existing CNL/canvas template-load path
    - _Bug_Condition: isBugCondition(input) where interactionType == EXTERNAL_CHANGE AND viewMode == NIR AND nirTabNotRefreshed_
    - _Expected_Behavior: applyTemplateToWorkspace while NIR active → nirImportProvider.syncFromCanvas called on the freshly loaded canvas graph_
    - _Preservation: existing applyTemplateToWorkspace behaviour identical when viewMode ≠ nir_
    - _Requirements: 2.6_

  - [x] 3.6 `lib/screens/studio_screen.dart` — remove stale workaround comment
    - Locate and delete the comment that documents NIR's one-directional sync limitation (a TODO / workaround note left when the limitation was first accepted)
    - No logic changes in this file
    - _Requirements: 2.7_

  - [x] 3.7 Verify bug-condition exploration test now passes
    - **Property 1: Expected Behavior** - NIR Parameter Edit Propagates to Canvas and CNL
    - **IMPORTANT**: Re-run the SAME tests from task 1 — do NOT write new tests
    - Run all four sub-cases (1a–1d) against the fixed code
    - **EXPECTED OUTCOME**: All sub-cases PASS — confirms all four root causes are fixed
    - _Requirements: 2.1, 2.2, 2.3, 2.6, 2.7_

  - [x] 3.8 Verify preservation tests still pass after fix
    - **Property 2: Preservation** - Non-NIR-Edit Inputs Are Unaffected
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run all P2a–P2f preservation properties against the fixed code
    - **EXPECTED OUTCOME**: All preservation tests PASS — confirms no regressions
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4. Unit tests for new and changed `StudioSyncNotifier` behaviour
  - **Depends on**: tasks 3.1, 3.2, 3.3
  - Test `onCanvasCnlSpec` with `viewMode == nir`: verify `specTextProvider` IS updated (narrowed guard)
  - Test `onCanvasCnlSpec` with `viewMode == cnl`: verify `specTextProvider` is NOT updated (guard preserved)
  - Test `scheduleNirFromCanvasDebounced` with `_syncingNirToCanvas = true`: verify `syncFromCanvas` is NOT called — **Property 3: Loop Prevention** - NIR Edit Does Not Re-Trigger NIR Refresh; validates Requirement 2.5
  - Test `scheduleNirFromCanvasDebounced` with NIR active and flag false: verify `syncFromCanvas` IS called after the 400 ms debounce window
  - Test `scheduleNirFromCanvasDebounced` with non-NIR `viewMode`: verify `syncFromCanvas` is NOT called
  - Test `beginNirEdit` / `endNirEdit` toggle: verify flag is set `true` then `false` in the correct order
  - Test `applyTemplateToWorkspace` with NIR active (mock `nirImportProvider`): verify `syncFromCanvas` is called on the updated graph
  - Test `NirImportNotifier.syncFromCanvas` is NOT called when `source == NirSource.file` (file-priority guard unchanged)
  - _Requirements: 2.2, 2.5, 2.6, 2.7, 3.3, 3.4_

- [x] 5. Widget tests for `_NirNodeCard` field commit → `canvasProvider` update

  - **Depends on**: task 3.4
  - Mount `_NirNodeCard` for a LIF node with a `threshold` parameter inside a `ProviderScope` backed by a real `canvasProvider`
  - Enter new threshold value `0.8` in the `TextFormField` and submit
  - Assert `canvasProvider.graph.nodes[lifNodeId].parameters['threshold'] == 0.8`
  - Assert `beginNirEdit` was called before and `endNirEdit` after `updateNodeParameters` (verify via captured call sequence)
  - Assert no recursive `scheduleNirFromCanvasDebounced` call is triggered during the same edit (the `_syncingNirToCanvas` guard catches it)
  - Test `_NirEdgeList` add-edge flow: fill source/target dropdowns, tap confirm, assert edge appears in `canvasProvider.graph.edges`
  - Test `_NirNodeCard` delete button: tap delete, assert node removed from `canvasProvider.graph.nodes`
  - _Requirements: 2.1, 2.3, 2.4, 2.5_

- [x] 6. Integration tests for full three-way sync
  - **Depends on**: tasks 3.1–3.5
  - **Test A — Full three-way sync round-trip**: Load a template in CNL mode → switch to NIR tab → edit LIF threshold via `_NirNodeCard` → switch to canvas tab → assert canvas node shows updated threshold → assert CNL text contains the updated threshold value
  - **Test B — Template Gallery load while NIR active**: Open NIR tab with an existing graph → call `applyTemplateToWorkspace` with a different template → assert `_NirGraphEditorPanel` immediately reflects the new template's nodes and parameters
  - **Test C — Switching editors mid-edit**: Begin editing a parameter field in NIR → switch to canvas tab before committing → assert no partial state corruption in either `canvasProvider` or `nirImportProvider`
  - **Test D — Structural edit round-trip**: Add a node via `_NirGraphEditorPanel` "Add Node" → assert node appears in canvas → assert CNL text is regenerated with the new node → remove the node via the delete button → assert node is absent from canvas and CNL
  - **Test E — Loop prevention under repeated edits**: Perform N = 5 sequential NIR parameter edits on the same node → assert `syncFromCanvas` is called exactly 5 times, not 10 (confirms **Property 3: Loop Prevention**)
  - **Test F — Canvas change while NIR active (live update)**: Mount studio with NIR tab active → mutate canvas via `canvasProvider.notifier.updateNodeParameters` directly → wait 400 ms debounce → assert `nirImportProvider.result` reflects the mutation
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

- [x] 7. Checkpoint — ensure all tests pass
  - Run full test suite: `flutter test`
  - All exploration tests (task 1 sub-cases 1a–1d) PASS
  - All preservation tests (task 2 sub-cases P2a–P2f) PASS
  - All unit tests (task 4) PASS
  - All widget tests (task 5) PASS
  - All integration tests (task 6, tests A–F) PASS
  - No regressions in existing CNL ↔ canvas sync or file-import paths
  - If any test fails, resolve it before marking this task complete
  - Ask the user if questions arise before closing the spec

## Notes

- The bug-condition exploration tests (task 1) and preservation tests (task 2) MUST be written and run against the **unfixed** code before any implementation work begins. Their results document the pre-fix baseline.
- The four root causes are independent at the file level (one Dart file each) and can be addressed in parallel once task 3.1 scaffolding is complete, but task 3.2 and 3.3 must both land before 3.4 and 3.5 can be completed correctly.
- The `_syncingNirToCanvas` flag is the single mechanism preventing the NIR→Canvas→CNL→onCanvasCnlSpec path from bouncing back into the NIR live-update listener. Any refactor that removes or relocates this flag must be accompanied by a re-run of Property 3 (loop-prevention) tests.
- All field-type rendering in `_NirNodeCard` should mirror `canvas/property_panel.dart` exactly — do not diverge in input validation logic, since both panels write to `canvasProvider.notifier.updateNodeParameters`.
- `applyTemplateToWorkspace` (task 3.5) calls `syncFromCanvas` synchronously (no debounce) because the template load itself is already an async operation with a defined completion point. The debounce in `scheduleNirFromCanvasDebounced` is for real-time edits only.
