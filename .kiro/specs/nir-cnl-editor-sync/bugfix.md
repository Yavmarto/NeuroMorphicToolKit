# Bugfix Requirements Document

## Introduction

NeuroCNL Studio contains a bidirectional sync between the CNL text editor and the canvas. The canvas-to-CNL direction works correctly: `POST /api/neurosim/generate-cnl` routes through `NIR_Renderer` and produces accurate NIR-native CNL. The CNL-to-canvas direction is broken in two places:

1. **Backend routing bug**: `POST /api/neurosim/parse-cnl-canonical` calls `canonical_from_cnl()` in `canonical_editor_projection.py`, which calls `build_ir_from_spec_text()` — the old biological IR parser. NIR-native CNL (e.g. `LIF "n" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0`) fails to match any pattern in the biological grammar, so the route returns a `CanonicalEditorDocument` with an empty or `None` canvas. The frontend then surfaces the hardcoded error "CNL parsed but produced an empty canvas".

2. **Frontend hardcoding bug**: `sync_provider.dart` `_canvasGraphFromCanonical()` ignores the `nir_type` and `componentId` fields that the backend produces, and instead forces every node to `componentId: 'lif_population'` and `nirType: 'nir.LIF'`, regardless of the actual primitive type in the CNL or canvas projection.

Together these two bugs mean that a `.nir` file loaded into Studio can never round-trip back to a correct canvas via the CNL editor, and any NIR-native CNL typed into the editor is rejected with an empty canvas.

---

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN NIR-native CNL text (where the first non-comment, non-blank line starts with a keyword from `{Input, Output, IF, LIF, LI, CubaLIF, CubaLI, I, Linear, Affine, Scale, Conv1d, Conv2d, AvgPool2d, SumPool2d, Flatten, Delay, Threshold, Connect, NIRGraph}`) is sent to `POST /api/neurosim/parse-cnl-canonical` THEN the system routes the text through the biological IR parser (`build_ir_from_spec_text`), which fails to match any sentence, and the endpoint returns a `CanonicalEditorDocument` with `canvas=None` or an empty `canvas.nodes` list.

1.2 WHEN the frontend calls `syncToCanvas()` and the backend returns a `CanonicalEditorDocument` whose `canvas.nodes` is empty THEN the system displays the hardcoded error message "CNL parsed but produced an empty canvas. Ensure the text follows the canonical reflex-arc grammar (sensory → motor, lif_population, static_synapse)" — an error message referencing the old biological grammar that is inapplicable to NIR-native CNL.

1.3 WHEN `_canvasGraphFromCanonical()` in `sync_provider.dart` constructs canvas nodes from a `CanvasProjection` THEN the system assigns `componentId: 'lif_population'` and `nirType: 'nir.LIF'` to every node regardless of the actual NIR primitive type present in the projection data.

### Expected Behavior (Correct)

2.1 WHEN NIR-native CNL text (where the first non-comment, non-blank line starts with a NIR primitive keyword or `Connect` or `NIRGraph`) is sent to `POST /api/neurosim/parse-cnl-canonical` THEN the system SHALL detect the NIR-native dialect, route the text through `NIR_CNL_Parser` → `NIR_Compiler` → `serialize_nir_to_canvas_graph()`, wrap the resulting `CanvasGraph` into a `CanonicalEditorDocument` with a fully populated `canvas` field, and return HTTP 200 with that document.

2.2 WHEN `_canvasGraphFromCanonical()` constructs a `CanvasNode` for a projection node whose underlying NIR type is `nir.Conv2d` THEN the system SHALL assign `componentId: 'nir.Conv2d'` and `nirType: 'nir.Conv2d'` to that canvas node.

2.3 WHEN `_canvasGraphFromCanonical()` constructs a `CanvasNode` for a projection node whose underlying NIR type is `nir.LIF` THEN the system SHALL assign `componentId: 'lif_population'` and `nirType: 'nir.LIF'` to that canvas node, matching the mapping defined in `NIR_CANVAS_TYPE_SPECS`.

2.4 WHEN `_canvasGraphFromCanonical()` constructs a `CanvasNode` for any projection node THEN the system SHALL derive `componentId` and `nirType` from the `nir_type` field carried in the projection node data (as supplied by `serialize_nir_to_canvas_graph()`), rather than hardcoding any fixed value.

### Unchanged Behavior (Regression Prevention)

3.1 WHEN biological CNL text (where sentences use vocabulary such as `sensory_population`, `motor_population`, `lif_population`, `static_synapse`, `MUST`, `MUST NOT`) is sent to `POST /api/neurosim/parse-cnl-canonical` THEN the system SHALL CONTINUE TO route that text through the existing biological `canonical_from_cnl()` path and return a populated `CanonicalEditorDocument` as before.

3.2 WHEN a valid `.nir` binary payload is sent to `POST /api/neurosim/generate-cnl-from-nir` THEN the system SHALL CONTINUE TO return accurate NIR-native CNL text produced by `NIR_Renderer` without any change to that endpoint's behavior.

3.3 WHEN a `CanvasGraph` is sent to `POST /api/neurosim/generate-cnl` THEN the system SHALL CONTINUE TO return CNL text produced by `generate_cnl_from_nir()` without any change to that endpoint's behavior.

3.4 WHEN `POST /api/neurosim/parse-cnl-canonical` receives NIR-native CNL that contains a parse or compile error (e.g. unknown parameter name, ghost node reference) THEN the system SHALL CONTINUE TO return HTTP 422 with a structured error body containing a `message` field, as it currently does for biological CNL failures.

3.5 WHEN canvas nodes of type `nir.Input` or `nir.Output` are constructed by `_canvasGraphFromCanonical()` THEN the system SHALL CONTINUE TO assign `componentId: 'input_node'` and `componentId: 'output_node'` respectively, matching the `NIR_CANVAS_TYPE_SPECS` mapping already used by `serialize_nir_to_canvas_graph()`.
