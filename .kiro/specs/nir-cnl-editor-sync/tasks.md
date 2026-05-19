# Implementation Plan

## Overview

Fix two bugs that prevent NIR-native CNL from round-tripping through the Studio editor canvas:
**Fix 1** adds a NIR dialect gate to the `parse-cnl-canonical` backend route; **Fix 2** extends
the Dart `CanvasNode` model to surface `nir_type`/`componentId` and updates `sync_provider.dart`
to derive `componentId` from a `_nirTypeToComponentId` lookup instead of hardcoding `lif_population`.

## Task Dependency Graph

```json
{
  "waves": [
    {"wave": 1, "tasks": ["1"]},
    {"wave": 2, "tasks": ["2"]},
    {"wave": 3, "tasks": ["3"]},
    {"wave": 4, "tasks": ["4"]},
    {"wave": 5, "tasks": ["5", "6"]},
    {"wave": 6, "tasks": ["7"]},
    {"wave": 7, "tasks": ["8"]}
  ]
}
```

## Tasks

---

## Exploratory Tests (run on UNFIXED code — both expected to FAIL)

- [ ] 1. Write bug-condition exploration tests
  - **Property 1: Bug Condition** — NIR-native CNL returns empty canvas + Dart hardcodes componentId
  - **CRITICAL**: Write and run BEFORE implementing any fix. FAILURE confirms the bugs exist.
  - **DO NOT** attempt to fix the test or production code when it fails.
  - **GOAL**: Surface concrete counterexamples that prove both root causes.

  - [ ] 1.1 Python exploration — Fix 1 (backend empty-canvas)
    - File: `neurocnl/neurosim/tests/routers/test_parse_cnl_canonical_nir.py` (create)
    - Call `parse_cnl_canonical` directly (use `httpx.AsyncClient` + FastAPI `TestClient`) with
      the payload `{"spec_text": "LIF \"n1\" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0"}`.
    - Assert `response.status_code == 422` OR `response.json()["document"]["canvas"]["nodes"] == []`.
      (Either outcome proves the unfixed code cannot route NIR-native CNL.)
    - Run: `cd neurocnl && python -m pytest neurosim/tests/routers/test_parse_cnl_canonical_nir.py -x`
    - **EXPECTED OUTCOME**: FAILS — counterexample: `canvas.nodes` is `[]` even for valid LIF CNL.
    - Document the exact response body in a comment at the top of the test file.
    - Mark task complete when the test is written, run, and the failure is recorded.
    - _Requirements: 1.1_

  - [ ] 1.2 Dart exploration — Fix 2 (frontend hardcoded componentId)
    - File: `neurocnl/frontend/test/providers/canvas/sync_provider_nir_test.dart` (create)
    - Build a `CanvasProjection` from a raw JSON map containing one node dict:
      `{"id": "c1", "nir_type": "nir.Conv2d", "componentId": "nir.Conv2d", "label": "Conv2d"}`.
    - Call `_canvasGraphFromCanonical(projection, currentGraph: emptyGraph)`.
    - Assert `result.nodes.first.componentId == 'nir.Conv2d'`.
    - **EXPECTED OUTCOME**: FAILS — on unfixed code `componentId` is `'lif_population'`.
    - Also assert `result.nodes.first.nirType == 'nir.Conv2d'` (also fails on unfixed code).
    - Run: `cd neurocnl/frontend && flutter test test/providers/canvas/sync_provider_nir_test.dart`
    - Document counterexample: `componentId='lif_population'` when `nir_type='nir.Conv2d'`.
    - Mark task complete when the test is written, run, and the failure is recorded.
    - _Requirements: 1.3_

---

## Fix 1 — Backend: Add NIR dialect gate to `/parse-cnl-canonical`

- [ ] 2. Fix 1 — `neurocnl/neurosim/app/routers/generation.py`
  - File: `neurocnl/neurosim/app/routers/generation.py`
  - **Done condition**: `parse_cnl_canonical` routes NIR-native CNL through
    `NIR_CNL_Parser → NIR_Compiler → serialize_nir_to_canvas_graph` and returns HTTP 200
    with `canvas.nodes` non-empty. Biological CNL is still routed through `canonical_from_cnl`.

  - [ ] 2.1 Add `_is_nir_native` import
    - Add `from neurocnl.pipeline import _is_nir_native` at the top of `generation.py`.
    - `NIR_CNL_Parser`, `NIR_Compiler`, `serialize_nir_to_canvas_graph`, `CanvasProjection`,
      and `CanonicalEditorDocument` are already imported — do not add duplicate imports.
    - _Bug_Condition: `_is_nir_native(request.spec_text)` is never called in the unfixed router._
    - _Requirements: 2.1_

  - [ ] 2.2 Add dialect gate and NIR execution path inside `parse_cnl_canonical`
    - At the top of the `try` block in `parse_cnl_canonical`, before the `canonical_from_cnl`
      call, add: `if _is_nir_native(request.spec_text): <NIR path>`.
    - NIR path — parse and compile:
      ```python
      records = NIR_CNL_Parser().parse(request.spec_text)
      nir_graph = NIR_Compiler().compile(records)
      canvas_graph = serialize_nir_to_canvas_graph(nir_graph)
      ```
    - NIR path — build projection node dicts (iterate `canvas_graph.nodes`):
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
    - NIR path — wrap and return:
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
    - Catch `ParseError` and `CompileError` in the NIR branch and raise HTTP 422:
      ```python
      except (ParseError, CompileError) as exc:
          raise HTTPException(
              status_code=422,
              detail={"message": str(exc), "unsupported_concepts": []},
          ) from exc
      ```
    - The existing `except Exception` catch-all below continues to cover the biological path.
    - _Bug_Condition: `isBugCondition_Fix1(request)` — NIR-native text routed to `canonical_from_cnl`._
    - _Expected_Behavior: HTTP 200 with `canvas.nodes` non-empty, each node containing `nir_type` and `componentId`._
    - _Preservation: Biological CNL (`_is_nir_native` returns False) still calls `canonical_from_cnl` unchanged._
    - _Requirements: 2.1, 3.1, 3.4_

---

## Fix 2a — Dart model: Surface `nir_type` and `componentId` in `CanvasNode`

- [ ] 3. Fix 2a — `neurocnl/frontend/lib/models/canonical_editor_document.dart`
  - File: `neurocnl/frontend/lib/models/canonical_editor_document.dart`
  - **Done condition**: `CanvasNode.fromJson` reads `nir_type` → `nirType` and `componentId`
    from the raw JSON map; `toJson` round-trips both fields; existing callers that omit
    these keys continue to work (both fields are nullable).

  - [ ] 3.1 Add `nirType` and `componentId` nullable fields to `CanvasNode`
    - Add to the constructor and field declarations:
      ```dart
      final String? nirType;     // json key: 'nir_type'
      final String? componentId; // json key: 'componentId'
      ```
    - Add both to `const CanvasNode({...})` as optional named params.
    - _Bug_Condition: `CanvasNode.fromJson` silently discards `nir_type` and `componentId` keys._
    - _Requirements: 2.2, 2.3, 2.4_

  - [ ] 3.2 Update `CanvasNode.fromJson` to read the new fields
    - Inside `fromJson`:
      ```dart
      nirType: json['nir_type'] as String?,
      componentId: json['componentId'] as String?,
      ```
    - No changes to existing field reads (`id`, `label`, `type`, `size`, `shape`,
      `threshold`, `tau`) — they must remain exactly as-is.
    - _Requirements: 2.2, 2.3, 2.4_

  - [ ] 3.3 Update `CanvasNode.toJson` to conditionally emit the new fields
    - ```dart
      if (nirType != null) 'nir_type': nirType,
      if (componentId != null) 'componentId': componentId,
      ```
    - Run serialization round-trip test: `flutter test test/models_serialization_test.dart`
    - _Requirements: 2.2, 2.4_

---

## Fix 2b — Dart sync provider: Read `nir_type` → `componentId` mapping

- [ ] 4. Fix 2b — `neurocnl/frontend/lib/providers/canvas/sync_provider.dart`
  - File: `neurocnl/frontend/lib/providers/canvas/sync_provider.dart`
  - **Done condition**: `_canvasGraphFromCanonical` derives `componentId` and `nirType` from
    `projection.nodes[index].nirType` via `_nirTypeToComponentId`; nodes with `nirType == null`
    fall back to `'nir.LIF'` / `'lif_population'` (biological-path preservation). Both
    dialect-specific error messages in `syncToCanvas` are replaced with generic ones.

  - [ ] 4.1 Add `_nirTypeToComponentId` constant (top of file, outside any function)
    - ```dart
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
    - _Requirements: 2.2, 2.3, 2.4, 3.5_

  - [ ] 4.2 Replace hardcoded `componentId`/`nirType` in `_canvasGraphFromCanonical`
    - Before the `CanvasNode(...)` constructor call, derive the effective NIR type:
      ```dart
      final rawNirType = projection.nodes[index].nirType ?? 'nir.LIF';
      ```
    - Replace the two hardcoded lines:
      ```dart
      // BEFORE (buggy):
      componentId: 'lif_population',
      nirType: 'nir.LIF',

      // AFTER (fixed):
      componentId: _nirTypeToComponentId[rawNirType] ?? rawNirType,
      nirType: rawNirType,
      ```
    - Unknown `nir_type` values fall back to using the `nir_type` string itself as
      `componentId` — avoids a crash while making unknown types visible in the canvas.
    - No other lines in `_canvasGraphFromCanonical` change.
    - _Bug_Condition: `isBugCondition_Fix2(nodeDict)` — `nir_type != null` and `nir_type != 'nir.LIF'`._
    - _Expected_Behavior: `componentId == NIR_CANVAS_TYPE_SPECS[nir_type].component_id` for all 15 NIR primitives._
    - _Preservation: nodes where `nirType == null` continue to receive `lif_population` (biological path)._
    - _Requirements: 2.2, 2.3, 2.4, 3.5_

  - [ ] 4.3 Replace dialect-specific error messages in `syncToCanvas`
    - Replace the null-document fallback error:
      ```dart
      // BEFORE:
      'CNL parse failed — check that the text uses the canonical '
      'reflex-arc grammar (sensory → motor, lif_population, static_synapse).'

      // AFTER:
      'CNL parse failed — check the editor for syntax errors.'
      ```
    - Replace the empty-canvas error:
      ```dart
      // BEFORE:
      'CNL parsed but produced an empty canvas. '
      'Ensure the text follows the canonical reflex-arc grammar '
      '(sensory → motor, lif_population, static_synapse).'

      // AFTER:
      'CNL parsed but produced an empty canvas. '
      'Check that the text is valid CNL (NIR-native or biological grammar).'
      ```
    - _Requirements: 1.2_

---

## Fix-Checking Tests (run on FIXED code — all expected to PASS)

- [ ] 5. Write fix-checking tests
  - **Property 1: Expected Behavior** — NIR-native CNL produces a populated canvas
  - **IMPORTANT**: Re-run / extend the SAME test files from tasks 1.1 and 1.2 — do NOT
    create separate test files. The exploration tests from task 1 encode the expected
    behavior; when they pass after the fix, the fix is confirmed.

  - [ ] 5.1 Python fix-checking — `neurocnl/neurosim/tests/routers/test_parse_cnl_canonical_nir.py`
    - Extend the file created in task 1.1 with fix-checking test functions:
    - `test_lif_cnl_returns_populated_canvas`:
      - POST `{"spec_text": "LIF \"n1\" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0"}` to
        `parse_cnl_canonical`.
      - Assert `status_code == 200`.
      - Assert `len(document["canvas"]["nodes"]) == 1`.
      - Assert `document["canvas"]["nodes"][0]["nir_type"] == "nir.LIF"`.
      - Assert `document["canvas"]["nodes"][0]["componentId"] == "lif_population"`.
    - `test_nir_graph_with_connect_returns_edges`:
      - POST a two-node NIR CNL (LIF + Connect) to `parse_cnl_canonical`.
      - Assert `len(document["canvas"]["edges"]) == 1`.
    - `test_nir_parse_error_returns_422`:
      - POST NIR CNL with a deliberate bad parameter (e.g. `tau abc`).
      - Assert `status_code == 422` and `response.json()["detail"]["message"]` is non-empty.
    - `test_nir_compile_error_returns_422`:
      - POST NIR CNL with a ghost node reference in `Connect`.
      - Assert `status_code == 422` and `detail.message` is non-empty.
    - Run: `cd neurocnl && python -m pytest neurosim/tests/routers/test_parse_cnl_canonical_nir.py -v`
    - **EXPECTED OUTCOME**: All tests PASS.
    - _Requirements: 2.1, 3.4_

  - [ ] 5.2 Dart fix-checking — `neurocnl/frontend/test/providers/canvas/sync_provider_nir_test.dart`
    - Extend the file created in task 1.2 with fix-checking test functions:
    - `test nir.Conv2d node gets correct componentId`:
      - Build `CanvasProjection` JSON: `[{"id":"c1","nir_type":"nir.Conv2d","componentId":"nir.Conv2d","label":"Conv2d"}]`.
      - Call `_canvasGraphFromCanonical`.
      - Assert `nodes[0].componentId == 'nir.Conv2d'` and `nodes[0].nirType == 'nir.Conv2d'`.
    - `test nir.LIF node still gets lif_population`:
      - Node dict with `nir_type: 'nir.LIF'`.
      - Assert `componentId == 'lif_population'` and `nirType == 'nir.LIF'`.
    - `test nir.Input node gets input_node`:
      - Node dict with `nir_type: 'nir.Input'`.
      - Assert `componentId == 'input_node'`.
    - `test nir.Output node gets output_node`:
      - Node dict with `nir_type: 'nir.Output'`.
      - Assert `componentId == 'output_node'`.
    - `test missing nir_type falls back to lif_population`:
      - Node dict with no `nir_type` key.
      - Assert `componentId == 'lif_population'` (biological-path preservation).
    - Run: `cd neurocnl/frontend && flutter test test/providers/canvas/sync_provider_nir_test.dart`
    - **EXPECTED OUTCOME**: All tests PASS.
    - _Requirements: 2.2, 2.3, 2.4, 3.5_

---

## Preservation / Regression Tests (run on FIXED code — all expected to PASS)

- [ ] 6. Write preservation property tests
  - **Property 2: Preservation** — Biological CNL path and existing node mappings unchanged
  - **IMPORTANT**: Follow the observation-first methodology — observe on UNFIXED code, then
    encode those observations as assertions in the test. Verify tests PASS on unfixed code
    before the fix is applied, then confirm they still pass after the fix.

  - [ ] 6.1 Python preservation — `neurocnl/neurosim/tests/routers/test_parse_cnl_canonical_nir.py`
    - Add to the same file:
    - `test_biological_cnl_unchanged`:
      - POST one valid biological CNL fixture (sensory/motor vocabulary, e.g. a fixture already
        used in `test_generation_canonical.py`) to `parse_cnl_canonical`.
      - Assert `status_code == 200`.
      - Assert `document["ir_json"]` is non-empty (biological path populates `ir_json`).
      - Assert `document["canvas"]["nodes"]` is non-empty.
      - Assert the node count matches the known fixture output (baseline observed on unfixed code).
    - `test_other_endpoints_untouched`:
      - POST a valid `CanvasGraph` to `POST /api/neurosim/generate-cnl`.
      - Assert `status_code == 200` and `cnl_spec` is a non-empty string.
      - This confirms Fix 1 did not disturb `generate_cnl`.
    - Run: `cd neurocnl && python -m pytest neurosim/tests/routers/test_parse_cnl_canonical_nir.py -v`
    - **EXPECTED OUTCOME on unfixed code**: `test_biological_cnl_unchanged` PASSES; `test_other_endpoints_untouched` PASSES.
    - **EXPECTED OUTCOME after fix**: Both still PASS.
    - _Requirements: 3.1, 3.2, 3.3_

  - [ ] 6.2 Dart preservation property test — `neurocnl/frontend/test/providers/canvas/sync_provider_nir_test.dart`
    - **Property 2: Preservation** — All 15 NIR primitives map to correct componentId (enumerate)
    - Add to the same file:
    - `test all 17 nir_type entries map to componentId consistent with NIR_CANVAS_TYPE_SPECS`:
      - Define the expected mapping inline (mirrors `_nirTypeToComponentId` in the provider):
        ```dart
        final expected = {
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
      - For each entry, build a single-node `CanvasProjection` and assert
        `_canvasGraphFromCanonical` produces the expected `componentId`.
      - This test enumerates the full domain of `nir_type` values — equivalent to a
        property-based test over the finite set.
    - `test error message does NOT contain lif_population static_synapse`:
      - Trigger the empty-canvas branch in `syncToCanvas` (mock `canonicalEditorProvider`
        to return a document with `canvas.nodes == []`).
      - Capture the `CanvasSyncIssue.message`.
      - Assert the message does NOT contain `'lif_population, static_synapse'`.
    - Run: `cd neurocnl/frontend && flutter test test/providers/canvas/sync_provider_nir_test.dart`
    - **EXPECTED OUTCOME on unfixed code**: enumeration test FAILS (confirms baseline before fix);
      error-message test FAILS (old text present on unfixed code).
    - **EXPECTED OUTCOME after fix**: Both PASS.
    - _Requirements: 2.2, 2.3, 2.4, 3.5_

  - [ ] 6.3 Dart model serialization regression — `neurocnl/frontend/test/models_serialization_test.dart`
    - The existing `models_serialization_test.dart` covers `CanvasNode` round-tripping.
    - Add two cases to the existing test:
      - `CanvasNode` with `nirType == null`, `componentId == null` (biological node): verify
        `toJson()` omits `nir_type` and `componentId` keys, and `fromJson(toJson())` preserves all other fields.
      - `CanvasNode` with `nirType == 'nir.Conv2d'`, `componentId == 'nir.Conv2d'`: verify
        `toJson()` includes both keys, and `fromJson(toJson())` restores them exactly.
    - Run: `cd neurocnl/frontend && flutter test test/models_serialization_test.dart`
    - **EXPECTED OUTCOME**: PASS.
    - _Requirements: 2.2, 2.4_

---

## Integration Tests

- [ ] 7. Integration tests

  - [ ] 7.1 NIR round-trip integration test — Python
    - File: `neurocnl/neurosim/tests/test_integration.py` (extend existing file)
    - `test_nir_round_trip_via_canvas`:
      - Load a `.nir` fixture file (or use a known NIR graph constructed via the `nir` library).
      - POST its bytes to `POST /api/neurosim/generate-cnl-from-nir`; capture the CNL text.
      - POST that CNL text to `POST /api/neurosim/parse-cnl-canonical`.
      - Assert `status_code == 200`.
      - Assert `len(canvas.nodes) == <expected node count from the fixture>`.
      - Assert each `canvas.nodes[i]["nir_type"]` matches the corresponding node type
        in the original NIR graph.
    - Run: `cd neurocnl && python -m pytest neurosim/tests/test_integration.py::test_nir_round_trip_via_canvas -v`
    - **EXPECTED OUTCOME**: PASS after both Fix 1 and Fix 2 are applied.
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 7.2 Biological CNL regression integration test — Python
    - File: `neurocnl/neurosim/tests/test_integration.py` (extend existing file)
    - `test_biological_cnl_regression`:
      - Load an existing biological CNL fixture from `neurosim/tests/` (one already used in
        `test_generation_canonical.py` or `test_canonical_editor_projection.py`).
      - POST it to `parse-cnl-canonical`.
      - Assert `status_code == 200`, `ir_json` is non-empty, and canvas topology (node count,
        edge count) matches the expected fixture output.
    - Run: `cd neurocnl && python -m pytest neurosim/tests/test_integration.py::test_biological_cnl_regression -v`
    - **EXPECTED OUTCOME**: PASS.
    - _Requirements: 3.1_

  - [ ] 7.3 Canvas sync E2E Flutter widget test
    - File: `neurocnl/frontend/test/integration/nir_three_way_sync_test.dart` (extend existing file)
    - Add a test `'syncToCanvas with NIR-type projection updates canvas with correct componentIds'`:
      - Mock `canonicalEditorProvider` to return a `CanonicalEditorDocument` whose canvas
        contains two nodes: one `nir.LIF` and one `nir.Conv2d`.
      - Call `syncToCanvas()` via the `cnlSpecProvider` notifier.
      - Read `canvasProvider.graph.nodes`.
      - Assert `nodes[0].componentId == 'lif_population'` and `nodes[0].nirType == 'nir.LIF'`.
      - Assert `nodes[1].componentId == 'nir.Conv2d'` and `nodes[1].nirType == 'nir.Conv2d'`.
    - Run: `cd neurocnl/frontend && flutter test test/integration/nir_three_way_sync_test.dart`
    - **EXPECTED OUTCOME**: PASS after Fixes 2a and 2b are applied.
    - _Requirements: 2.2, 2.3, 2.4, 3.5_

---

## Checkpoint

- [ ] 8. Checkpoint — Ensure all tests pass
  - Run full Python test suite: `cd neurocnl && python -m pytest neurosim/tests/ -v`
  - Run full Dart test suite: `cd neurocnl/frontend && flutter test`
  - Confirm zero failures and zero regressions in pre-existing tests.
  - If any test fails unexpectedly, investigate before marking complete.
  - Ask if questions arise.

## Notes

- Tasks 1.1 and 1.2 are intentionally written to FAIL on unfixed code — do not modify them
  to pass until the corresponding fix task is complete.
- Tasks 5.1 / 5.2 extend the same test files created in 1.1 / 1.2; there is no separate
  "fix-checking" file — the exploration tests become the fix-checking tests once the fix passes.
- `_canvasGraphFromCanonical` is a top-level private function in `sync_provider.dart`; it cannot
  be tested directly from outside the package. Use `@visibleForTesting` or test through
  `cnlSpecProvider.notifier.syncToCanvas()` with a mocked `canonicalEditorProvider`.
- The 17-entry `_nirTypeToComponentId` map in Dart must stay in sync with
  `NIR_CANVAS_TYPE_SPECS` in `neurocnl/backend/app/services/nir_graph_serializer.py`;
  if a new NIR primitive is added to the Python serializer it must be added here too.
- Run commands from the `neurocnl/` subdirectory for Python tests and from
  `neurocnl/frontend/` for Dart tests.
