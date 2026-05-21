# Bugfix Requirements Document

## Introduction

This document captures four bugs found in the NIR/CNL editor (NeuroCNL Studio). The bugs span the Flutter frontend and the Python backend, covering edge loading on NIR file import, connection registration when applying a CNL template, the NIR viewer panel that has been deemed useless, and a validation layer that becomes stale after manual edits revert a breaking change.

---

## Bug Analysis

### Current Behavior (Defect)

**Bug 1 — Edge loading on NIR file import**

1.1 WHEN a user loads a `.nir` file via the NIR importer tab THEN the system generates CNL from the binary via `generateCnlFromNirBytes`, parses it through the canonical endpoint into a `CanonicalEditorDocument`, and calls `canvasGraphFromCanonical` — but `canvasGraphFromCanonical` maps every projection node to `componentId: 'lif_population'` and `nirType: 'nir.LIF'` regardless of the actual NIR primitive type, so the resulting canvas graph carries wrong type metadata for all non-LIF nodes

1.2 WHEN the NIR-file write-back sets the canvas graph via `canvasProvider.setGraph` THEN the system does NOT call `validationProvider.validate` on the new graph, so the validation panel reflects an outdated state after file load

1.3 WHEN `serialize_nir_to_canvas_graph` is called with a NIR graph whose `graph.edges` list is non-empty THEN the system produces a correctly populated `CanvasGraph.edges` list on the backend — yet the frontend write-back path that flows through `generateCnlFromNirBytes` → `parseCnlCanonical` → `canvasGraphFromCanonical` discards edges because `CanvasProjection.edges` only carries the lightweight projection shape (`source`, `target`, `polarity`, `weight`) and `canvasGraphFromCanonical` builds a `CanvasEdge` from those projection fields; if the backend canonical endpoint returns an empty or partial `edges` list in the projection the canvas shows no edges

**Bug 2 — CNL template connection registration**

2.1 WHEN a user selects a template from the Template Gallery THEN the system calls `applyTemplateToWorkspace`, which calls `canonicalDocProvider.updateFromCnl(template.spec)` — this updates `canonicalDocProvider` and the reactive listener in `CanvasNotifier` calls `_mirrorProjection`, which calls `canvasGraphFromCanonical` and sets the graph — but `canvasGraphFromCanonical` hardcodes `componentId: 'lif_population'` and `nirType: 'nir.LIF'` for every node, causing all non-LIF template nodes to be registered with incorrect types in the canvas

2.2 WHEN `applyTemplateToWorkspace` completes and the canvas graph is populated with template nodes and edges THEN the system does NOT call `validationProvider.validate` on the populated graph, so validation state is not triggered by template loading and the validation panel remains in its prior state

2.3 WHEN the `_mirrorProjection` path sets a new graph (from a template or CNL parse) and that graph contains edges THEN the edges are written to `canvasProvider` correctly via `canvasGraphFromCanonical` — however because `componentId` and `nirType` are hardcoded to the LIF values, any NIR-aware edge validation that depends on port specs (checked against `NIR_CANVAS_TYPE_SPECS` keyed by `nir_type`) uses the wrong type and may silently fail port validation

**Bug 3 — NIR viewer panel is present and wasted screen space**

3.1 WHEN the NIR importer tab is rendered THEN the system displays a two-column layout where the right column (`flex: 2`) renders a recursive HDF5 tree view (`_NirTreeView`) alongside the editable node/edge panel — this right-side viewer panel is considered unnecessary and wastes screen space that could be used by the editor

**Bug 4 — Validation layer staleness after manual revert**

4.1 WHEN a user has a valid canvas state, edits the CNL text to introduce a breaking change (triggering a failed validation), and then manually types back the original CNL text (character by character, without using a "Revert" button) THEN the system does NOT re-run `validationProvider.validate` after the CNL-to-canvas sync completes for the reverted text, leaving the validation panel showing the stale failure from the broken intermediate state

4.2 WHEN `StudioSyncNotifier.syncCnlToCanvas` is called with a CNL string that parses successfully and produces a canvas graph THEN the system calls `validationProvider.validate` on the updated graph — however if a prior CNL edit triggered `_pushToCanonical` inside `CanvasNotifier` and `validationProvider` was updated with an error state at that time, and subsequently the user manually restores the original CNL, the debounce in `scheduleCnlToCanvasDebounced` may be cancelled or the `_syncingCnlToCanvas` / `_syncingCanvasToCnl` guard may prevent the final `validate` call from completing

4.3 WHEN a CNL edit is made that changes a canvas node parameter (e.g. updating a synapse weight) and `_pushToCanonical` fires with `debounce: true` inside `CanvasNotifier` THEN the system calls `validationProvider.validate` as a side-effect of the push — but this intermediate validation result (which may be a failure) is NOT cleared or superseded when the user subsequently reverts the CNL change, because the `canvasProvider` state mutation from `_mirrorProjection` does NOT call `validate` and `syncCnlToCanvas` only calls `validate` after a successful parse, leaving the validation in a stale failed state if any intermediate `_pushToCanonical` validation fired

---

### Expected Behavior (Correct)

**Bug 1 — Edge loading on NIR file import**

2.1 WHEN a user loads a `.nir` file and the write-back path produces a canvas graph via `canvasGraphFromCanonical` THEN the system SHALL derive `componentId` and `nirType` for each canvas node from the `nir_type` field present in the `CanvasProjection.CanvasNode` returned by the backend projection, falling back to a canonical mapping (matching `NIR_CANVAS_TYPE_SPECS`) rather than hardcoding `'lif_population'` and `'nir.LIF'`

2.2 WHEN the NIR-file write-back sets the canvas graph via `canvasProvider.setGraph` THEN the system SHALL also call `validationProvider.validate` on the new graph so the validation panel reflects the current loaded state

2.3 WHEN a `.nir` file is loaded and the backend canonical projection includes edges in `CanvasProjection.edges` THEN the system SHALL produce a `CanvasGraph` whose `edges` list is populated with those edges, so all connections from the NIR file appear on the canvas

**Bug 2 — CNL template connection registration**

2.4 WHEN `canvasGraphFromCanonical` constructs `CanvasNode` objects from a `CanvasProjection` THEN the system SHALL assign `componentId` and `nirType` from the `nir_type` field in the projection node data rather than hardcoding any fixed value, so that template nodes of any NIR primitive type are registered with correct type metadata

2.5 WHEN `applyTemplateToWorkspace` completes and the canvas graph is populated THEN the system SHALL trigger `validationProvider.validate` on the populated canvas graph so validation state is up to date immediately after template application

**Bug 3 — NIR viewer panel removal**

2.6 WHEN the NIR importer tab is rendered and a graph is loaded THEN the system SHALL display only the node/edge editor panel without the right-side HDF5 tree viewer column, giving the editor the full available width

**Bug 4 — Validation layer staleness after manual revert**

2.7 WHEN `StudioSyncNotifier.syncCnlToCanvas` completes a successful CNL parse and sets the canvas graph THEN the system SHALL always call `validationProvider.validate` on the final settled graph, regardless of any intermediate validation states that were set by `_pushToCanonical` during the same editing session

2.8 WHEN `CanvasNotifier._mirrorProjection` sets a new graph derived from a CNL parse (i.e. triggered by the `canonicalDocProvider` listener) THEN the system SHALL call `validationProvider.validate` on the newly mirrored graph so validation always reflects the current authoritative canvas state

---

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a `.nir` file is loaded and the HDF5 inspect call succeeds THEN the system SHALL CONTINUE TO display the node list and edge list in the NIR editor panel as it does today

3.2 WHEN the CNL editor is active and the user types THEN the system SHALL CONTINUE TO debounce and sync the text to the canvas via `StudioSyncNotifier.scheduleCnlToCanvasDebounced`

3.3 WHEN the canvas editor is active and the user edits a node parameter THEN the system SHALL CONTINUE TO regenerate CNL and sync it to the CNL editor via `_pushToCanonical` and `onCanonicalDocFromCanvas`

3.4 WHEN a template is loaded while the NIR importer tab is NOT the active tab THEN the system SHALL CONTINUE TO apply the template spec to the CNL editor and populate the canvas without affecting NIR-specific state

3.5 WHEN a valid canvas graph is sent to `POST /api/neurosim/nir/import` THEN the system SHALL CONTINUE TO return a `CanvasGraph` with correctly typed nodes and edges as it does today via `serialize_nir_to_canvas_graph`

3.6 WHEN `validationProvider.validate` is called with a valid canvas graph THEN the system SHALL CONTINUE TO send the graph to the backend validation endpoint and store the result as `AsyncData(ValidationResult)`

3.7 WHEN the user uses the explicit "Revert" action (if present) to restore a previous state THEN the system SHALL CONTINUE TO trigger whatever validation path was already in place for that action

3.8 WHEN the NIR importer tab displays loaded state from a pipeline or canvas source (not a file) THEN the system SHALL CONTINUE TO show the node/edge editor panel with the full available width (the HDF5 tree is absent for non-file sources already)

3.9 WHEN a `.nir` file load fails at the inspect step THEN the system SHALL CONTINUE TO show the error view and not attempt write-back to the canvas or CNL editor
