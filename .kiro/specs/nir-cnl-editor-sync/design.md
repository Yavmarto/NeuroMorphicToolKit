# nir-cnl-editor-sync Bugfix Design

## Overview

Two bugs prevent NIR-native CNL from round-tripping through the Studio editor canvas.

**Fix 1 (Backend):** `POST /api/neurosim/parse-cnl-canonical` unconditionally calls the biological
`canonical_from_cnl()` path. For NIR-native CNL this path produces an empty canvas. The fix adds a
dialect gate using the existing `_is_nir_native()` helper: NIR-native text is routed through
`NIR_CNL_Parser → NIR_Compiler → serialize_nir_to_canvas_graph`, and the resulting `CanvasGraph`
is wrapped into a `CanonicalEditorDocument` with a fully populated `CanvasProjection`. Biological
CNL continues to use `canonical_from_cnl()` unchanged.

**Fix 2 (Frontend):** `_canvasGraphFromCanonical()` in `sync_provider.dart` hardcodes every node to
`componentId: 'lif_population'` and `nirType: 'nir.LIF'`, ignoring the `nir_type` and
`componentId` fields now present in the projection node dicts. The fix reads `nir_type` from the
raw node dict and applies the same `NIR_CANVAS_TYPE_SPECS` mapping used by the serializer. The
dialect-specific error message in `syncToCanvas()` is also replaced with a generic one.

## Glossary

- **Bug_Condition (C)**: The input condition that triggers the bug — NIR-native CNL text sent to
  `parse-cnl-canonical` (Fix 1), or any projection node dict with a `nir_type` other than
  `nir.LIF` (Fix 2).
- **Property (P)**: Desired correct behavior — HTTP 200 with a fully populated `canvas` field
  (Fix 1); canvas node `componentId`/`nirType` matching `NIR_CANVAS_TYPE_SPECS` for the node's
  `nir_type` (Fix 2).
- **Preservation**: The biological `canonical_from_cnl()` path, all other endpoints, and
  `nir.LIF` canvas node construction must remain unchanged.
- **`_is_nir_native(text)`**: Function in `neurocnl.pipeline` that returns `True` when the first
  substantive line of `text` starts with a NIR primitive keyword, `Connect`, or `NIRGraph`.
- **`NIR_CANVAS_TYPE_SPECS`**: `dict[str, NirCanvasTypeSpec]` in
  `backend.app.services.nir_graph_serializer` — the single source of truth for mapping a
  `nir_type` string to `component_id`, category, label, and port specs.
- **`CanvasProjection.nodes`**: `list[dict[str, Any]]` in the Pydantic contract; the biological
  path stores typed-population dicts; after Fix 1 the NIR path stores richer node dicts (see
  §"Node Dict Shape" below).

## Bug Details

### Bug Condition

**Fix 1 — Backend routing:** The bug manifests when the `spec_text` payload sent to
`parse-cnl-canonical` is NIR-native CNL. The route calls `canonical_from_cnl()` regardless of
dialect; `canonical_from_cnl()` calls `build_ir_from_spec_text()`, which routes through the
biological grammar and silently produces a `NetworkIR` with zero populations, causing the canvas
projection to be empty.

**Formal Specification:**
```
FUNCTION isBugCondition_Fix1(request)
  INPUT: request of type ParseCnlRequest
  OUTPUT: boolean

  RETURN _is_nir_native(request.spec_text)
         AND route_calls_canonical_from_cnl(request.spec_text)
         -- i.e. the NIR dialect gate is absent
END FUNCTION
```

**Fix 2 — Frontend hardcoding:** The bug manifests when a `CanvasProjection` produced by the
fixed backend contains a node dict whose `nir_type` is anything other than `nir.LIF`.

```
FUNCTION isBugCondition_Fix2(nodeDict)
  INPUT: nodeDict of type Map<String, dynamic>
  OUTPUT: boolean

  RETURN nodeDict['nir_type'] != null
         AND nodeDict['nir_type'] != 'nir.LIF'
END FUNCTION
```

### Examples

- `LIF "n1" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0` → Fix 1 bug: empty canvas returned.
  Fix 1 correct: `canvas.nodes = [{id:"n1", nir_type:"nir.LIF", componentId:"lif_population", ...}]`
- `Conv2d "conv" weight_shape [8,1,3,3]` → Fix 1 bug: empty canvas. Fix 2 bug: if backend were
  somehow bypassed, Dart would set `componentId='lif_population'`. Fix 1+2 correct: backend
  returns `nir_type:"nir.Conv2d"`, Dart maps it to `componentId:'nir.Conv2d'`.
- Biological CNL (`sensory_population "S" MUST fire...`) → unchanged (preservation).
- NIR CNL with typo (`LIF "n1" tau abc`) → HTTP 422 with `detail.message` (preservation).

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Biological CNL sent to `parse-cnl-canonical` continues to route through `canonical_from_cnl()`
  and returns an equivalent `CanonicalEditorDocument` as before.
- `POST /api/neurosim/generate-cnl-from-nir` is untouched.
- `POST /api/neurosim/generate-cnl` and `POST /api/neurosim/parse-cnl` are untouched.
- Canvas nodes with `nir_type: 'nir.LIF'` continue to be assigned
  `componentId: 'lif_population'` by `_canvasGraphFromCanonical()`.
- Canvas nodes with `nir_type: 'nir.Input'` / `'nir.Output'` continue to be assigned
  `componentId: 'input_node'` / `'output_node'`.
- HTTP 422 is still returned for any CNL (NIR-native or biological) that fails to parse or
  compile, and the response body still contains a `message` field.

**Scope:**
All inputs that do NOT satisfy `isBugCondition_Fix1` or `isBugCondition_Fix2` are completely
unaffected. This includes:
- Biological CNL requests to `parse-cnl-canonical`
- All canvas-to-CNL requests
- Any `.nir` upload
- `CanvasProjection` nodes that already have the correct `nir_type` set

### Node Dict Shape (Backend → Frontend Contract)

After Fix 1, each entry in `CanvasProjection.nodes` for a NIR-native document will be a plain
`dict` with **at minimum** the following keys, mirroring the `CanvasNode` Pydantic fields that
`serialize_nir_to_canvas_graph()` populates:

| Key | Type | Example | Notes |
|-----|------|---------|-------|
| `id` | `str` | `"n1"` | Node name in the NIR graph |
| `nir_type` | `str` | `"nir.LIF"` | One of the 17 keys in `NIR_CANVAS_TYPE_SPECS` |
| `componentId` | `str` | `"lif_population"` | `spec.component_id` from `NIR_CANVAS_TYPE_SPECS` |
| `label` | `str` | `"LIF"` | Display label |
| `parameters` | `dict` | `{"n_neurons": 1, "tau": 0.02, ...}` | Type-specific params from `_serialize_node_parameters()` |

The biological path nodes do not contain `nir_type` or `componentId`; the Dart side must treat
their absence as a signal to fall through to biological-projection handling (unchanged behavior).

## Hypothesized Root Cause

### Fix 1 — Backend

1. **Missing dialect gate**: `parse_cnl_canonical` has a single code path that calls
   `canonical_from_cnl(request.spec_text)`. There is no call to `_is_nir_native()` before this.
   `_is_nir_native()` already exists and works correctly in `neurocnl.pipeline`; it simply is not
   invoked from the router.

2. **Biological IR produces empty populations for NIR keywords**: When NIR-native CNL passes
   through `build_ir_from_spec_text()`, `parse_spec_text()` actually does route through
   `_parse_nir_native()` (because `_is_nir_native()` is called there), producing `NIRNodeRecord`
   and `NIREdgeRecord` objects. However `lower_to_ir()` expects `ParsedSentence` dicts with
   biological concepts like `sensory_population` and produces a `NetworkIR` with zero populations
   from NIR records. The canvas projection of a zero-population `NetworkIR` is `[]`.

3. **The NIR compilation path already exists in the router** — it is used by `POST /parse-cnl`
   (the legacy endpoint). Fix 1 is simply lifting that same `NIR_CNL_Parser → NIR_Compiler →
   serialize_nir_to_canvas_graph` sequence into the canonical endpoint with a dialect check.

### Fix 2 — Frontend

4. **`_canvasGraphFromCanonical()` was written before the NIR projection existed**: The function
   accesses typed `CanvasNode` objects (from `canonical_editor_document.dart`) which only expose
   biological fields (`id`, `label`, `type`, `size`, `threshold`, `tau`). The `nir_type` and
   `componentId` keys in the raw dict never reach the function because `CanvasNode.fromJson()`
   silently discards them.

5. **The fix requires reading from the raw `Map<String, dynamic>`** before constructing the
   typed `CanvasNode`, because the typed model does not carry `nir_type` or `componentId`.
   Alternatively, extend `CanvasNode` in `canonical_editor_document.dart` to surface these fields.
   The latter is cleaner and enables future consumers; it is the approach taken here.

## Correctness Properties

Property 1: Bug Condition — NIR-native CNL produces a populated canvas via the canonical route

_For any_ `spec_text` where `_is_nir_native(spec_text)` returns `True` and the text is
syntactically valid NIR-native CNL, the fixed `parse_cnl_canonical` route SHALL return HTTP 200
with a `CanonicalEditorDocument` whose `canvas.nodes` is non-empty and each node dict contains
`nir_type`, `componentId`, `label`, and `id` keys consistent with the NIR graph produced by
`NIR_CNL_Parser → NIR_Compiler`.

**Validates: Requirements 2.1**

Property 2: Bug Condition — Dart _canvasGraphFromCanonical() maps nir_type to correct componentId

_For any_ projection node dict where `nir_type` is one of the 17 entries in
`NIR_CANVAS_TYPE_SPECS` (i.e. `isBugCondition_Fix2` returns `True`), the fixed
`_canvasGraphFromCanonical()` SHALL construct a `CanvasNode` whose `componentId` and `nirType`
fields exactly match `NIR_CANVAS_TYPE_SPECS[nir_type].component_id` and `nir_type` respectively.

**Validates: Requirements 2.2, 2.3, 2.4, 3.5**

Property 3: Preservation — Biological CNL path is unchanged

_For any_ `spec_text` where `_is_nir_native(spec_text)` returns `False`, the fixed
`parse_cnl_canonical` route SHALL produce the same `CanonicalEditorDocument` as the original
(unfixed) code, specifically by delegating to `canonical_from_cnl()` without modification.

**Validates: Requirements 3.1**

Property 4: Preservation — Parse/compile errors still produce HTTP 422

_For any_ `spec_text` where `_is_nir_native(spec_text)` returns `True` but the text contains a
`ParseError` or `CompileError`, the fixed route SHALL return HTTP 422 with a response body that
contains a `detail.message` string field, in the same format as the existing 422 responses.

**Validates: Requirements 3.4**

## Fix Implementation

### Fix 1 — `neurocnl/neurosim/app/routers/generation.py`

**Function:** `parse_cnl_canonical`

**New import (already present via `nir_cnl.parser`, but add pipeline import):**
```python
from neurocnl.pipeline import _is_nir_native
```

**Specific Changes:**

1. **Add dialect gate at the top of the try block.** Before calling `canonical_from_cnl`, call
   `_is_nir_native(request.spec_text)`. If `True`, take the NIR path; otherwise fall through to
   the existing biological path.

2. **NIR path — parse and compile:**
   ```python
   records = NIR_CNL_Parser().parse(request.spec_text)
   nir_graph = NIR_Compiler().compile(records)
   canvas_graph = serialize_nir_to_canvas_graph(nir_graph)
   ```
   `NIR_CNL_Parser` and `NIR_Compiler` are already imported in the module.
   `serialize_nir_to_canvas_graph` is already imported.

3. **NIR path — build CanvasProjection node dicts.** Iterate `canvas_graph.nodes` (each is a
   `CanvasNode` Pydantic model) and produce plain dicts:
   ```python
   projection_nodes = [
       {
           "id": node.id,
           "nir_type": node.nir_type,
           "componentId": node.component_id,
           "label": node.label or node.id,
           **node.parameters,
       }
       for node in canvas_graph.nodes
   ]
   projection_edges = [
       {
           "source": edge.source_node_id,
           "target": edge.target_node_id,
           **edge.parameters,
       }
       for edge in canvas_graph.edges
   ]
   ```

4. **NIR path — wrap into CanonicalEditorDocument and return:**
   ```python
   document = CanonicalEditorDocument(
       ir_json={},
       cnl_text=request.spec_text,
       canvas=CanvasProjection(
           nodes=projection_nodes,
           edges=projection_edges,
       ),
   )
   return ParseCnlResponse(document=document, diagnostics=[])
   ```
   `CanvasProjection` is already imported from `neurosim.contracts.canonical_editor_contracts`.

5. **Error handling — catch ParseError and CompileError** in the NIR branch and raise HTTP 422
   using the same `detail` shape as the existing handler:
   ```python
   except (ParseError, CompileError) as exc:
       raise HTTPException(
           status_code=422,
           detail={"message": str(exc), "unsupported_concepts": []},
       ) from exc
   ```
   This is inside the outer `try` block so the existing catch-all `except Exception` below it
   continues to cover unanticipated errors for the biological path.

**No other files in the backend are changed.**

### Fix 2 — `neurocnl/frontend/lib/models/canonical_editor_document.dart`

**Class:** `CanvasNode` (in the canonical editor document model, **not** `canvas.dart`)

Add two nullable fields and read them in `fromJson`:

```dart
final String? nirType;    // json key: 'nir_type'
final String? componentId; // json key: 'componentId'
```

Update `fromJson`:
```dart
nirType: json['nir_type'] as String?,
componentId: json['componentId'] as String?,
```

Update `toJson` to round-trip the fields:
```dart
if (nirType != null) 'nir_type': nirType,
if (componentId != null) 'componentId': componentId,
```

### Fix 2 — `neurocnl/frontend/lib/providers/canvas/sync_provider.dart`

**componentId → nirType mapping constant (top of file, outside any function):**

```dart
/// Maps NIR type strings to canvas component IDs.
/// Mirrors NIR_CANVAS_TYPE_SPECS in nir_graph_serializer.py.
const Map<String, String> _nirTypeToComponentId = {
  'nir.Input':     'input_node',
  'nir.Output':    'output_node',
  'nir.LIF':       'lif_population',
  'nir.CubaLIF':   'lif_population',
  'nir.IF':        'lif_population',
  'nir.LI':        'lif_population',
  'nir.Linear':    'nir.Linear',
  'nir.Affine':    'nir.Affine',
  'nir.Conv1d':    'nir.Conv1d',
  'nir.Conv2d':    'nir.Conv2d',
  'nir.Flatten':   'nir.Flatten',
  'nir.AvgPool2d': 'nir.AvgPool2d',
  'nir.SumPool2d': 'nir.SumPool2d',
  'nir.Delay':     'nir.Delay',
  'nir.Scale':     'nir.Scale',
};
```

**`_canvasGraphFromCanonical()` node construction change:**

Replace the hardcoded `componentId` and `nirType`:
```dart
// Before (buggy):
componentId: 'lif_population',
nirType: 'nir.LIF',

// After (fixed):
final rawNirType = projection.nodes[index].nirType ?? 'nir.LIF';
// ...
componentId: _nirTypeToComponentId[rawNirType] ?? rawNirType,
nirType: rawNirType,
```

The `projection.nodes[index]` here is the typed `canonical.CanvasNode`; after the model fix above
it now exposes `.nirType` and `.componentId`.

**`syncToCanvas()` error message change:**

Replace the dialect-specific fallback error:
```dart
// Before (buggy — references biological grammar):
'CNL parse failed — check that the text uses the canonical '
'reflex-arc grammar (sensory → motor, lif_population, static_synapse).'

// After (generic):
'CNL parse failed — check the editor for syntax errors.'
```

Also replace the empty-canvas error message:
```dart
// Before:
'CNL parsed but produced an empty canvas. '
'Ensure the text follows the canonical reflex-arc grammar '
'(sensory → motor, lif_population, static_synapse).'

// After:
'CNL parsed but produced an empty canvas. '
'Check that the text is valid CNL (NIR-native or biological grammar).'
```

### componentId Mapping — All 15 NIR Primitives (excluding Input/Output)

This table is the Dart-side mirror of `NIR_CANVAS_TYPE_SPECS` in `nir_graph_serializer.py`.

| `nir_type` | `componentId` | Category |
|---|---|---|
| `nir.LIF` | `lif_population` | neuron |
| `nir.CubaLIF` | `lif_population` | neuron |
| `nir.IF` | `lif_population` | neuron |
| `nir.LI` | `lif_population` | neuron |
| `nir.Linear` | `nir.Linear` | transform |
| `nir.Affine` | `nir.Affine` | transform |
| `nir.Conv1d` | `nir.Conv1d` | transform |
| `nir.Conv2d` | `nir.Conv2d` | transform |
| `nir.Scale` | `nir.Scale` | transform |
| `nir.Flatten` | `nir.Flatten` | utility |
| `nir.Delay` | `nir.Delay` | utility |
| `nir.AvgPool2d` | `nir.AvgPool2d` | pooling |
| `nir.SumPool2d` | `nir.SumPool2d` | pooling |
| `nir.Input` | `input_node` | io |
| `nir.Output` | `output_node` | io |

The four neuron types (`LIF`, `CubaLIF`, `IF`, `LI`) share `lif_population` because the Studio
canvas uses a single LIF population component for all integrate-and-fire variants. The transform,
utility, and pooling types each carry their own `componentId` matching the `nir_type` string.

Unknown / future `nir_type` values fall back to using the `nir_type` string itself as the
`componentId` — this avoids a crash while making unknown types visible in the canvas.

## Testing Strategy

### Validation Approach

Two-phase approach: first run exploratory tests against the **unfixed** code to confirm the bug
manifests as hypothesized, then run fix-checking and preservation tests against the **fixed** code.

---

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples on unfixed code that confirm the root cause analysis.

**Test Plan**: Use the existing test harness in `neurocnl/neurosim/` to call the router function
directly (not via HTTP) and the existing `pytest` suite to call `_canvasGraphFromCanonical` via
a widget test.

**Test Cases**:

1. **NIR LIF canvas is empty (Fix 1 exploration)**: Call `parse_cnl_canonical` with the text
   `LIF "n1" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0` on unfixed code. Assert that the
   returned document has `canvas.nodes == []` or `canvas is None`. Expected to fail with unfixed
   code producing an empty canvas.

2. **NIR Conv2d gets wrong componentId (Fix 2 exploration)**: Construct a `CanvasProjection`
   with one node dict `{id:"c", nir_type:"nir.Conv2d", componentId:"nir.Conv2d", label:"Conv2d"}`.
   Pass it to `_canvasGraphFromCanonical`. Assert `result.nodes[0].componentId == 'nir.Conv2d'`.
   Expected to fail on unfixed code which produces `componentId == 'lif_population'`.

3. **Error message contains old biological grammar text (Fix 2 exploration)**: Trigger the empty
   canvas error branch in `syncToCanvas()` on unfixed code. Assert the error message contains
   `'lif_population, static_synapse'`. Expected to pass on unfixed code, fail after fix (this
   is a "confirm the old text was there" test, run on unfixed code only).

**Expected Counterexamples (unfixed code)**:
- `parse_cnl_canonical` with NIR-native text → `document.canvas.nodes` is `[]`.
- `_canvasGraphFromCanonical` with `nir.Conv2d` node → canvas node has `componentId='lif_population'`.

---

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed functions produce the
expected behavior.

**Pseudocode (Fix 1):**
```
FOR ALL spec_text WHERE _is_nir_native(spec_text) AND is_valid_nir_cnl(spec_text) DO
  response := parse_cnl_canonical_fixed(spec_text)
  ASSERT response.status_code == 200
  ASSERT len(response.document.canvas.nodes) > 0
  ASSERT all(node has 'nir_type' and 'componentId') for node in response.document.canvas.nodes
END FOR
```

**Pseudocode (Fix 2):**
```
FOR ALL nir_type IN NIR_CANVAS_TYPE_SPECS.keys() DO
  node_dict := {id:"x", nir_type: nir_type, componentId: NIR_CANVAS_TYPE_SPECS[nir_type].component_id, label:"x"}
  graph := _canvasGraphFromCanonical_fixed(projection_with(node_dict))
  ASSERT graph.nodes[0].componentId == NIR_CANVAS_TYPE_SPECS[nir_type].component_id
  ASSERT graph.nodes[0].nirType == nir_type
END FOR
```

---

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed functions
produce the same result as the original.

**Pseudocode (Fix 1 — biological CNL):**
```
FOR ALL spec_text WHERE NOT _is_nir_native(spec_text) DO
  ASSERT parse_cnl_canonical_original(spec_text) == parse_cnl_canonical_fixed(spec_text)
END FOR
```

**Pseudocode (Fix 2 — nir.LIF nodes):**
```
FOR ALL node_dict WHERE node_dict['nir_type'] == 'nir.LIF' OR node_dict has no 'nir_type' DO
  ASSERT _canvasGraphFromCanonical_original(projection) == _canvasGraphFromCanonical_fixed(projection)
END FOR
```

**Testing Approach**: Property-based testing is used for Fix 2 preservation because the space of
`nir_type` values and parameter combinations is large. The PBT generator can pick from the 17
known `nir_type` strings and construct corresponding node dicts. For Fix 1, two concrete
biological CNL examples are sufficient given the deterministic dialect gate.

---

### Unit Tests

**Python (pytest) — `neurocnl/neurosim/tests/test_parse_cnl_canonical_nir.py`:**

- `test_lif_cnl_returns_populated_canvas`: Post minimal LIF CNL; assert HTTP 200, `canvas.nodes`
  length == 1, node has `nir_type == 'nir.LIF'` and `componentId == 'lif_population'`.
- `test_nir_graph_with_edges_returns_edges`: Post two-node NIR CNL with a `Connect` line; assert
  `canvas.edges` length == 1.
- `test_biological_cnl_unchanged`: Post one valid biological CNL spec; assert HTTP 200, verify
  `ir_json` is non-empty (biological path populates IR), `canvas.nodes` is non-empty.
- `test_nir_parse_error_returns_422`: Post NIR CNL with deliberate bad parameter; assert
  HTTP 422 and `response.json()['detail']['message']` is a non-empty string.
- `test_nir_compile_error_returns_422`: Post NIR CNL that compiles to a NIR graph with an
  unsupported structure; assert HTTP 422.

**Dart (flutter test) — `neurocnl/frontend/test/providers/canvas/sync_provider_nir_test.dart`:**

- `test nir.Conv2d node gets correct componentId`: Build a `CanvasProjection` from JSON with one
  node dict `{id:"c1", nir_type:"nir.Conv2d", componentId:"nir.Conv2d", label:"Conv2d"}`, call
  `_canvasGraphFromCanonical`, assert `nodes[0].componentId == 'nir.Conv2d'` and
  `nodes[0].nirType == 'nir.Conv2d'`.
- `test nir.LIF node still gets lif_population`: Same but with `nir_type:'nir.LIF'`; assert
  `componentId == 'lif_population'`.
- `test nir.Input node gets input_node`: Node dict with `nir_type:'nir.Input'`; assert
  `componentId == 'input_node'`.
- `test missing nir_type falls back to nir.LIF`: Node dict without `nir_type`; assert
  `componentId == 'lif_population'` (fallback preserved).
- `test error message does not contain lif_population static_synapse`: Trigger empty canvas
  error path; assert message does NOT contain `'lif_population, static_synapse'`.

---

### Property-Based Tests

**Python (hypothesis) — `test_parse_cnl_canonical_nir.py`:**

- **Property: Any valid NIR-native CNL produces non-empty canvas** (`@given` generates NIR CNL
  strings from a grammar-based strategy; asserts `canvas.nodes` is non-empty). This tests
  Property 1 above.

**Dart (propcheck or manual enumeration) — `sync_provider_nir_test.dart`:**

- **Property: All 17 nir_type strings map to correct componentId** (enumerate over all 17 entries
  in the Dart `_nirTypeToComponentId` map; verify the mapping is consistent with the Python
  serializer's `NIR_CANVAS_TYPE_SPECS` by comparing the expected values). This tests Property 2.

---

### Integration Tests

- **NIR round-trip via canvas**: Load a `.nir` file via `generate-cnl-from-nir` (produces CNL),
  then POST that CNL to `parse-cnl-canonical`, verify `canvas.nodes` matches the original NIR
  graph's node count and `nir_type` values.
- **Biological CNL regression**: Load an existing biological CNL fixture, POST to
  `parse-cnl-canonical`, verify `ir_json` is non-empty and canvas topology matches the expected
  fixture output.
- **Canvas sync E2E (Flutter)**: Widget test that drives `syncToCanvas()` with a mock backend
  returning a NIR-type canvas projection, verifies the canvas provider state is updated with
  the correct `componentId` values.
