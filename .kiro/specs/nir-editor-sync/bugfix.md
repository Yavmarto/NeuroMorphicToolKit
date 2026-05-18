# Bugfix Requirements Document

## Introduction

The NIR tab in CNL Studio (`NirImporterTab`) is currently a read-only inspector: it displays an HDF5 tree of the loaded NIR graph but provides no editable fields and does not propagate user changes back to the CNL editor or the canvas. This means the NIR surface is a passive viewer, breaking the bidirectional three-way sync that the CNL editor and canvas editor already have with each other. Users cannot drive the model from the NIR representation, and loading a template does not update the NIR view while in NIR mode. The fix must make the NIR tab a full peer editor alongside the CNL editor and canvas editor, enabling complete bidirectional sync in all directions.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the user edits a node parameter (e.g., a LIF neuron threshold) in the NIR tab THEN the system provides no editable fields, so the change cannot be made from the NIR tab at all

1.2 WHEN the user modifies a node parameter value in the NIR tab THEN the system does not update the CNL editor with the corresponding CNL text

1.3 WHEN the user modifies a node parameter value in the NIR tab THEN the system does not update the canvas with the corresponding node/parameter state

1.4 WHEN the user adds or removes a node or edge in the NIR tab THEN the system provides no controls to do so, leaving structural edits unavailable from the NIR surface

1.5 WHEN the user switches to the NIR tab while in NIR mode THEN the system does not push any NIR-originated change back into the CNL editor or canvas (the `syncFromCanvas` call is one-directional only: canvas → NIR display with no write-back path)

1.6 WHEN a template is loaded from the Template Gallery while the NIR tab is the active view THEN the system does not reflect the new template's NIR graph in the NIR editor fields; the NIR tab shows stale or idle content

1.7 WHEN the canvas editor or CNL editor changes while the NIR tab is the active view THEN the system does not refresh the NIR editor fields in real time (only a tab-switch triggers an update)

### Expected Behavior (Correct)

2.1 WHEN the user edits a node parameter field in the NIR editor THEN the system SHALL present editable fields for all NIR node parameters (matching those available in the canvas property panel and defined in `NirParameterDef`)

2.2 WHEN the user commits a node parameter change in the NIR editor THEN the system SHALL propagate the updated NIR graph to the CNL editor (regenerating the CNL text via the same path used by canvas → CNL sync)

2.3 WHEN the user commits a node parameter change in the NIR editor THEN the system SHALL propagate the updated NIR graph to the canvas editor (updating the canvas node parameters via `canvasProvider.notifier.updateNodeParameters`)

2.4 WHEN the user adds or removes a node or edge in the NIR editor THEN the system SHALL propagate the structural change to both the CNL editor and the canvas editor

2.5 WHEN the NIR editor is the active view and a change originates there THEN the system SHALL treat it as authoritative and SHALL update the CNL editor and canvas editor without triggering a re-sync loop back into the NIR editor

2.6 WHEN a template is loaded while the NIR tab is active THEN the system SHALL update the NIR editor fields to reflect the new template's NIR graph immediately, consistent with how the CNL editor and canvas receive template content

2.7 WHEN the CNL editor or canvas editor changes while the NIR tab is the active view THEN the system SHALL live-update the NIR editor fields to reflect the latest graph state (same debounce/listen pattern used for CNL ↔ canvas)

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user loads a `.nir` file from the NIR tab THEN the system SHALL CONTINUE TO parse the file, display the HDF5 tree, and write back the CNL text and canvas graph as it does today

3.2 WHEN the pipeline generates a NIR result (via Generate) and no file or canvas source has been loaded THEN the system SHALL CONTINUE TO auto-populate the NIR tab from the pipeline `nir_code` as it does today

3.3 WHEN the canvas is the active editor and the user edits a node parameter THEN the system SHALL CONTINUE TO regenerate CNL and sync it to the CNL editor via `cnlSpecProvider` and `StudioSyncNotifier.onCanvasCnlSpec`

3.4 WHEN the CNL editor is the active editor and the user types THEN the system SHALL CONTINUE TO debounce and sync the text to the canvas via `StudioSyncNotifier.scheduleCnlToCanvasDebounced`

3.5 WHEN the user switches from the NIR tab to the canvas or CNL tab THEN the system SHALL CONTINUE TO trigger the appropriate one-shot sync (`syncCnlToCanvas` or `syncCanvasToCnl`) as it does today

3.6 WHEN a template is loaded from the Template Gallery while the CNL or canvas tab is active THEN the system SHALL CONTINUE TO apply the template to the CNL editor and canvas as it does today (via `applyTemplateToWorkspace`)

3.7 WHEN the NIR tab is in idle state (no source loaded) THEN the system SHALL CONTINUE TO display the idle placeholder instructing the user to load a `.nir` file or run Generate
