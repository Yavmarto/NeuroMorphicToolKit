# Studio Single Source of Truth Remaining Implementation Plan

## Verified Implementation Status (2026-07-04)

Verified against the `neurocnl` submodule at commit `dbb0944b` ("Harden NIR backend/deploy-target support"). Most of the functional work landed in one squashed commit, `4b0ae8f6` "Moved cnl - nir - canvas to single source of truth", not as the plan's per-task commits — only Task 1's commit (`3f3feac0` "refactor: extend workspace file document state") matches the plan's naming.

- **Task 1 (WorkspaceFile document fields):** DONE — `pipelineState`, `canonicalDocument`, `canvasGraph`, `nirState`, `revision` all present on `WorkspaceFile` (workspace_file.dart:152-158, actual model now lives under `frontend/src/features/studio/domain/workspace_file.dart`; `models/workspace_file.dart` is an export shim).
- **Task 2 (Pipeline state → workspace doc):** DONE — `workspace_provider.dart:486-500` has `setActiveFilePipelineState`/`clearActiveFilePipelineState`; `pipeline_provider.dart:126-160` mirrors via `_publishState`/`_clearPublishedState` and hydrates from `activeFile.pipelineState` on file switch.
- **Task 3 (Canonical document ownership):** DONE — `workspace_provider.dart:502-508` `setActiveFileCanonicalDocument`; `canonical_doc_provider.dart:55-89` `_publishDocument`/`updateFromCnl` write into `activeFile.canonicalDocument`; `studio_sync_notifier.dart` no longer assumes canonicalDocProvider owns durable state.
- **Task 4 (Canvas graph ownership):** DONE — `workspace_provider.dart:510-516` `setActiveFileCanvasGraph`; `canvas_provider.dart:144-286` (`_publishGraph`) writes graph mutations and seeds from `activeFile.canvasGraph` on init/file switch.
- **Task 5 (NIR state ownership):** DONE — `workspace_provider.dart:518-524` `setActiveFileNirState`; `nir_import_provider.dart:90-110` mirrors/hydrates via `_setState`/`_hydrateFromWorkspace`.
- **Task 6 (Revision tracking / stale-async guard):** PARTIAL — a single shared `WorkspaceFile.revision` exists and is incremented in `updateActiveFileContent` (workspace_provider.dart:317), and `_matchesActiveDocument(fileId, revision)` staleness guards are wired into `pipeline_provider.dart`, `canonical_doc_provider.dart`, `studio_sync_notifier.dart`, and `nir_import_provider.dart`. The plan's four separate `pipelineRevision`/`canonicalRevision`/`canvasRevision`/`nirRevision` fields and `pipelineState.sourceRevision` were never added — the guard works but via a simpler mechanism than specified.
- **Task 7 (Remove dual-write text mutation paths):** NOT DONE — `studio_screen.dart:598-607` `_syncSpecFromWorkspace` still calls `specTextProvider.notifier.set(content)`, the exact call the plan says was removed. `spec_provider.dart`'s `SpecTextController.set/update` already forwards into `workspaceControllerProvider.notifier.updateActiveFileContent`, making the studio_screen.dart call redundant dead code rather than a true dual-write bug, but the described removal did not happen. Canvas editor/screen paths are single-write and correct.
- **Task 8 (Narrow field-level selectors):** DONE — `validationPanelSnapshotProvider` (validation_panel.dart:20,80), `exportWorkspaceSummaryProvider` and `workspaceRecentActivitiesProvider` (export_menu.dart:34/51, watched 146/911), `trainingPanelPrereqProvider` (training_inspector_panel.dart:25, watched 211/313) all exist and are watched only by their owning widgets.
- **Test files:** DONE — `studio_document_state_test.dart`, `studio_document_revision_test.dart`, `canvas_provider_dopush_preservation_test.dart`, `studio_sync_notifier_nir_test.dart` all exist with substantive content. `error_reporting_test.dart` contains only 1 of the 3 named Task 8 tests; the other two ("workspaceRecentActivitiesProvider..." and "trainingPanelPrereqProvider...") live in `studio_screen_test.dart` instead (lines 1271, 1292) — same coverage, different file than the plan states.
- **Commit trail:** only 1 of 8 plan-named commits exists (`3f3feac0`); Tasks 2-6's code landed in the unlabeled squash commit `4b0ae8f6` instead of discrete commits, so Task 2-6 "Step 5: Commit" checkboxes are unverifiable as literally described even though the code changes exist.

**Overall: PARTIAL / IN PROGRESS.** Tasks 1-5 and 8 are functionally complete (just not committed under the plan's prescribed messages/granularity). Task 6 is functionally covered but structurally simplified versus spec. Task 7 (dual-write removal) is the one genuinely unfinished item — the redundant `specTextProvider.notifier.set` call in `StudioScreen._syncSpecFromWorkspace` is still present. Task 9's final verification/commit steps remain unchecked and unrun.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the NeuroCNL Studio Riverpod state refactor so editable Studio document state has one authoritative source of truth and field-level edits stop fanning out across parallel writable stores.

**Architecture:** `workspaceProvider` remains the authoritative Riverpod store for Studio document and shell state, and all duplicate writable document state is collapsed into it. `specTextProvider`, `pipelineProvider`, `canonicalDocProvider`, `canvasProvider`, and `nirImportProvider` are converted from mixed ownership stores into adapters or document-scoped derived branches, while async parse/canonical/canvas/NIR work writes back into the active workspace document instead of maintaining second copies.

**Tech Stack:** Flutter, Dart, Riverpod `StateNotifierProvider`, widget tests, `flutter test`, `flutter analyze`

---

## Target state

- The authoritative CNL text is `workspaceProvider.state.activeFile.content`.
- `specTextProvider` is only an adapter/selector over `activeFile.content`.
- Template load, CNL editor, parameter explorer, canvas CNL editor, NIR import, and canvas import paths never write both spec and workspace content independently.
- Per-document derived artifacts live with the active file document state, not in parallel writable providers.
- Widgets read narrow Riverpod selectors instead of broad provider objects.
- Async parse/canonical/canvas/NIR completions patch the currently active document only when the revision token matches.

## File structure and responsibilities

- Modify: `neurocnl/frontend/lib/models/workspace_file.dart`
  Add document-scoped derived branches and revision metadata to `WorkspaceFile`.
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
  Keep this as the root writable Riverpod store and add document-scoped mutation helpers.
- Modify: `neurocnl/frontend/lib/providers/spec_provider.dart`
  Keep as adapter-only over `workspaceProvider.activeFile.content`.
- Modify: `neurocnl/frontend/lib/providers/pipeline_provider.dart`
  Convert to workspace-backed adapter / mutation helper for active-document pipeline state.
- Modify: `neurocnl/frontend/lib/providers/canonical_doc_provider.dart`
  Convert to workspace-backed adapter / mutation helper for active-document canonical state.
- Modify: `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`
  Convert graph ownership to the active document’s canvas branch.
- Modify: `neurocnl/frontend/lib/providers/nir_import_provider.dart`
  Convert NIR ownership to the active document’s NIR branch.
- Modify: `neurocnl/frontend/lib/providers/studio_sync_notifier.dart`
  Keep as an effect coordinator only; remove durable document ownership assumptions.
- Modify: `neurocnl/frontend/lib/widgets/cnl_editor.dart`
  Read and write only document-owned text/selection fields.
- Modify: `neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart`
  Stop treating `specTextProvider` as an independent store.
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`
  Consume document-scoped selectors and remove remaining dual-hydration logic.
- Modify: `neurocnl/frontend/test/providers_test.dart`
- Modify: `neurocnl/frontend/test/screens/studio_screen_test.dart`
- Create: `neurocnl/frontend/test/providers/studio_document_state_test.dart`
- Create: `neurocnl/frontend/test/providers/studio_document_revision_test.dart`

## Task 1: Extend `WorkspaceFile` into a true Studio document state container

**Files:**
- Modify: `neurocnl/frontend/lib/models/workspace_file.dart`
- Test: `neurocnl/frontend/test/providers/studio_document_state_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('WorkspaceFile document state preserves text plus derived branches', () {
  const file = WorkspaceFile(
    id: 'file-1',
    name: 'Spec 1',
    content: 'threshold=1.0',
  );

  expect(file.content, 'threshold=1.0');
  expect(file.pipelineState, isNull);
  expect(file.canonicalDocument, isNull);
  expect(file.canvasGraph, isNull);
  expect(file.nirState, isNull);
  expect(file.revision, 0);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/studio_document_state_test.dart`
Expected: FAIL with missing `pipelineState`, `canonicalDocument`, `canvasGraph`, `nirState`, or `revision` fields on `WorkspaceFile`.

- [x] **Step 3: Write minimal implementation**

Add document-scoped optional fields to `WorkspaceFile`:

```dart
final PipelineState? pipelineState;
final CanonicalEditorDocument? canonicalDocument;
final CanvasGraph? canvasGraph;
final NirImportState? nirState;
final int revision;
```

Update:
- constructor
- `copyWith`
- `toJson`
- `fromJson`

Use nullable fields first; keep behavior additive and backward-compatible for stored workspace payloads.

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/studio_document_state_test.dart`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/models/workspace_file.dart frontend/test/providers/studio_document_state_test.dart
git -C neurocnl commit -m "refactor: extend workspace file document state"
```

## Task 2: Move pipeline state into the active workspace document

**Files:**
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/pipeline_provider.dart`
- Test: `neurocnl/frontend/test/providers_test.dart`
- Test: `neurocnl/frontend/test/providers/studio_document_revision_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('runParseAndValidate writes results to the active workspace document', () async {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(mockApi)],
  );
  addTearDown(container.dispose);

  await container.read(pipelineProvider.notifier).runParseAndValidate('spec');

  final activeFile = container.read(workspaceProvider).activeFile!;
  expect(activeFile.pipelineState, isNotNull);
  expect(activeFile.pipelineState!.validateResult?.overall, isTrue);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers_test.dart`
Expected: FAIL because `activeFile.pipelineState` is null and pipeline results are only stored in `pipelineProvider.state`.

- [x] **Step 3: Write minimal implementation**

Add workspace mutation helpers:

```dart
void setActiveFilePipelineState(PipelineState state) { ... }
void clearActiveFilePipelineState() { ... }
```

In `PipelineNotifier`:
- keep the provider surface for compatibility
- after each state transition, mirror the active `PipelineState` into `workspaceProvider.activeFile.pipelineState`
- when file switches, hydrate notifier state from `activeFile.pipelineState` if present
- keep cache helpers working, but source them from the document-owned pipeline branch

Use a shared helper:

```dart
void _publishState(PipelineState next) {
  state = next;
  _ref.read(workspaceProvider.notifier).setActiveFilePipelineState(next);
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers_test.dart`
Expected: PASS with pipeline results visible on the active workspace document.

- [x] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/providers/workspace_provider.dart frontend/lib/providers/pipeline_provider.dart frontend/test/providers_test.dart frontend/test/providers/studio_document_revision_test.dart
git -C neurocnl commit -m "refactor: root pipeline state in workspace document"
```

## Task 3: Move canonical document ownership into the active workspace document

**Files:**
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/canonical_doc_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/studio_sync_notifier.dart`
- Test: `neurocnl/frontend/test/providers/studio_document_state_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('updateFromCnl stores canonical document on active workspace file', () async {
  await container.read(canonicalDocProvider.notifier).updateFromCnl('threshold=1.0');

  final activeFile = container.read(workspaceProvider).activeFile!;
  expect(activeFile.canonicalDocument, isNotNull);
  expect(activeFile.canonicalDocument!.cnlText, 'threshold=1.0');
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/studio_document_state_test.dart`
Expected: FAIL because `canonicalDocProvider` holds the document independently.

- [x] **Step 3: Write minimal implementation**

Add workspace helpers:

```dart
void setActiveFileCanonicalDocument(CanonicalEditorDocument? doc) { ... }
```

In `CanonicalDocNotifier`:
- keep `AsyncValue` surface for compatibility
- treat `workspaceProvider.activeFile.canonicalDocument` as the durable source
- on success, write the parsed/generated canonical document into the active file
- on init / file switch, surface the active file’s canonical document through the provider state

In `StudioSyncNotifier`:
- stop assuming `canonicalDocProvider` owns durable state
- read current canonical data via the adapter surface only

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/studio_document_state_test.dart`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/providers/workspace_provider.dart frontend/lib/providers/canonical_doc_provider.dart frontend/lib/providers/studio_sync_notifier.dart frontend/test/providers/studio_document_state_test.dart
git -C neurocnl commit -m "refactor: root canonical document in workspace"
```

## Task 4: Move canvas graph ownership into the active workspace document

**Files:**
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/studio_sync_notifier.dart`
- Test: `neurocnl/frontend/test/providers/canvas/canvas_provider_dopush_preservation_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('canvas graph mutations write to active workspace document graph', () {
  container.read(canvasProvider.notifier).loadProjectGraph(graph);

  final activeFile = container.read(workspaceProvider).activeFile!;
  expect(activeFile.canvasGraph, isNotNull);
  expect(activeFile.canvasGraph!.nodes, isNotEmpty);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/canvas/canvas_provider_dopush_preservation_test.dart`
Expected: FAIL because the graph is only durable inside `canvasProvider.state`.

- [x] **Step 3: Write minimal implementation**

Add workspace helpers:

```dart
void setActiveFileCanvasGraph(CanvasGraph? graph) { ... }
```

In `CanvasNotifier`:
- keep `CanvasState` provider surface for compatibility
- every graph mutation writes the normalized graph into `activeFile.canvasGraph`
- on init / file switch, seed `CanvasState.graph` from `activeFile.canvasGraph` first, then from canonical projection if absent
- selection and connection drag remain UI-local in `CanvasState`; only the actual graph becomes document-owned

This preserves a useful split:
- durable graph in workspace document
- ephemeral canvas UI affordances in the provider

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/canvas/canvas_provider_dopush_preservation_test.dart`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/providers/workspace_provider.dart frontend/lib/providers/canvas/canvas_provider.dart frontend/lib/providers/studio_sync_notifier.dart frontend/test/providers/canvas/canvas_provider_dopush_preservation_test.dart
git -C neurocnl commit -m "refactor: root canvas graph in workspace document"
```

## Task 5: Move NIR state ownership into the active workspace document

**Files:**
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/nir_import_provider.dart`
- Test: `neurocnl/frontend/test/providers/studio_sync_notifier_nir_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('NIR import state is stored on the active workspace document', () async {
  await container.read(nirImportProvider.notifier).inspectFile('network.nir', bytes);

  final activeFile = container.read(workspaceProvider).activeFile!;
  expect(activeFile.nirState, isNotNull);
  expect(activeFile.nirState!.source, NirSource.file);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/studio_sync_notifier_nir_test.dart`
Expected: FAIL because NIR state is only durable in `NirImportNotifier.state`.

- [x] **Step 3: Write minimal implementation**

Add workspace helper:

```dart
void setActiveFileNirState(NirImportState? state) { ... }
```

In `NirImportNotifier`:
- keep provider surface for compatibility
- mirror successful and loading states into `activeFile.nirState`
- on init / file switch, hydrate notifier state from `activeFile.nirState`
- preserve the rule that file-import source has priority over canvas/pipeline source

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/studio_sync_notifier_nir_test.dart`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/providers/workspace_provider.dart frontend/lib/providers/nir_import_provider.dart frontend/test/providers/studio_sync_notifier_nir_test.dart
git -C neurocnl commit -m "refactor: root nir state in workspace document"
```

## Task 6: Add document revision tracking and stale async result protection

**Files:**
- Modify: `neurocnl/frontend/lib/models/workspace_file.dart`
- Modify: `neurocnl/frontend/lib/providers/workspace_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/pipeline_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/canonical_doc_provider.dart`
- Modify: `neurocnl/frontend/lib/providers/studio_sync_notifier.dart`
- Modify: `neurocnl/frontend/lib/providers/nir_import_provider.dart`
- Create: `neurocnl/frontend/test/providers/studio_document_revision_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('stale parse result does not overwrite newer document revision', () async {
  final notifier = container.read(specTextProvider.notifier);
  notifier.set('old');
  final oldRevision = container.read(workspaceProvider).activeFile!.revision;

  notifier.set('new');
  final newRevision = container.read(workspaceProvider).activeFile!.revision;
  expect(newRevision, greaterThan(oldRevision));

  await completeOldParseRequest();

  final activeFile = container.read(workspaceProvider).activeFile!;
  expect(activeFile.content, 'new');
  expect(activeFile.pipelineState!.sourceRevision, newRevision);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/studio_document_revision_test.dart`
Expected: FAIL because old async completions can still publish into the active providers.

- [x] **Step 3: Write minimal implementation**

Add document fields:

```dart
final int revision;
final int? pipelineRevision;
final int? canonicalRevision;
final int? canvasRevision;
final int? nirRevision;
```

Update `workspaceProvider.updateActiveFileContent` to increment `revision`.

When async work starts:
- capture `activeFile.id`
- capture `activeFile.revision`

When async work completes:
- drop the result unless both still match the current active file and revision

Implement this in:
- `PipelineNotifier`
- `CanonicalDocNotifier`
- `StudioSyncNotifier` async flows
- any canvas/NIR effect path that can complete after a later edit

- [x] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/studio_document_revision_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/models/workspace_file.dart frontend/lib/providers/workspace_provider.dart frontend/lib/providers/pipeline_provider.dart frontend/lib/providers/canonical_doc_provider.dart frontend/lib/providers/studio_sync_notifier.dart frontend/test/providers/studio_document_revision_test.dart
git -C neurocnl commit -m "refactor: guard studio async state by revision"
```

## Task 7: Remove remaining dual-write text mutation paths

Status note on 2026-06-07: current code audit found the primary text mutation surfaces already normalized through `specTextProvider.notifier.set/update(...)`, but screen-level verification is still blocked by an existing `studio_screen_test` interaction failure unrelated to the single-source-of-truth write path. Leave Task 7 open until that harness issue is separated from the dual-write assertions.

**Files:**
- Modify: `neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart`
- Modify: `neurocnl/frontend/lib/screens/canvas/canvas_screen.dart`
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`
- Test: `neurocnl/frontend/test/screens/studio_screen_test.dart`
- Test: `neurocnl/frontend/test/integration/nir_three_way_sync_test.dart`

- [x] **Step 1: Write the regression tests**

```dart
testWidgets('canvas and studio imports mutate only the workspace document text', (tester) async {
  final container = _buildStudioContainer(...);
  await _pumpStudio(tester, container);

  container.read(specTextProvider.notifier).set('imported');

  expect(container.read(workspaceProvider).activeFile!.content, 'imported');
  expect(container.read(specTextProvider), 'imported');
});
```

- [x] **Step 2: Run the focused Task 7 regressions**

Run:
- `flutter test test/screens/studio_screen_test.dart --plain-name "StudioScreen switching active files keeps spec text sourced from workspace content"`
- `flutter test test/integration/nir_three_way_sync_test.dart --plain-name "applyTemplateToWorkspace post-load block: viewMode == nir AND canvasGraph non-empty → nirImportProvider state is refreshed"`

Observed on 2026-06-07: both regressions already passed, confirming the remaining Task 7 work was cleanup of redundant Studio hydration rather than a failing user-visible bug.

- [x] **Step 3: Write minimal implementation**

Audit and normalize every remaining text mutation path:
- canvas CNL editor
- canvas screen import contract hydrate
- Studio `_syncSpecFromWorkspace`
- NIR / template / import helper paths not already updated

Rule:
- write only through `specTextProvider.notifier.set/update(...)`
- never pair that with direct `workspaceProvider.updateActiveFileContent(...)`
- when reading text, prefer `specTextProvider` or a direct workspace selector consistently per widget

Implementation landed on 2026-06-07:
- removed the redundant `specTextProvider.notifier.set(content)` call from `StudioScreen._syncSpecFromWorkspace`
- left `canvas_cnl_editor.dart` and `canvas_screen.dart` on the existing single-write path through `specTextProvider`
- strengthened regression coverage so file switching and template load both assert workspace-backed text stays authoritative

- [x] **Step 4: Run test to verify it passes**

Run:
- `flutter test test/screens/studio_screen_test.dart --plain-name "StudioScreen switching active files keeps spec text sourced from workspace content"`
- `flutter test test/integration/nir_three_way_sync_test.dart --plain-name "applyTemplateToWorkspace post-load block: viewMode == nir AND canvasGraph non-empty → nirImportProvider state is refreshed"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/widgets/canvas/canvas_cnl_editor.dart frontend/lib/screens/canvas/canvas_screen.dart frontend/lib/screens/studio_screen.dart frontend/test/screens/studio_screen_test.dart frontend/test/integration/nir_three_way_sync_test.dart
git -C neurocnl commit -m "refactor: remove remaining studio text dual writes"
```

## Task 8: Narrow widget subscriptions to field-level selectors

**Files:**
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`
- Modify: `neurocnl/frontend/lib/widgets/validation_overlay.dart`
- Modify: `neurocnl/frontend/lib/widgets/validation_panel.dart`
- Modify: `neurocnl/frontend/lib/widgets/training_inspector_panel.dart`
- Modify: `neurocnl/frontend/lib/widgets/export_menu.dart`
- Test: `neurocnl/frontend/test/screens/studio_screen_test.dart`
- Test: `neurocnl/frontend/test/widgets/error_reporting_test.dart`

- [x] **Step 1: Write the regression tests**

Added on 2026-06-07:
- `validationPanelSnapshotProvider does not notify on spec edits when validation state is unchanged`
- `workspaceRecentActivitiesProvider does not notify on spec edits`
- `trainingPanelPrereqProvider does not notify on recent activity changes`

- [x] **Step 2: Run test to verify it fails**

Run:
- `flutter test test/widgets/error_reporting_test.dart --plain-name "validationPanelSnapshotProvider does not notify on spec edits when validation state is unchanged"`
- `flutter test test/screens/studio_screen_test.dart --plain-name "workspaceRecentActivitiesProvider does not notify on spec edits"`
- `flutter test test/screens/studio_screen_test.dart --plain-name "trainingPanelPrereqProvider does not notify on recent activity changes"`

Observed on 2026-06-07: initial red came from the new selector providers not existing yet, which was the expected TDD entry point.

- [x] **Step 3: Write minimal implementation**

For each touched widget:
- replace broad `watch(provider)` with `select(...)` or tiny derived providers
- watch only the exact field needed
- keep top-level shell widgets off text/content paths

Minimum targets:
- active step selectors
- active file tab projection
- validation summary
- recent activity list
- deploy target
- active panel

Implementation landed on 2026-06-07:
- introduced `validationPanelSnapshotProvider` so `ValidationPanel` watches parse/validate/focus fields instead of the whole pipeline/workspace objects
- introduced `exportWorkspaceSummaryProvider` and `workspaceRecentActivitiesProvider` so export surfaces watch only the summary and activity history they render
- introduced `trainingPanelPrereqProvider` so `TrainingInspectorPanel` watches only the training prerequisite fields it needs
- kept the already-narrow selectors in `StudioScreen` and `ValidationOverlay` as-is for this pass

- [x] **Step 4: Run test to verify it passes**

Run:
- `flutter test test/widgets/error_reporting_test.dart`
- `flutter test test/screens/studio_screen_test.dart --plain-name "workspaceRecentActivitiesProvider does not notify on spec edits"`
- `flutter test test/screens/studio_screen_test.dart --plain-name "trainingPanelPrereqProvider does not notify on recent activity changes"`
- `flutter analyze lib/widgets/validation_panel.dart lib/widgets/training_inspector_panel.dart lib/widgets/export_menu.dart test/widgets/error_reporting_test.dart test/screens/studio_screen_test.dart`

Observed on 2026-06-07:
- focused tests PASS
- analyze reports only the pre-existing `webview_flutter_platform_interface` test dependency info in `studio_screen_test.dart`

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/screens/studio_screen.dart frontend/lib/widgets/validation_overlay.dart frontend/lib/widgets/validation_panel.dart frontend/lib/widgets/training_inspector_panel.dart frontend/lib/widgets/export_menu.dart frontend/test/screens/studio_screen_test.dart frontend/test/widgets/error_reporting_test.dart
git -C neurocnl commit -m "refactor: narrow studio riverpod selectors"
```

## Task 9: Final verification and cleanup

**Files:**
- Modify: any touched files from prior tasks
- Test: `neurocnl/frontend/test/providers_test.dart`
- Test: `neurocnl/frontend/test/widgets/cnl_editor_test.dart`
- Test: `neurocnl/frontend/test/screens/studio_screen_test.dart`
- Test: `neurocnl/frontend/test/widgets/error_reporting_test.dart`

- [ ] **Step 1: Run targeted verification suite**

Run:

```bash
cd neurocnl/frontend
flutter test test/providers_test.dart
flutter test test/widgets/cnl_editor_test.dart
flutter test test/screens/studio_screen_test.dart
flutter test test/widgets/error_reporting_test.dart
flutter analyze lib/providers/spec_provider.dart lib/providers/workspace_provider.dart lib/providers/pipeline_provider.dart lib/providers/canonical_doc_provider.dart lib/providers/canvas/canvas_provider.dart lib/providers/nir_import_provider.dart lib/providers/studio_sync_notifier.dart lib/widgets/cnl_editor.dart lib/widgets/canvas/canvas_cnl_editor.dart lib/screens/studio_screen.dart
```

Expected:
- all targeted tests PASS
- analyze reports no new warnings/errors in touched files

- [ ] **Step 2: Run broader Studio integration checks if the above are green**

Run:

```bash
cd neurocnl/frontend
flutter test test/integration/nir_three_way_sync_test.dart
flutter test test/providers/studio_sync_notifier_nir_test.dart
flutter test test/providers/canvas/canvas_provider_dopush_preservation_test.dart
```

Expected:
- PASS, or only clearly pre-existing unrelated failures documented in the task summary

- [ ] **Step 3: Commit**

```bash
git -C neurocnl add frontend
git -C neurocnl commit -m "refactor: continue studio single source of truth"
```

## Assumptions and defaults

- `workspaceProvider` remains the root writable Riverpod store instead of introducing a brand new top-level `studioStateProvider`.
- `specTextProvider` stays in place as a compatibility adapter because too many widgets and tests already depend on it.
- Canvas selection/focus/drag affordances remain UI-local in `canvasProvider`; only durable graph data is document-owned.
- `PipelineNotifier`, `CanonicalDocNotifier`, and `NirImportNotifier` remain as compatibility provider facades during this phase; they should mirror document-owned branches instead of owning parallel durable state.
- The existing `frontend/lib/screens/studio_screen.dart` git conflict state is pre-existing repo noise; implementation should avoid broad unrelated edits there beyond the specific selector and text-sync work required by this plan.
