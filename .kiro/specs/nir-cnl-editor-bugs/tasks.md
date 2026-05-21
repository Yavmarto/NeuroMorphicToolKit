# Implementation Plan

## Overview

Exploratory bugfix task list for `nir-cnl-editor-bugs`. Follows the bug-condition methodology:
write bug condition exploration tests first (Property 1), write preservation tests second (Property 2),
apply the three-file NIR type chain fix and two missing-validation call-site fixes, then verify.
The four bugs share two root causes: hardcoded NIR type strings in `canvasGraphFromCanonical`
(fixed via a Python + Dart model + Dart utility three-file chain) and missing `validationProvider.validate`
calls after `_mirrorProjection` and `applyTemplateToWorkspace`.

## Task Dependency Graph

```json
{
  "waves": [
    { "wave": 1, "tasks": ["1", "2"] },
    { "wave": 2, "tasks": ["3.1", "3.2", "3.3", "4.1", "4.2", "5.1"] },
    { "wave": 3, "tasks": ["3.4", "3.5", "4.3", "4.4", "5.2", "5.3"] },
    { "wave": 4, "tasks": ["4.5", "6.1", "6.2", "7.1", "7.2", "7.3", "7.4"] },
    { "wave": 5, "tasks": ["8"] }
  ]
}
```

## Tasks

- [x] 1. Write bug condition exploration test — NIR type resolution in `canvasGraphFromCanonical`
  - **Property 1: Bug Condition** - NIR Type Hardcoding in canvasGraphFromCanonical
  - **CRITICAL**: This test MUST FAIL on unfixed code — failure confirms the bugs exist
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior — it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate every non-LIF node gets stamped with `nirType: 'nir.LIF'` and `componentId: 'lif_population'`
  - **Scoped PBT Approach**: Scope the property to the concrete failing case — a `CanvasProjection` containing one `nir.Input` node (where `isBugConditionNodeType` returns `true` because `'nir.Input' != 'nir.LIF'`)
  - Add `nirType` field to the `CanvasNode` model stub used in tests (pre-empt the model change from Change 2)
  - Call `canvasGraphFromCanonical` with a projection whose single node has `nirType: 'nir.Input'`
  - Assert `result.nodes.first.nirType == 'nir.Input'` and `result.nodes.first.componentId == 'input_node'`
  - Also test a three-node projection: `nir.Input`, `nir.LIF`, `nir.Output` — assert each node's `nirType` matches its projection type
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS — returns `nirType: 'nir.LIF'` and `componentId: 'lif_population'` for Input/Output nodes (counterexample confirmed)
  - Document counterexamples found (e.g. `canvasGraphFromCanonical({nir.Input}) → nirType='nir.LIF'`)
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 2.1, 2.4_

- [x] 2. Write preservation property tests — pure-LIF graphs are unchanged (BEFORE implementing fix)
  - **Property 2: Preservation** - Pure-LIF Graph Output Identical Before and After Fix
  - **IMPORTANT**: Follow observation-first methodology
  - Observe: call `canvasGraphFromCanonical` on UNFIXED code with a projection where every node has `nirType: 'nir.LIF'` (or `null`) — record the exact `componentId`, `nirType`, parameter values, and position for each node, and the full edges list
  - Write property-based test: for any `CanvasProjection` where all nodes have `nirType == 'nir.LIF'` or `nirType == null`, the fixed function produces a graph whose nodes and edges are bitwise-identical to what the unfixed function produced
  - Include edge-count sub-property: for any `CanvasProjection` with N edges, `canvasGraphFromCanonical` returns a `CanvasGraph` with exactly N edges (matching `sourceNodeId`, `targetNodeId`, `weight`) — this covers Property 3 (edge count) as it also applies to the all-LIF baseline
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (confirms baseline behavior to preserve and edge count is correct today)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.5, 2.3_

- [x] 3. Fix Bug 1 & 2 — NIR type metadata three-file chain

  - [x] 3.1 Emit `nir_type` from `_project_to_canvas` in Python backend
    - In `neurocnl/neurosim/app/services/canonical_editor_projection.py`, inside the `nodes` loop (lines 163–172), resolve the NIR primitive type from `nir_graph.nodes` when `nir_graph` is not `None`
    - Add `nir_type: str | None = None` before the append
    - When `nir_graph is not None and name in nir_graph.nodes`, set `nir_type = f"nir.{type(nir_graph.nodes[name]).__name__}"`
    - Add `"nir_type": nir_type` to the node dict
    - Emit `"nir_type": None` when `nir_graph` is `None` or the name is not in `nir_graph.nodes`
    - _Bug_Condition: `isBugConditionNodeType` — any node whose actual NIR type differs from `nir.LIF`; `_project_to_canvas` called with a `nir_graph` containing a non-LIF node_
    - _Expected_Behavior: `nir_type` key present in every node dict; value is `f"nir.{type(nir_graph.nodes[name]).__name__}"` for known nodes_
    - _Preservation: `nir_type: None` emitted when `nir_graph` is `None`; all other node dict fields (`id`, `label`, `type`, `size`, `shape`, `threshold`, `tau`) unchanged_
    - _Requirements: 2.1, 2.4_

  - [x] 3.2 Add `nirType` field to `CanvasNode` Dart model
    - In `neurocnl/frontend/lib/models/canonical_editor_document.dart`, add `final String? nirType;` to the `CanvasNode` class
    - Add `this.nirType` to the named constructor parameters (optional)
    - In `fromJson`: add `nirType: json['nir_type'] as String?,`
    - In `toJson`: add `if (nirType != null) 'nir_type': nirType,`
    - _Bug_Condition: Dart model silently discards `nir_type` from JSON because field is absent_
    - _Expected_Behavior: `CanvasNode.fromJson({'nir_type': 'nir.Input', ...}).nirType == 'nir.Input'`_
    - _Preservation: All existing `CanvasNode` fields (`id`, `label`, `type`, `size`, `shape`, `threshold`, `tau`) unchanged; `nirType` is optional and defaults to `null`, so existing JSON without the field deserializes unchanged_
    - _Requirements: 2.1, 2.4_

  - [x] 3.3 Replace hardcoded type strings in `canvasGraphFromCanonical` with `_nirTypeToComponentId` map lookup
    - In `neurocnl/frontend/lib/utils/canvas_projection_utils.dart`, add a top-level `const Map<String, String> _nirTypeToComponentId` mapping all known NIR types to their `legacyComponentId` values (see design Change 3 for the full map)
    - In the nodes loop, read `final rawNirType = projection.nodes[index].nirType;`
    - Set `final resolvedNirType = rawNirType ?? 'nir.LIF';` (backward-compatible fallback for pre-fix backend)
    - Set `final resolvedComponentId = _nirTypeToComponentId[resolvedNirType] ?? resolvedNirType;`
    - Replace `componentId: 'lif_population'` with `componentId: resolvedComponentId`
    - Replace `nirType: 'nir.LIF'` with `nirType: resolvedNirType`
    - _Bug_Condition: `canvasGraphFromCanonical` called with any projection node where `nirType != 'nir.LIF'`_
    - _Expected_Behavior: each resulting `CanvasNode.nirType == projection.nodes[index].nirType`; `componentId == _nirTypeToComponentId[nirType]`_
    - _Preservation: when `nirType` is `null` or `'nir.LIF'`, resolved values are `'nir.LIF'` and `'lif_population'` — identical to unfixed behavior; edge count and all other fields unchanged_
    - _Requirements: 2.1, 2.4, 2.3, 3.1, 3.5_

  - [x] 3.4 Verify bug condition exploration test (Property 1) now passes
    - **Property 1: Expected Behavior** - NIR Type Resolution in canvasGraphFromCanonical
    - **IMPORTANT**: Re-run the SAME test from task 1 — do NOT write a new test
    - The test from task 1 encodes the expected behavior: `result.nodes[i].nirType == projection.nodes[i].nirType` and `componentId == _nirTypeToComponentId[nirType]`
    - Run bug condition exploration test from step 1 on the fixed code (after changes 3.1–3.3)
    - **EXPECTED OUTCOME**: Test PASSES (confirms Bug 1 and Bug 2 type-metadata path is fixed)
    - _Requirements: 2.1, 2.4_

  - [x] 3.5 Verify preservation property tests still pass
    - **Property 2: Preservation** - Pure-LIF Graphs Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run preservation property tests from step 2 on the fixed code
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions in the all-LIF / null-type path)
    - Confirm edge count property also still passes
    - _Requirements: 3.1, 3.5, 2.3_

- [x] 4. Fix Bug 2 & 4 — missing validation call sites

  - [x] 4.1 Call `validationProvider.validate` after graph write in `_mirrorProjection`
    - In `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`, after `state = state.copyWith(graph: _normalizeGraph(newGraph));` inside `_mirrorProjection`, add `ref.read(validationProvider.notifier).validate(newGraph);`
    - This is fire-and-forget (same pattern as `_doPush`) — no `await` needed
    - Do NOT modify `setGraph`, `_doPush`, or any other method; this is an additive single-line change
    - _Bug_Condition: `isBugConditionMissingValidation('mirrorProjection')` — `_mirrorProjection` sets state without calling `validate`_
    - _Expected_Behavior: after `_mirrorProjection` returns, `validationProvider.state` has transitioned away from any prior stale value_
    - _Preservation: `_doPush` → `validate` path unchanged; `setGraph` remains a silent setter; debounce flags and `_syncingCnlToCanvas` / `_syncingCanvasToCnl` guards unchanged_
    - _Requirements: 2.2, 2.5, 2.7, 2.8_

  - [x] 4.2 Call `validationProvider.validate` after template load in `applyTemplateToWorkspace`
    - In `neurocnl/frontend/lib/services/template_load_guard.dart`, add imports for `canvas_provider.dart` and `validation_provider.dart` (aliased as `canvas_val`)
    - After `await ref.read(pipelineProvider.notifier).runParseAndValidate(...)`, read the canvas graph: `final graph = ref.read(canvasProvider).graph;`
    - If `graph.nodes.isNotEmpty`, call `unawaited(ref.read(canvas_val.validationProvider.notifier).validate(graph));`
    - Use `unawaited` (same pattern as NIR write-back) to avoid blocking the template load on the validation HTTP round-trip
    - _Bug_Condition: `isBugConditionMissingValidation('applyTemplateToWorkspace')` — function completes without calling `validate`_
    - _Expected_Behavior: after `applyTemplateToWorkspace` resolves, `validationProvider.validate` has been called with the populated canvas graph; empty-graph guard prevents spurious calls_
    - _Preservation: `workspaceProvider`, `specTextProvider`, `selectedHardwareConfigProvider`, `canonicalDocProvider.updateFromCnl`, and `pipelineProvider.runParseAndValidate` calls all unchanged_
    - _Requirements: 2.2, 2.5_

  - [x] 4.3 Verify validation is called after `_mirrorProjection` (Property 1 sub-check)
    - **Property 1: Expected Behavior** - Validation Always Follows _mirrorProjection
    - Write a targeted unit test: instantiate a `CanvasNotifier` with a mock `validationProvider`; call `_mirrorProjection` with a non-empty projection; assert `mockValidationProvider.validate` was called exactly once with the new graph
    - Run test on fixed code
    - **EXPECTED OUTCOME**: Test PASSES (confirms Bug 4 / validation staleness is fixed)
    - _Requirements: 2.2, 2.7, 2.8_

  - [x] 4.4 Verify validation is called after `applyTemplateToWorkspace` (Property 1 sub-check)
    - **Property 1: Expected Behavior** - Validation Always Follows applyTemplateToWorkspace
    - Write a targeted widget test: call `applyTemplateToWorkspace` in a `ProviderScope` container with mock providers; after the async call completes, assert `mockValidationProvider.validate` was called with a non-empty graph
    - Also assert the empty-graph guard: when the canvas graph is empty after template load, `validate` is NOT called
    - Run tests on fixed code
    - **EXPECTED OUTCOME**: Tests PASS (confirms Bug 2 validation path is fixed)
    - _Requirements: 2.2, 2.5_

  - [x] 4.5 Verify preservation tests for `_doPush` still pass
    - **Property 2: Preservation** - `_doPush` Validation Unchanged
    - Confirm that user-initiated canvas mutations (add node, remove node, add edge, update parameters) still flow through `_pushToCanonical` → `_doPush` → `validationProvider.validate` exactly as before
    - Run any existing `_doPush` or `CanvasNotifier` mutation tests
    - **EXPECTED OUTCOME**: Tests PASS (no regression in the existing validation path)
    - _Requirements: 3.2, 3.3_

- [x] 5. Fix Bug 3 — remove NIR viewer column from `_NirGraphEditorPanel`

  - [x] 5.1 Remove `Expanded(flex: 2, child: _NirTreeView(...))` column
    - In `neurocnl/frontend/lib/widgets/nir_importer_tab.dart`, inside `_NirGraphEditorPanel.build`, locate the `Row` with two `Expanded` children
    - Remove the `Expanded(flex: 2, child: _NirTreeView(...))` child, the `VerticalDivider` between the columns, and the enclosing `Row` wrapper
    - Replace with a single-child layout: the existing `Expanded(flex: 3)` node/edge editor content promoted to the top level
    - Retain or delete `_NirTreeView`, `_GroupTile`, `_DatasetTile`, and `_Badge` private classes — either is safe; deleting reduces code size
    - _Bug_Condition: `isBugConditionViewerPresent` — `_NirGraphEditorPanel` Row children list contains `Expanded(flex: 2, child: _NirTreeView)`_
    - _Expected_Behavior: widget tree contains exactly one `Expanded` child; `find.byType(_NirTreeView)` returns zero matches_
    - _Preservation: `_NirNodeCard` widgets for every canvas node and `_NirEdgeList` widget continue to render; empty-graph path shows `_EmptyGraphEditor` unchanged_
    - _Requirements: 2.6, 3.1, 3.8_

  - [x] 5.2 Verify NIR viewer column is absent (Property 1 sub-check)
    - **Property 1: Expected Behavior** - NIR Viewer Column Absent from _NirGraphEditorPanel
    - Write a widget test: render `_NirGraphEditorPanel` (or the parent `_LoadedView`) with a populated `NirInspectResult`; assert `find.byType(_NirTreeView)` returns zero matches; assert `find.byType(_NirNodeCard)` returns the expected count of node cards
    - Run test on fixed code
    - **EXPECTED OUTCOME**: Test PASSES (confirms tree view column is removed)
    - _Requirements: 2.6_

  - [x] 5.3 Verify node/edge editor column is intact (Property 2 sub-check)
    - **Property 2: Preservation** - Node/Edge Editor Column Still Renders
    - Run existing NIR tab widget tests that assert node cards and edge list are present
    - If no such tests exist, write one: render `_NirGraphEditorPanel` with a two-node, one-edge graph; assert `find.byType(_NirNodeCard)` finds 2 widgets and `find.byType(_NirEdgeList)` finds 1 widget
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regression in the editor panel)
    - _Requirements: 3.1, 3.8_

- [x] 6. Python `_project_to_canvas` unit and PBT tests

  - [x] 6.1 Write unit test — `_project_to_canvas` emits `nir_type` for known NIR node classes
    - In `neurocnl/neurosim/tests/`, write a pytest test that calls `_project_to_canvas` with a mock `NetworkIR` and a `nir_graph` whose nodes contain instances of `nir.LIF`, `nir.Input`, `nir.Output`, and `nir.CubaLIF`
    - Assert each returned node dict has a `"nir_type"` key whose value matches `f"nir.{type(node).__name__}"`
    - Also test the `nir_graph=None` path: assert `"nir_type"` key is present with value `None`
    - _Requirements: 2.1, 2.4_

  - [x] 6.2 Write PBT — `_project_to_canvas` type round-trip
    - **Property 1: Bug Condition** - Python nir_type Emission Round-Trip
    - Use `hypothesis` to generate arbitrary lists of NIR node class instances (drawn from the known NIR primitives)
    - For any non-empty list, assert every output node dict's `"nir_type"` matches the corresponding input node's class name
    - Run on fixed code; confirm test passes
    - _Requirements: 2.1, 2.4_

- [x] 7. Dart property-based tests (fast_check / dart_test)

  - [x] 7.1 Write PBT — type resolution round-trip across all `_nirTypeToComponentId` entries
    - **Property 1: Bug Condition** - Type Resolution Round-Trip
    - For any list of NIR type strings drawn from `_nirTypeToComponentId.keys`, construct a `CanvasProjection` with nodes carrying those types and call `canvasGraphFromCanonical`
    - Assert `result.nodes[i].nirType == inputTypes[i]` and `result.nodes[i].componentId == _nirTypeToComponentId[inputTypes[i]]`
    - Run on fixed code
    - _Requirements: 2.1, 2.4_

  - [x] 7.2 Write PBT — edge count preservation for arbitrary projections
    - **Property 2: Preservation** - Edge Count Preserved Through canvasGraphFromCanonical
    - For any `CanvasProjection` with 0–20 random edges (random `sourceNodeId`, `targetNodeId`, `weight`), assert `canvasGraphFromCanonical(projection).edges.length == projection.edges.length` and each edge's `sourceNodeId`, `targetNodeId`, `weight` match
    - Run on fixed code
    - _Requirements: 2.3, 3.1_

  - [x] 7.3 Write PBT — LIF-only graphs produce identical output before and after fix
    - **Property 2: Preservation** - Pure-LIF Identical Output
    - For any `CanvasProjection` where all nodes have `nirType == 'nir.LIF'` or `nirType == null`, assert the fixed `canvasGraphFromCanonical` output equals the output captured in task 2 (same componentId, same nirType, same parameters, same edges)
    - This is the Dart-side companion to the Python preservation property
    - Run on fixed code
    - _Requirements: 3.1, 3.5_

  - [x] 7.4 Write PBT — validation always follows `_mirrorProjection`
    - **Property 1: Bug Condition** - Validation Always Follows _mirrorProjection
    - For any non-empty `CanvasProjection` (arbitrary node count 1–10), calling `_mirrorProjection` on a fresh `CanvasNotifier` (with mock `validationProvider`) always results in `validationProvider.validate` being invoked at least once
    - Confirm no code path inside `_mirrorProjection` can skip the `validate` call
    - Run on fixed code
    - _Requirements: 2.2, 2.7, 2.8_

- [x] 8. Checkpoint — all tests pass
  - Run the full Dart/Flutter test suite: `flutter test neurocnl/frontend/`
  - Run the full Python test suite: `python3 -m pytest neurocnl/neurosim/`
  - Confirm every exploration test (Property 1) now passes after the fix
  - Confirm every preservation test (Property 2) still passes
  - Confirm no regressions in existing CNL↔canvas sync, `_doPush`, template load, and NIR file import paths
  - Ask the user if any questions arise before closing the spec

## Notes

- Tasks 1 and 2 MUST be completed (tests written and run against unfixed code) before any fix implementation begins.
- Task 1 exploration test is expected to FAIL on unfixed code — that failure is proof the bug exists. Do not alter the code to make it pass prematurely.
- Task 2 preservation test is expected to PASS on unfixed code — it establishes the behavioral baseline.
- The three-file chain (3.1 Python → 3.2 Dart model → 3.3 Dart utility) must be applied together before re-running the exploration test in 3.4.
- `_mirrorProjection` fix (4.1) and `applyTemplateToWorkspace` fix (4.2) are independent of the three-file chain and may be implemented in parallel.
- Bug 3 (5.1) is a pure widget removal and is independent of all other tasks.
- PBT tasks (6.x, 7.x) should be run on fixed code only; they complement the unit-level exploration/preservation tests from tasks 1 and 2.
- See design document sections "Bug Details", "Correctness Properties", and "Fix Implementation" for pseudocode and exact code snippets.
