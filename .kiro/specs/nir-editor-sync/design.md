# NIR Editor Sync Bugfix Design

## Overview

The `NirImporterTab` is currently a read-only HDF5 tree inspector. It can display a NIR graph
(from a `.nir` file, the Generate pipeline, or a canvas export) but provides no editable fields
and has no write-back path for user edits. The CNL editor and canvas editor are already
bidirectionally synced through `StudioSyncNotifier` and `cnlSpecProvider`; the NIR tab is a
passive bystander in that sync loop.

This fix transforms `NirImporterTab` into a full peer editor by:

1. Adding a parameter-editing panel (`_NirPropertyPanel`) wired to `canvasProvider`.
2. Adding structural edit controls (add/remove node, add/remove edge) through `canvasProvider`.
3. Extending `StudioSyncNotifier` with a third sync direction: NIR ↔ canvas (and, transitively, canvas ↔ CNL).
4. Adding a debounced canvas-change listener that keeps the NIR view live while in NIR mode.
5. Patching `applyTemplateToWorkspace` and the `onCanvasCnlSpec` guard so template loads and
   external canvas/CNL changes flow into the NIR tab.

The `_syncingCanvasToCnl` / `_syncingCnlToCanvas` guard pattern already in
`StudioSyncNotifier` is extended with a `_syncingNirToCanvas` flag to prevent re-entry loops.

---

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug — a canvas graph is loaded and the
  NIR tab is the active view, yet no editable parameter fields are shown and no user edit
  propagates to CNL or canvas.
- **Property (P)**: The desired behaviour — every parameter change committed in the NIR editor
  propagates to `canvasProvider` (and transitively to `cnlSpecProvider` and `specTextProvider`)
  within the same debounce window used by the existing Canvas ↔ CNL sync.
- **Preservation**: File import write-back, pipeline auto-populate, canvas ↔ CNL bidirectional
  sync, and tab-switch one-shot sync must all work exactly as they do today.
- **NirImporterTab**: `lib/widgets/nir_importer_tab.dart` — the widget being promoted from viewer
  to peer editor.
- **StudioSyncNotifier**: `lib/providers/studio_sync_notifier.dart` — owns all
  bidirectional sync logic and loop-prevention flags.
- **NirImportNotifier**: `lib/providers/nir_import_provider.dart` — owns the NIR state machine
  (`NirImportState`): `source`, `status`, `result`, write-back fields.
- **NirParameterDef**: `lib/models/nir_node_type.dart` — schema for a single editable parameter
  (`name`, `type ∈ {int, float, text, bool, enum}`, `defaultValue`, `min`, `max`, `unit`).
- **NirNodeType / nirNodeTypeMapProvider**: `lib/providers/canvas/nir_types_provider.dart` —
  registry mapping NIR type id (e.g. `nir.LIF`) to its `NirParameterDef` list.
- **canvasProvider**: `lib/providers/canvas/canvas_provider.dart` — Riverpod `StateNotifier`
  holding `CanvasState { graph, selectedNodeId, … }`. Mutations fire `_triggerGenerateCnl`,
  which updates `cnlSpecProvider`.
- **cnlSpecProvider**: `lib/providers/canvas/sync_provider.dart` — holds the last
  canvas-generated CNL string; listened by `StudioSyncNotifier.onCanvasCnlSpec`.
- **specTextProvider**: `lib/providers/spec_provider.dart` — holds the CNL editor text;
  listened by `StudioSyncNotifier.scheduleCnlToCanvasDebounced`.
- **applyTemplateToWorkspace**: `lib/services/template_load_guard.dart` — sets
  `specTextProvider`, `workspaceProvider`, `cnlSpecProvider`, then calls
  `cnlSpecProvider.notifier.syncToCanvas()`.
- **_syncingNirToCanvas** (new flag): boolean on `StudioSyncNotifier` that gates re-entry when a
  NIR edit is mid-flight to canvas.

---

## Bug Details

### Bug Condition

The bug manifests whenever a `CanvasGraph` with at least one node is loaded (from any source)
while `StudioViewMode.nir` is the active view and the user attempts to edit parameters. The
`NirImporterTab` has no editable fields, so the edit cannot be initiated. Additionally, even when
the canvas changes externally (template load, canvas editor edit), the NIR tab is not refreshed
in real time.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type NirEditorInteraction
  OUTPUT: boolean

  RETURN (
    (input.interactionType == PARAMETER_EDIT AND noEditableFieldsPresent(nirTab))
    OR (input.interactionType == STRUCTURAL_EDIT AND noStructuralControlsPresent(nirTab))
    OR (input.interactionType == EXTERNAL_CHANGE
        AND viewMode == NIR
        AND nirTabNotRefreshed(input.canvasGraph))
  )
END FUNCTION
```

### Examples

- **Edit LIF threshold**: User is in NIR mode, sees a LIF node, and wants to change `threshold`
  from 1.0 to 0.8. Current: no input field — cannot make the edit. Expected: a numeric `TextField`
  pre-populated with `1.0` allows the change and triggers canvas + CNL update.
- **Template load**: User clicks "Reflex Arc" in the Template Gallery while the NIR tab is open.
  Current: NIR tab shows stale/idle content. Expected: NIR tab immediately reflects the new
  template graph.
- **Canvas edit while NIR active**: User's colleague updates the canvas in a split pane while NIR
  is the active editor tab. Current: NIR tab is not refreshed. Expected: NIR tab live-updates
  within the debounce window.
- **Idle state**: No graph loaded, NIR tab shows the idle placeholder. Current ✓ (preserved).

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Pressing "Load .nir" parses the file, shows the HDF5 tree, and writes CNL + canvas graph back
  exactly as today (`inspectFile` → `_applyWriteBack`).
- Pipeline `nir_code` auto-populates the NIR tab when no file/canvas source is loaded
  (`syncFromPipelineNirCode` guard unchanged).
- Canvas → CNL sync via `cnlSpecProvider` continues to fire after every canvas mutation.
- CNL → Canvas debounced sync via `specTextProvider` listener continues unchanged.
- Tab-switch one-shot syncs (`syncCnlToCanvas`, `syncCanvasToCnl`, `syncFromCanvas`) continue
  unchanged.
- `applyTemplateToWorkspace` continues to update CNL editor and canvas when CNL or canvas tab is
  active.
- The idle placeholder is shown when no source is loaded.

**Scope:**
All interactions that do NOT involve the NIR editor committing a parameter or structural change
are completely unaffected. This includes mouse clicks on canvas nodes, CNL text typing, file
imports, and pipeline runs.

---

## Hypothesized Root Cause

Based on codebase analysis, there are four distinct root causes:

1. **Missing UI layer — no editable fields in NIR tab**:  
   `_LoadedView` renders `_NirTreeView` only. There is no property panel widget for NIR nodes.
   The canvas `PropertyPanel` (in `canvas/property_panel.dart`) already implements all field
   types needed (`_PropertyTextField`, `SwitchListTile`, `DropdownButtonFormField`), but is
   wired to `canvasProvider` and lives in the canvas subpackage. A NIR-specific variant is
   required that drives the same `canvasProvider.notifier.updateNodeParameters` call.

2. **Missing NIR→Canvas write-back path for live edits**:  
   `NirImportNotifier` handles file-import write-back via `markWriteBackConsumed` and
   `_applyWriteBack` in the widget. There is no equivalent for interactive edits. The fix is to
   call `canvasProvider.notifier.updateNodeParameters` (and `addNode`/`removeNode`/`addEdge`/
   `removeEdge`) directly from the NIR property panel, bypassing `NirImportNotifier` for live
   edits (just as `PropertyPanel` calls `canvasProvider` directly rather than going through an
   intermediate notifier).

3. **`onCanvasCnlSpec` guard blocks CNL update when NIR is active**:  
   `StudioSyncNotifier.onCanvasCnlSpec` has this guard:
   ```dart
   if (viewMode == StudioViewMode.cnl || viewMode == StudioViewMode.nir) return;
   ```
   This prevents `cnlSpecProvider` changes from propagating to `specTextProvider` while in NIR
   mode. The rationale was to avoid overwriting the CNL editor while the user owns it — but the
   same guard is applied to NIR mode, which is wrong. The NIR editor is not a CNL text owner;
   canvas mutations triggered by NIR edits SHOULD propagate to CNL. The guard must be narrowed
   to only block CNL mode, and a new `_syncingNirToCanvas` flag must prevent the canvas change
   from re-triggering a `syncFromCanvas` call.

4. **No live-update listener for NIR tab**:  
   `StudioSyncNotifier.onViewModeChanged` triggers a one-shot `syncFromCanvas` when switching
   to NIR. But there is no ongoing listener that refreshes the NIR tab when `canvasProvider`
   changes while NIR is already the active view. The `specTextProvider` and `cnlSpecProvider`
   listeners in `StudioScreen.build` do not have a NIR-refresh branch. The fix adds a debounced
   listener in `StudioSyncNotifier` (or in `StudioScreen.build`) that calls
   `nirImportProvider.notifier.syncFromCanvas` when canvas changes while NIR is active, guarded
   by `_syncingNirToCanvas` to avoid loops.

---

## Correctness Properties

Property 1: Bug Condition — NIR Parameter Edit Propagates to Canvas and CNL

_For any_ canvas node parameter edit committed via the NIR editor (isBugCondition returns true:
the NIR tab is active and an editable field commits a new value), the fixed system SHALL call
`canvasProvider.notifier.updateNodeParameters(nodeId, newParameters)`, which SHALL fire
`_triggerGenerateCnl` (debounced 300 ms), which SHALL update `cnlSpecProvider`, which SHALL
(via `onCanvasCnlSpec`) update `specTextProvider` and `workspaceProvider` with regenerated CNL
text that reflects the new parameter value.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation — Non-NIR-Edit Inputs Are Unaffected

_For any_ interaction where the bug condition does NOT hold (isBugCondition returns false —
i.e., the interaction is a file import, pipeline sync, CNL text edit, canvas drag, template
load while CNL/canvas is active, or tab switch), the fixed system SHALL produce exactly the
same observable state as the original system, including all write-back paths, sync flags, and
debounce timing.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

Property 3: Loop Prevention — NIR Edit Does Not Re-Trigger NIR Refresh

_For any_ parameter edit committed in the NIR editor, the resulting chain
(NIR edit → `updateNodeParameters` → `_triggerGenerateCnl` → `cnlSpecProvider` → `onCanvasCnlSpec`
→ `specTextProvider`) SHALL NOT cause `nirImportProvider.notifier.syncFromCanvas` to be called
a second time during the same edit, ensuring exactly one update per user action.

**Validates: Requirements 2.5**

---

## Fix Implementation

### Architecture: Extended Three-Way Sync

The fix introduces a third sync direction inside `StudioSyncNotifier`, bringing NIR into the
existing CNL ↔ Canvas sync topology:

```
         ┌─────────────────────────────────────────────────────────┐
         │                 StudioSyncNotifier                      │
         │                                                         │
         │  CNL editor ──(onChanged)──► scheduleCnlToCanvasDebounced
         │                                       │                 │
         │                                  syncCnlToCanvas        │
         │                                       │                 │
         │  canvasProvider ◄─────────────────────┘                 │
         │       │                                                  │
         │  _triggerGenerateCnl ──► cnlSpecProvider                 │
         │                                │                        │
         │                         onCanvasCnlSpec                 │
         │                                │                        │
         │  specTextProvider ◄────────────┘  (guard: NOT cnl mode) │
         │                                                         │
         │  [NEW] canvasProvider ──► scheduleNirFromCanvasDebounced │
         │                                │   (guard: NIR mode     │
         │                                │    AND NOT _syncingNir) │
         │  nirImportProvider ◄───────────┘                        │
         │       │                                                  │
         │  NirImporterTab._NirPropertyPanel                        │
         │       │ (user edits)                                     │
         │  canvasProvider.updateNodeParameters ───────────────────►│
         │  (sets _syncingNirToCanvas = true for duration)         │
         └─────────────────────────────────────────────────────────┘
```

### Changes Required

#### File 1: `lib/providers/studio_sync_notifier.dart`

**Change 1 — Add `_syncingNirToCanvas` flag:**
```dart
bool _syncingNirToCanvas = false;
```

**Change 2 — Fix `onCanvasCnlSpec` guard:**

Current:
```dart
if (viewMode == StudioViewMode.cnl || viewMode == StudioViewMode.nir) return;
```
Changed to:
```dart
if (viewMode == StudioViewMode.cnl) return;
```
This allows canvas-generated CNL to propagate to `specTextProvider` when NIR is the active
view (which is correct — NIR edits flow through canvas, and the resulting CNL should be stored).

**Change 3 — Add `scheduleNirFromCanvasDebounced`:**

New method called from the `canvasProvider` listener in `StudioScreen.build` when NIR is the
active view:
```dart
void scheduleNirFromCanvasDebounced(CanvasGraph graph) {
  if (_syncingNirToCanvas) return;  // this change originated from NIR — skip re-sync
  final viewMode = _ref.read(studioViewModeProvider).viewMode;
  if (viewMode != StudioViewMode.nir) return;
  _nirDebounce?.cancel();
  _nirDebounce = Timer(const Duration(milliseconds: 400), () {
    if (!mounted) return;
    if (_syncingNirToCanvas) return;
    _ref.read(nirImportProvider.notifier).syncFromCanvas(graph);
  });
}
Timer? _nirDebounce;
```

**Change 4 — New `syncNirToCanvas` method (wraps a NIR-sourced canvas edit):**

This is not a full round-trip API call — it is a flag-setting wrapper that marks a NIR edit as
in-flight so that the canvas-change listener does not re-trigger `syncFromCanvas`:
```dart
void beginNirEdit() {
  _syncingNirToCanvas = true;
}

void endNirEdit() {
  _syncingNirToCanvas = false;
}
```
These are called synchronously around `canvasProvider.notifier.updateNodeParameters` calls from
the NIR property panel (see widget changes below).

**Change 5 — Update `dispose`:**
```dart
_nirDebounce?.cancel();
```

#### File 2: `lib/widgets/nir_importer_tab.dart`

**Change 1 — Rename header title from `'NIR Inspector'` to `'NIR Editor'`.**

**Change 2 — Replace `_LoadedView` with a two-panel layout:**
- Left/top: collapsed HDF5 tree (retained for file-source context; hidden for canvas/pipeline
  sources since the tree is less useful than the parameter view).
- Right/main: `_NirGraphEditorPanel` — a scrollable list of all canvas nodes, each expanded
  into a `_NirNodeCard`.

**Change 3 — Add `_NirGraphEditorPanel` widget:**

```dart
class _NirGraphEditorPanel extends ConsumerWidget {
  // Reads canvasProvider.graph.nodes and nirNodeTypeMapProvider.
  // For each CanvasNode, renders a _NirNodeCard.
  // "Add Node" button at bottom calls canvasProvider.notifier.addNode(...)
  //   with a default NirNodeType selected by a dropdown.
}
```

**Change 4 — Add `_NirNodeCard` widget:**

```dart
class _NirNodeCard extends ConsumerWidget {
  // Expanded ExpansionTile per node.
  // Header: node label, nirType badge, delete button.
  // Body: for each NirParameterDef in nodeType.parameters,
  //   renders the same field types as PropertyPanel._buildParameterField.
  // On field commit, calls:
  //   ref.read(studioSyncNotifierProvider.notifier).beginNirEdit();
  //   ref.read(canvasProvider.notifier).updateNodeParameters(node.id, next);
  //   ref.read(studioSyncNotifierProvider.notifier).endNirEdit();
  // Delete button:
  //   same beginNirEdit/endNirEdit pattern around canvasProvider.notifier.removeNode.
}
```

**Change 5 — Add `_NirEdgeList` widget:**

```dart
class _NirEdgeList extends ConsumerWidget {
  // Compact list of edges (source → target, weight, delay).
  // Each row has an "Add" icon and a delete button.
  // Structural changes use beginNirEdit/endNirEdit pattern.
}
```

**Change 6 — Preserve idle / loading / error states unchanged.**

**Change 7 — Live-update: add `ref.listen<CanvasState>` in `_NirImporterTabState.build`:**

This listener is the companion to the `scheduleNirFromCanvasDebounced` in `StudioSyncNotifier`.
Since `NirImporterTab` is kept alive inside `IndexedStack`, it always has an active subscription:
```dart
ref.listen<CanvasState>(canvasProvider, (prev, next) {
  final viewMode = ref.read(studioViewModeProvider).viewMode;
  if (viewMode != StudioViewMode.nir) return;
  ref.read(studioSyncNotifierProvider.notifier)
      .scheduleNirFromCanvasDebounced(next.graph);
});
```
This replaces the need to add a separate listener in `StudioScreen.build`.

#### File 3: `lib/screens/studio_screen.dart`

No new listeners are required (the NirImporterTab widget itself handles its own live-update
listener — see File 2, Change 7). The only change is removing the workaround comment
mentioning NIR's one-directional sync limitation once the fix is complete.

#### File 4: `lib/services/template_load_guard.dart`

**Change — Trigger NIR refresh after template load if NIR is active:**

```dart
Future<void> applyTemplateToWorkspace(WidgetRef ref, CnlTemplate template) async {
  ref.read(workspaceProvider.notifier).updateActiveFileContent(template.spec);
  ref.read(specTextProvider.notifier).set(template.spec);
  ref.read(cnlSpecProvider.notifier).setCnl(template.spec);
  ref.read(selectedHardwareConfigProvider.notifier).state = template.hardwareConfig;
  await Future.wait([
    ref.read(pipelineProvider.notifier).runParseAndValidate(
          template.spec,
          backend: template.validationBackend,
        ),
    ref.read(cnlSpecProvider.notifier).syncToCanvas(),
  ]);

  // [NEW] If NIR tab is active, refresh NIR display from the just-loaded canvas.
  final viewMode = ref.read(studioViewModeProvider).viewMode;
  if (viewMode == StudioViewMode.nir) {
    final canvasGraph = ref.read(canvasProvider).graph;
    if (canvasGraph.nodes.isNotEmpty) {
      ref.read(nirImportProvider.notifier).syncFromCanvas(canvasGraph);
    }
  }
}
```

### Data Flow Diagrams

#### NIR Parameter Edit → Canvas + CNL

```
User types in _NirNodeCard field
        │
        ▼
studioSyncNotifier.beginNirEdit()   (_syncingNirToCanvas = true)
        │
        ▼
canvasProvider.notifier.updateNodeParameters(nodeId, params)
        │
        ▼
_triggerGenerateCnl(debounce: true)  [300 ms]
        │
        ▼
cnlSpecProvider.generateFromGraph(graph)   [API call]
        │
        ▼
cnlSpecProvider state updated (new CNL string)
        │
        ▼
StudioScreen ref.listen<String>(cnlSpecProvider) fires
        │
        ▼
studioSyncNotifier.onCanvasCnlSpec(prev, next)
  guard: viewMode != cnl  ✓ (NIR mode passes)
  guard: !_syncingCnlToCanvas  ✓
        │
        ▼
specTextProvider.set(next)
workspaceProvider.updateActiveFileContent(next)
pipelineProvider.runParseAndValidate(next)
        │
        ▼
studioSyncNotifier.endNirEdit()    (_syncingNirToCanvas = false)

[Concurrently, NirImporterTab ref.listen fires:]
scheduleNirFromCanvasDebounced(graph)
  guard: _syncingNirToCanvas = true  ✗ → returns immediately  ✓ (loop prevented)
```

#### External Canvas/CNL Change → NIR Live-Update

```
canvasProvider updated (e.g. canvas editor, template load)
        │
        ▼
NirImporterTab ref.listen<CanvasState> fires
        │
        ▼
viewMode == nir?  YES
        │
        ▼
scheduleNirFromCanvasDebounced(graph)   [400 ms debounce]
  guard: _syncingNirToCanvas?  NO (external change)
        │
        ▼
nirImportProvider.notifier.syncFromCanvas(graph)
        │
        ▼
NirImporterTab rebuilds with fresh _NirGraphEditorPanel
```

#### Template Load While NIR Active

```
applyTemplateToWorkspace called
        │
        ├── specTextProvider.set(template.spec)
        ├── cnlSpecProvider.setCnl(template.spec)
        ├── cnlSpecProvider.notifier.syncToCanvas()   → canvasProvider updated
        │
        └── [NEW] viewMode == nir?  YES
                │
                ▼
            nirImportProvider.notifier.syncFromCanvas(canvasGraph)
                │
                ▼
            NirImporterTab shows new template's NIR graph
```

---

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, write exploratory tests against the
unfixed code to confirm the bug condition and understand failure modes; then write fix-checking
and preservation tests to validate the corrected implementation.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bugs BEFORE implementing the fix.
Confirm the root cause analysis.

**Test Plan**: Write widget tests that mount `NirImporterTab` with a non-empty canvas graph and
assert that editable fields are present. Also write unit tests on `StudioSyncNotifier` that
assert `specTextProvider` is not updated after a simulated NIR parameter edit.

**Test Cases**:
1. **No editable fields**: Mount `NirImporterTab` with a loaded LIF node. Assert that no
   `TextField` widgets are present in the tree. (Will FAIL on unfixed code ← confirms defect 1.1)
2. **NIR→CNL blocked by guard**: Simulate the `onCanvasCnlSpec` call with
   `viewMode == StudioViewMode.nir`. Assert that `specTextProvider` is NOT updated.
   (Will PASS on unfixed code ← confirms defect root cause 3)
3. **No live update in NIR mode**: Change `canvasProvider` while NIR is active. Assert
   `nirImportProvider.status` remains unchanged. (Will PASS on unfixed code ← confirms defect 1.7)
4. **Template not reflected in NIR**: Call `applyTemplateToWorkspace` while NIR is active.
   Assert `nirImportProvider.result` is not refreshed. (Will PASS on unfixed code ← confirms defect 1.6)

**Expected Counterexamples**:
- No `TextField` widgets found in the NIR tab tree when a graph is loaded.
- `specTextProvider` value is unchanged after simulating a NIR parameter edit followed by
  `_triggerGenerateCnl` with the `nir` view-mode guard active.

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed system produces
the expected behavior.

**Pseudocode:**
```
FOR ALL nodeId, paramName, newValue WHERE isBugCondition(nirEdit(nodeId, paramName, newValue)) DO
  result := nirEditor_fixed.commitParameterEdit(nodeId, paramName, newValue)
  ASSERT canvasProvider.graph.nodes[nodeId].parameters[paramName] == newValue
  ASSERT specTextProvider contains cnlTextReflecting(newValue)   -- within 300ms debounce
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed system
produces the same result as the original system.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT original_system_behavior(input) == fixed_system_behavior(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many random CNL strings and canvas graphs automatically.
- It catches edge cases where the new `_syncingNirToCanvas` flag might accidentally block
  a legitimate canvas→CNL sync.
- It provides strong guarantees that the existing sync flags and debounce timers are not perturbed.

**Test Plan**: Observe behavior of file import, pipeline auto-populate, and CNL↔Canvas sync on
unfixed code first, then write PBT/unit tests that assert identical behavior on fixed code.

**Preservation Test Cases:**
1. **File import write-back preserved**: Load a `.nir` file; assert CNL and canvas graph are
   updated as before (write-back path unchanged).
2. **Pipeline auto-populate preserved**: Set `pipelineProvider.nir_code`; assert NIR tab updates
   only when source is `none` or `pipeline`.
3. **Canvas→CNL guard preserved in CNL mode**: Simulate canvas mutation while `viewMode == cnl`;
   assert `specTextProvider` is NOT updated (user owns CNL editor).
4. **CNL→Canvas debounced sync preserved**: Update `specTextProvider`; assert canvas is updated
   after 400 ms debounce.
5. **Tab-switch one-shot syncs preserved**: Switch from CNL to canvas; assert `syncCnlToCanvas`
   is called. Switch from canvas to NIR; assert `syncFromCanvas` is called.
6. **Template load in CNL/canvas mode unchanged**: Call `applyTemplateToWorkspace` while CNL or
   canvas is active; assert existing behavior is identical.

### Unit Tests

- Test `StudioSyncNotifier.onCanvasCnlSpec` with `viewMode == nir`: verify `specTextProvider`
  IS updated (guard removed for NIR mode).
- Test `StudioSyncNotifier.scheduleNirFromCanvasDebounced` with `_syncingNirToCanvas = true`:
  verify `syncFromCanvas` is NOT called (loop prevention).
- Test `StudioSyncNotifier.scheduleNirFromCanvasDebounced` with NIR active and no flag:
  verify `syncFromCanvas` IS called after debounce.
- Test `_NirNodeCard` field commit calls `beginNirEdit`/`endNirEdit` around `updateNodeParameters`.
- Test `applyTemplateToWorkspace` with NIR active: verify `syncFromCanvas` is called on the
  updated graph.
- Test `NirImportNotifier.syncFromCanvas` is NOT called when `source == NirSource.file`
  (file priority guard unchanged).

### Property-Based Tests

- **Property 1 (Bug Condition)**: For any `CanvasNode` with a non-empty `NirParameterDef` list,
  pick a random parameter and random valid value. After committing via the NIR editor:
  - `canvasProvider.graph.nodes[id].parameters[param] == newValue` holds.
  - `specTextProvider` value is non-empty and different from its pre-edit state.
- **Property 2 (Preservation)**: For any CNL string that round-trips through
  `cnlSpecProvider.syncToCanvas()`, the resulting `canvasProvider.graph` produces the same CNL
  when `generateFromGraph` is called, regardless of whether NIR mode was active during the
  round-trip.
- **Property 3 (Loop Prevention)**: For any sequence of N NIR parameter edits on the same node,
  `syncFromCanvas` is called at most N times (once per edit, not twice due to loop).

### Integration Tests

- Full three-way sync: Start with a template in CNL mode, switch to NIR, edit a LIF threshold,
  switch to canvas — verify canvas node shows updated threshold and CNL text is updated.
- Template Gallery load while NIR active: Load a template from the gallery while NIR tab is
  the active view; verify the NIR editor immediately shows the new graph's nodes and parameters.
- Switching editors mid-edit: Begin editing a parameter in NIR, switch to canvas before
  committing; verify no partial state corruption.
- Structural edit round-trip: Add a node in NIR, verify it appears in canvas and CNL; remove
  the node in NIR, verify it is gone from canvas and CNL.
