# NIR/CNL Editor Bugs — Bugfix Design

## Overview

This document formalizes the fix design for four bugs in NeuroCNL Studio spanning the
Flutter frontend and Python backend. The bugs share two root causes:

1. `canvasGraphFromCanonical` hardcodes `componentId: 'lif_population'` and
   `nirType: 'nir.LIF'` for every canvas node, regardless of the actual NIR primitive
   type emitted by the backend projection. Fixing this requires (a) the Python
   `_project_to_canvas` function to emit `nir_type` from the live `nir_graph` node
   objects, (b) the Dart `canonical_editor_document.dart` `CanvasNode` model to carry
   that field, and (c) `canvasGraphFromCanonical` to read it.

2. `validationProvider.validate` is never called after graph mutations that bypass
   `_doPush` — specifically `_mirrorProjection` in `CanvasNotifier` and the
   `applyTemplateToWorkspace` function in `template_load_guard.dart`. The fix adds a
   `validate` call to each of those two sites.

Bug 3 (NIR viewer removal) is purely a widget change: remove the `Expanded(flex: 2)`
HDF5 tree column from `_NirGraphEditorPanel`.

Bug 4 (validation staleness after manual revert) is fixed entirely by the
`_mirrorProjection` validation call from root cause 2 — `_mirrorProjection` is the
path taken when a user's character-by-character revert causes `canonicalDocProvider`
to emit a new valid document.


## Glossary

- **Bug_Condition (C)**: The condition that triggers each bug — see per-bug
  formalizations in the Bug Details section.
- **Property (P)**: The desired observable behaviour once the fix is in place.
- **Preservation**: Behaviours in `CanvasNotifier`, `StudioSyncNotifier`,
  `applyTemplateToWorkspace`, and `_NirGraphEditorPanel` that must remain identical
  for all inputs that do NOT trigger a bug condition.
- **`canvasGraphFromCanonical`**: The Dart function in
  `neurocnl/frontend/lib/utils/canvas_projection_utils.dart` that converts a
  `CanvasProjection` from the backend into a `CanvasGraph` for the Riverpod
  `canvasProvider`. Currently hardcodes `componentId: 'lif_population'` and
  `nirType: 'nir.LIF'` for every node.
- **`_mirrorProjection`**: Private method of `CanvasNotifier` in
  `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`. Called by the
  `canonicalDocProvider` reactive listener whenever a new canonical document arrives
  (CNL parse, NIR import, template load). Calls `canvasGraphFromCanonical` and writes
  the result to `canvasProvider` state but currently never calls
  `validationProvider.validate`.
- **`_doPush`**: Private method of `CanvasNotifier` that calls both
  `canonicalDocProvider.updateFromCanvas` and `validationProvider.validate`. Only
  reachable from user-initiated canvas mutations — not from `_mirrorProjection` or
  `applyTemplateToWorkspace`.
- **`applyTemplateToWorkspace`**: Async function in
  `neurocnl/frontend/lib/services/template_load_guard.dart`. Sets spec text,
  workspace, hardware config, and triggers `canonicalDocProvider.updateFromCnl`.
  Currently does not call `validationProvider.validate` after the graph is populated.
- **`_project_to_canvas`**: Python function in
  `neurocnl/neurosim/app/services/canonical_editor_projection.py`. Builds the
  `CanvasProjection` sent to the frontend. Currently does not emit `nir_type` in the
  node dict, even though `nir_graph.nodes` contains typed NIR primitives.
- **`NIR_CANVAS_TYPE_SPECS`**: The `_nirNodeTypes` list in
  `neurocnl/frontend/lib/providers/canvas/nir_types_provider.dart`, keyed by NIR
  type id (e.g. `'nir.LIF'`, `'nir.Input'`). Port resolution, parameter display, and
  canvas rendering all look up nodes by `nirType`. Incorrect types cause silent
  failures.
- **`NirNodeType.legacyComponentId`**: The `componentId` value stored in a
  `CanvasNode` corresponding to a given NIR type — e.g. `'lif_population'` for
  `nir.LIF`, `'input_node'` for `nir.Input`. Currently each node type's
  `legacyComponentId` must be read from `_nirNodeTypes` rather than hardcoded.


## Bug Details

### Bug Condition (Bugs 1 & 2) — Hardcoded NIR Type in `canvasGraphFromCanonical`

Bugs 1 and 2 share the same bug condition: `canvasGraphFromCanonical` is called with
a `CanvasProjection` whose nodes represent non-LIF NIR primitives, yet the function
ignores any type information and stamps every node with `componentId: 'lif_population'`
and `nirType: 'nir.LIF'`. The condition holds whenever the projection contains at
least one node whose actual NIR type differs from `nir.LIF`.

**Formal Specification:**

```
FUNCTION isBugConditionNodeType(projection, nirNodeTypeMap)
  INPUT: projection  — CanvasProjection from the backend
         nirNodeTypeMap — Map<String, NirNodeType> from nir_types_provider
  OUTPUT: boolean

  FOR EACH node IN projection.nodes DO
    actualNirType := node.nirType   // field added by the fix to canonical_editor_document.dart
    IF actualNirType IS NULL
      RETURN true    // backend did not emit nir_type — same hardcoding bug
    IF actualNirType NOT IN nirNodeTypeMap
      RETURN true    // unknown type — would be silently misrepresented
    expectedComponentId := nirNodeTypeMap[actualNirType].legacyComponentId
    currentComponentId  := 'lif_population'   // what unfixed code would assign
    IF actualNirType != 'nir.LIF'
      RETURN true    // non-LIF node → hardcoded values are wrong
  END FOR
  RETURN false
END FUNCTION
```

**Examples:**

- A `.nir` file containing `nir.Input → nir.LIF → nir.Output`: the Input and Output
  nodes are assigned `nirType: 'nir.LIF'`; port resolution for `nir.Input` (which has
  only an `out` port) fails silently because the canvas looks up `nir.LIF` ports
  instead.
- A CNL template containing a `nir.CubaLIF` population: the canvas registers it as
  `nir.LIF`; the CubaLIF-specific parameters (`tau_mem`, `tau_syn`, `w_in`) are never
  shown in the property panel.
- A `.nir` file containing only `nir.LIF` nodes: the bug condition does NOT hold —
  the hardcoded values happen to be correct, so no visible regression.

### Bug Condition (Bugs 1 & 2) — Missing Validation After Graph Set

**Formal Specification:**

```
FUNCTION isBugConditionMissingValidation(path)
  INPUT: path — one of {'mirrorProjection', 'applyTemplateToWorkspace',
                        'nirWriteBack'}
  OUTPUT: boolean

  // 'nirWriteBack' was already fixed in nir_importer_tab.dart (lines 107-109).
  // _mirrorProjection and applyTemplateToWorkspace are still broken.
  RETURN path IN {'mirrorProjection', 'applyTemplateToWorkspace'}
END FUNCTION
```

**Examples:**

- User loads a `.nir` file → `canonicalDocProvider.updateFromNirFile` fires →
  `_mirrorProjection` sets the graph → validation panel stays at its previous state.
- User opens Template Gallery and picks any template → `applyTemplateToWorkspace`
  populates canvas → validation panel reflects the prior (possibly empty) state.

### Bug Condition (Bug 3) — NIR Viewer Panel Present

```
FUNCTION isBugConditionViewerPresent(widget)
  INPUT: widget — the _NirGraphEditorPanel Row's children list
  OUTPUT: boolean

  RETURN widget.children contains Expanded(flex: 2, child: _NirTreeView)
END FUNCTION
```

**Examples:**

- Any loaded state in the NIR tab: the right 40 % of the panel is occupied by the
  HDF5 recursive tree view. The node/edge editor is compressed to 60 %.

### Bug Condition (Bug 4) — Stale Validation After Manual Revert

Bug 4 is a consequence of Bug Condition (Bugs 1 & 2) / Missing Validation for
`_mirrorProjection`. When the user types back the original CNL text character by
character, the successful re-parse causes `canonicalDocProvider` to emit a new
document. `_mirrorProjection` picks this up and sets the canvas graph — but never
calls `validationProvider.validate`. The stale failed validation from the broken
intermediate state persists.

```
FUNCTION isBugConditionStaleness(event)
  INPUT: event — the triggering code path for a graph mutation
  OUTPUT: boolean

  IF event == 'mirrorProjection' AND NOT validationCalledAfter
    RETURN true
  RETURN false
END FUNCTION
```

**Examples:**

- User edits CNL weight from `1.0` to `abc` (invalid) → validation fails. User then
  types back `1.0` → `_mirrorProjection` fires → canvas graph is correct again →
  validation panel still shows the `abc` failure.
- User changes CNL to reference a non-existent population → validation error. User
  adds the population back by retyping → `_mirrorProjection` sets the correct graph →
  validation remains stale.


## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**

- `_doPush` (called by all user-initiated canvas mutations) MUST continue to call both
  `canonicalDocProvider.updateFromCanvas` and `validationProvider.validate` exactly as
  it does today.
- `StudioSyncNotifier.syncCnlToCanvas` MUST continue to call
  `validationProvider.validate` after a successful CNL parse, as it does today.
- `scheduleCnlToCanvasDebounced` MUST continue to debounce and route through
  `syncCnlToCanvas` — the debounce timer, `_syncingCnlToCanvas`, and
  `_syncingCanvasToCnl` guard flags MUST remain unchanged.
- Mouse-driven canvas edits (add/remove node, add/remove edge, update parameters)
  MUST continue to trigger `_pushToCanonical` and subsequently `validationProvider.validate`.
- The node/edge editor column in `_NirGraphEditorPanel` (the `Expanded(flex: 3)`
  child) MUST continue to show node cards, parameter fields, and the connections panel
  exactly as before.
- The `setGraph` method on `CanvasNotifier` MUST NOT call `_pushToCanonical` — it is
  intentionally a silent setter used by `syncCnlToCanvas` and NIR write-back.
- For inputs where all projection nodes are `nir.LIF`, the behaviour of
  `canvasGraphFromCanonical` MUST be identical to the current behaviour (same
  `componentId`, same `nirType`, same parameters, same position logic).
- `applyTemplateToWorkspace` MUST continue to update `workspaceProvider`,
  `specTextProvider`, `selectedHardwareConfigProvider`, and
  `canonicalDocProvider.updateFromCnl`, and run `pipelineProvider.runParseAndValidate`.

**Scope:**

All inputs that do NOT trigger a bug condition are completely unaffected. Specifically:
- CNL→Canvas debounced sync via `scheduleCnlToCanvasDebounced`
- Canvas→CNL sync via `syncCanvasToCnl`
- NIR write-back path in `nir_importer_tab.dart` (already calls `validate`)
- Pipeline-sourced NIR auto-populate
- Pure-LIF NIR graphs (no type mismatch)


## Hypothesized Root Cause

### Root Cause 1 — `_project_to_canvas` does not emit `nir_type`

`_project_to_canvas` in `canonical_editor_projection.py` iterates over
`ir.populations` to build node dicts but never reads the corresponding entry from
`nir_graph.nodes` to extract the NIR primitive class. The `NetworkIR.populations`
dict carries only the abstracted `Population` data model, not the raw NIR class name.
The `nir_graph` parameter is passed in but is only used for the fallback-edge loop
(when `ir.connections` is empty); it is never consulted for node type information.

Result: the `CanvasProjection` nodes arrive at the frontend with no `nir_type` field.
The Dart `CanvasNode` model in `canonical_editor_document.dart` also lacks a
`nir_type` field, so even if the backend added it, the frontend would silently discard
it during JSON deserialization.

### Root Cause 2 — `canvasGraphFromCanonical` hardcodes type strings

Even if `nir_type` were available in the projection, `canvasGraphFromCanonical`
ignores all node fields except `id`, `label`, `size`, `threshold`, `tau`, and
`position`. It unconditionally writes `componentId: 'lif_population'` and
`nirType: 'nir.LIF'` for every node. There is no lookup against `_nirNodeTypes` or
any other type registry.

### Root Cause 3 — `_mirrorProjection` never calls `validationProvider.validate`

`_mirrorProjection` calls `canvasGraphFromCanonical` then writes the result to
`state`. It does not call `validationProvider.validate`. The only path in
`CanvasNotifier` that triggers validation is `_doPush`, which is called exclusively
from user-initiated structural mutations (add/remove node, add/remove edge, update
parameters, load demo, load project). `_mirrorProjection` is a passive receiver of
incoming canonical doc changes and was intentionally kept free of upstream pushes to
prevent sync loops — but the absence of a downstream `validate` call was an oversight.

### Root Cause 4 — `applyTemplateToWorkspace` never calls `validationProvider.validate`

`applyTemplateToWorkspace` calls `canonicalDocProvider.updateFromCnl(template.spec)`,
which triggers `_mirrorProjection` asynchronously via the Riverpod listener. But
`applyTemplateToWorkspace` itself does not wait for the canvas to be populated and
does not call `validationProvider.validate`. The `pipelineProvider.runParseAndValidate`
call it already contains validates at the pipeline level (syntax/backend), not at the
canvas graph level.

### Root Cause 5 — Right-side HDF5 tree column never guarded by a feature flag

`_NirGraphEditorPanel` was built as a two-column layout with a tree view that has
since been deemed unnecessary. The `Expanded(flex: 2)` column containing `_NirTreeView`
was never removed.


## Correctness Properties

Property 1: Bug Condition — NIR Type Resolution in `canvasGraphFromCanonical`

_For any_ `CanvasProjection` where any node carries a non-null `nirType` field, the
fixed `canvasGraphFromCanonical` SHALL assign each resulting `CanvasNode` a
`nirType` equal to the projection node's `nirType`, and a `componentId` equal to
the `legacyComponentId` of the matching entry in `_nirNodeTypes` (falling back to the
`nirType` string itself when no registry entry exists). No node SHALL be assigned
`nirType: 'nir.LIF'` or `componentId: 'lif_population'` unless the projection node's
`nirType` is actually `'nir.LIF'`.

**Validates: Requirements 2.1, 2.4**

Property 2: Bug Condition — `nir_type` Emitted by Python Projection

_For any_ NIR graph passed to `_project_to_canvas` where `nir_graph` is non-null and
a node name exists in both `ir.populations` and `nir_graph.nodes`, the fixed
`_project_to_canvas` SHALL include a `nir_type` key in that node's dict whose value
is `f"nir.{type(nir_graph.nodes[name]).__name__}"`.

**Validates: Requirements 2.1, 2.4**

Property 3: Bug Condition — Edge Count Preservation Through `canvasGraphFromCanonical`

_For any_ `CanvasProjection` with N edges, the fixed `canvasGraphFromCanonical` SHALL
return a `CanvasGraph` whose `edges` list has exactly N entries, each with matching
`sourceNodeId`, `targetNodeId`, and `weight` values.

**Validates: Requirements 2.3**

Property 4: Bug Condition — Validation After `_mirrorProjection`

_For any_ `CanvasProjection` that causes `_mirrorProjection` to be invoked (i.e.
`canonicalDocProvider` emits a new document with a non-empty canvas), the fixed
`_mirrorProjection` SHALL call `validationProvider.validate` with the newly constructed
graph immediately after setting `state`, such that `validationProvider`'s state
transitions away from any prior stale value.

**Validates: Requirements 2.2, 2.5, 2.7, 2.8**

Property 5: Bug Condition — Validation After `applyTemplateToWorkspace`

_For any_ template application that successfully populates `canonicalDocProvider`
(i.e. `updateFromCnl` does not throw), the fixed `applyTemplateToWorkspace` SHALL
result in `validationProvider.validate` being called with the canvas graph that
reflects the template, so validation state is current by the time the function
completes.

**Validates: Requirements 2.2, 2.5**

Property 6: Bug Condition — NIR Viewer Column Absent

_For any_ rendered `_NirGraphEditorPanel`, the fixed widget SHALL contain exactly one
`Expanded` child (the node/edge editor), and SHALL NOT contain any `_NirTreeView`
widget instance.

**Validates: Requirements 2.6**

Property 7: Preservation — Pure-LIF Graphs Unchanged

_For any_ `CanvasProjection` where every node's `nirType` is `'nir.LIF'` (or `null`
before the backend fix is deployed), the fixed `canvasGraphFromCanonical` SHALL
produce a `CanvasGraph` identical to what the unfixed function produces — same
`componentId`, same `nirType`, same parameters, same position logic.

**Validates: Requirements 3.1, 3.5**

Property 8: Preservation — `_doPush` Validation Unchanged

_For any_ user-initiated canvas mutation that calls `_pushToCanonical`, the fixed
`CanvasNotifier` SHALL continue to invoke `validationProvider.validate` via `_doPush`
exactly as before — the fix MUST NOT remove or alter the `_doPush` → `validate` path.

**Validates: Requirements 3.2, 3.3**

Property 9: Preservation — Node/Edge Editor Column Intact

_For any_ rendered `_NirGraphEditorPanel` with a non-empty canvas graph, the fixed
widget SHALL continue to render `_NirNodeCard` widgets for every canvas node and the
`_NirEdgeList` widget, identical to the current behaviour.

**Validates: Requirements 3.1, 3.8**


## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct, five targeted changes are needed across
three files. All changes are additive (no existing behaviour is removed) except Bug 3.

---

**File 1: `neurocnl/neurosim/app/services/canonical_editor_projection.py`**

**Function:** `_project_to_canvas`

**Change 1 — Emit `nir_type` from the live NIR node object:**

In the `nodes` loop (lines 163–172), resolve the NIR primitive type from
`nir_graph.nodes` when `nir_graph` is available, and add it to the node dict:

```python
for name, pop in ir.populations.items():
    nir_type: str | None = None
    if nir_graph is not None and name in nir_graph.nodes:
        nir_node = nir_graph.nodes[name]
        nir_type = f"nir.{type(nir_node).__name__}"
    nodes.append({
        "id": name,
        "label": name,
        "type": pop.population_type or "excitatory",
        "size": pop.size or 1,
        "shape": list(pop.shape) if pop.shape else None,
        "threshold": pop.threshold,
        "tau": pop.membrane_time_constant,
        "nir_type": nir_type,     # NEW
    })
```

---

**File 2: `neurocnl/frontend/lib/models/canonical_editor_document.dart`**

**Class:** `CanvasNode`

**Change 2 — Add `nirType` field to the Dart canonical `CanvasNode` model:**

Add an optional `nirType` field and wire it into `fromJson` / `toJson`:

```dart
class CanvasNode {
  const CanvasNode({
    required this.id,
    required this.label,
    this.nirType,          // NEW
    this.type = 'excitatory',
    this.size = 1,
    this.shape,
    this.threshold,
    this.tau,
  });

  final String id;
  final String label;
  final String? nirType;  // NEW — e.g. 'nir.LIF', 'nir.Input', 'nir.CubaLIF'
  // ... existing fields unchanged
}
```

In `fromJson`:
```dart
nirType: json['nir_type'] as String?,   // NEW
```

In `toJson`:
```dart
if (nirType != null) 'nir_type': nirType,   // NEW
```

---

**File 3: `neurocnl/frontend/lib/utils/canvas_projection_utils.dart`**

**Function:** `canvasGraphFromCanonical`

**Change 3 — Resolve `componentId` and `nirType` from projection node:**

Replace the two hardcoded strings with a lookup against a passed-in type registry, or
use a local fallback map. To avoid a provider dependency in a pure utility function,
use a local `_nirTypeToComponentId` const map mirroring the registry's
`legacyComponentId` values:

```dart
const Map<String, String> _nirTypeToComponentId = {
  'nir.Input':   'input_node',
  'nir.Output':  'output_node',
  'nir.LIF':     'lif_population',
  'nir.CubaLIF': 'lif_population',
  'nir.IF':      'lif_population',
  'nir.LI':      'lif_population',
  'nir.Linear':  'nir.Linear',
  'nir.Affine':  'nir.Affine',
  'nir.Conv1d':  'nir.Conv1d',
  'nir.Conv2d':  'nir.Conv2d',
  'nir.Flatten': 'nir.Flatten',
  'nir.AvgPool2d': 'nir.AvgPool2d',
  'nir.SumPool2d': 'nir.SumPool2d',
  'nir.Delay':   'nir.Delay',
  'nir.Scale':   'nir.Scale',
};

// In the nodes loop:
final rawNirType = projection.nodes[index].nirType;    // from new Dart model field
final resolvedNirType = rawNirType ?? 'nir.LIF';       // fallback for pre-fix backend
final resolvedComponentId =
    _nirTypeToComponentId[resolvedNirType] ?? resolvedNirType;

CanvasNode(
  id: projection.nodes[index].id,
  componentId: resolvedComponentId,   // was 'lif_population'
  nirType: resolvedNirType,           // was 'nir.LIF'
  // ... rest unchanged
)
```


---

**File 4: `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`**

**Method:** `_mirrorProjection`

**Change 4 — Call `validationProvider.validate` after mirroring the graph:**

```dart
void _mirrorProjection(canonical_doc.CanvasProjection projection) {
  final newGraph = canvasGraphFromCanonical(
    projection,
    currentGraph: state.graph,
  );
  state = state.copyWith(graph: _normalizeGraph(newGraph));
  // NEW: keep validation in sync with the mirrored graph.
  // Fire-and-forget — same pattern used in _doPush.
  ref.read(validationProvider.notifier).validate(newGraph);
}
```

This is the single fix for both Bug 2 (template connection registration) and Bug 4
(validation staleness after manual revert), because both of those code paths converge
on `_mirrorProjection`.

---

**File 5: `neurocnl/frontend/lib/services/template_load_guard.dart`**

**Function:** `applyTemplateToWorkspace`

**Change 5 — Add imports and call `validationProvider.validate` after template load:**

```dart
import '../providers/canvas/canvas_provider.dart';
import '../providers/canvas/validation_provider.dart' as canvas_val;

Future<void> applyTemplateToWorkspace(
    WidgetRef ref, CnlTemplate template) async {
  ref.read(workspaceProvider.notifier).updateActiveFileContent(template.spec);
  ref.read(specTextProvider.notifier).set(template.spec);
  ref.read(selectedHardwareConfigProvider.notifier).state =
      template.hardwareConfig;
  await ref.read(canonicalDocProvider.notifier).updateFromCnl(template.spec);
  await ref.read(pipelineProvider.notifier).runParseAndValidate(
        template.spec,
        backend: template.validationBackend,
      );
  // NEW: validate the populated canvas graph so the validation panel
  // reflects the template state immediately.
  final graph = ref.read(canvasProvider).graph;
  if (graph.nodes.isNotEmpty) {
    unawaited(
      ref.read(canvas_val.validationProvider.notifier).validate(graph),
    );
  }
}
```

Note: `unawaited` is used (same pattern as the NIR write-back path) because
`applyTemplateToWorkspace` is called from UI event handlers and we do not want to
block the template load on the validation HTTP round-trip.

---

**File 6: `neurocnl/frontend/lib/widgets/nir_importer_tab.dart`**

**Widget:** `_NirGraphEditorPanel.build`

**Change 6 — Remove the right-side HDF5 tree view column:**

Replace the current `Row` with two `Expanded` children with a single child:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final graph = ref.watch(canvasProvider).graph;
  return graph.nodes.isEmpty
      ? const _EmptyGraphEditor()
      : ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          children: [
            for (final node in graph.nodes) _NirNodeCard(node: node),
            _NirEdgeList(graph: graph),
          ],
        );
}
```

The `Row`, `VerticalDivider`, and the `Expanded(flex: 2, child: _NirTreeView(...))`
block are removed entirely. The `_NirTreeView`, `_GroupTile`, `_DatasetTile`, and
`_Badge` private classes can be retained or deleted; they are no longer referenced.
Deleting them reduces code size but either choice is safe.


## Testing Strategy

### Validation Approach

The strategy follows the bug-condition methodology: first run exploratory tests against
the **unfixed** code to confirm the root cause, then apply the fix and run property and
preservation tests to verify correctness.

---

### Exploratory Bug Condition Checking

**Goal:** Surface counterexamples on unfixed code. Confirm or refute the root cause
hypotheses. If a test passes unexpectedly on unfixed code, the hypothesis is wrong.

**Test Plan:** Write targeted unit tests and a widget test that exercise each bug
condition directly. Run them against the current (unfixed) codebase.

**Test Cases:**

1. **Type Mismatch Test**: Call `canvasGraphFromCanonical` with a projection that has
   one `nir.Input` node. Assert the resulting `CanvasNode.nirType == 'nir.Input'`.
   **Expected to FAIL on unfixed code** — returns `'nir.LIF'` instead.

2. **Multi-Type Projection Test**: Call `canvasGraphFromCanonical` with a projection
   containing `nir.Input`, `nir.LIF`, and `nir.Output` nodes. Assert each node's
   `nirType` matches its projection type.
   **Expected to FAIL on unfixed code.**

3. **Template Validation Test**: Apply a template via `applyTemplateToWorkspace` in a
   widget test container. After the async call completes, assert that
   `validationProvider.state` is `AsyncData` (not `AsyncLoading` or a prior value).
   **Expected to FAIL on unfixed code** — validation is never triggered.

4. **_mirrorProjection Validation Test**: Directly call `_mirrorProjection` on a
   `CanvasNotifier` with a non-empty projection. Assert `validationProvider` state
   changes.
   **Expected to FAIL on unfixed code.**

5. **NIR Viewer Column Test**: Render `_LoadedView` with a populated
   `NirInspectResult`. Assert `find.byType(_NirTreeView)` returns zero matches.
   **Expected to FAIL on unfixed code** — tree view is present.

6. **Revert Staleness Test**: Simulate a broken CNL edit (populate
   `validationProvider` with an error state), then trigger `_mirrorProjection` with a
   valid graph. Assert validation state is no longer an error.
   **Expected to FAIL on unfixed code.**

**Expected Counterexamples:**
- `canvasGraphFromCanonical` returns `nirType == 'nir.LIF'` for non-LIF nodes.
- `validationProvider.state` remains `AsyncLoading` or a prior `AsyncError` after
  `_mirrorProjection` or `applyTemplateToWorkspace`.
- `_NirTreeView` widget is found in the rendered tree.

---

### Fix Checking

**Goal:** Verify that for all inputs where the bug condition holds, the fixed code
produces the expected behaviour.

**Pseudocode:**

```
FOR ALL projection WHERE any(node.nirType != 'nir.LIF') DO
  graph := canvasGraphFromCanonical_fixed(projection)
  FOR EACH node IN graph.nodes DO
    ASSERT node.nirType == projection.nodes[index].nirType
    ASSERT node.componentId == _nirTypeToComponentId[node.nirType]
  END FOR
END FOR

FOR ALL event IN {'mirrorProjection', 'applyTemplateToWorkspace'} DO
  trigger_fixed_path(event)
  ASSERT validationProvider.state transitioned from prior_state
END FOR
```

---

### Preservation Checking

**Goal:** Verify that for inputs outside each bug condition, the fixed code is
identical to the unfixed code.

**Pseudocode:**

```
FOR ALL projection WHERE all(node.nirType == 'nir.LIF' OR node.nirType IS NULL) DO
  graph_original := canvasGraphFromCanonical_original(projection)
  graph_fixed    := canvasGraphFromCanonical_fixed(projection)
  ASSERT graph_original.nodes == graph_fixed.nodes
  ASSERT graph_original.edges == graph_fixed.edges
END FOR

FOR ALL canvas_mutation IN {addNode, removeNode, addEdge, updateParameters} DO
  result_original := execute_original(mutation)
  result_fixed    := execute_fixed(mutation)
  ASSERT validationProvider called in both
  ASSERT _pushToCanonical called in both
END FOR
```

**Testing Approach:** Property-based testing is recommended for the type resolution
preservation check because the input space of projections is large and we need to
confirm that no regression occurs across all-LIF inputs after the fallback path is
introduced.

---

### Unit Tests

- `canvasGraphFromCanonical` correctly resolves `nirType` and `componentId` for all
  known NIR types in `_nirTypeToComponentId`.
- `canvasGraphFromCanonical` falls back to `'nir.LIF'` / `'lif_population'` when
  `projection.nodes[i].nirType` is null (backward compatibility with pre-fix backend).
- `canvasGraphFromCanonical` produces edge count equal to `projection.edges.length`.
- `_mirrorProjection` calls `validationProvider.validate` with the new graph.
- `applyTemplateToWorkspace` calls `validationProvider.validate` with the populated
  canvas graph when the graph is non-empty.
- `applyTemplateToWorkspace` does NOT call `validationProvider.validate` when the
  canvas graph is empty (guard).
- Python `_project_to_canvas` emits `nir_type` for every known NIR node class.
- Python `_project_to_canvas` emits `nir_type: None` when `nir_graph` is None.

---

### Property-Based Tests

- **P1 — Type resolution round-trip**: For any list of NIR type strings drawn from
  `_nirNodeTypes`, construct a `CanvasProjection` with those types and assert that
  `canvasGraphFromCanonical` returns nodes with exactly matching `nirType` values and
  correct `componentId` lookups.

- **P2 — Edge count preservation**: For any `CanvasProjection` with 0–N random edges,
  `canvasGraphFromCanonical` returns a `CanvasGraph` with exactly the same number of
  edges.

- **P3 — LIF-only graphs are unchanged**: For any `CanvasProjection` where every node
  has `nirType == 'nir.LIF'` (or null), the fixed function produces identical output
  to the unfixed function.

- **P4 — Validation always follows `_mirrorProjection`**: For any non-empty
  `CanvasProjection`, calling `_mirrorProjection` on a fresh `CanvasNotifier` always
  results in `validationProvider.validate` being invoked.

---

### Integration Tests

- Load a `.nir` file that contains `nir.Input`, `nir.LIF`, and `nir.Output` nodes;
  verify the canvas displays all three with correct type labels and that validation
  completes.
- Apply a template with a non-LIF population (e.g. CubaLIF); verify the canvas nodes
  have correct `nirType` and that validation fires immediately.
- Simulate the manual-revert flow: inject an error validation state, trigger
  `_mirrorProjection` with a valid graph, verify the validation panel clears to a
  passing state.
- Render the NIR tab with a loaded `.nir` file; verify the HDF5 tree view is absent
  and the editor occupies full width.
