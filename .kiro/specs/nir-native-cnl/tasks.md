# Implementation Plan: NIR-Native CNL (`nir-native-cnl`)

## Overview

Replace the biological reflex-arc CNL system with a NIR-native grammar that directly maps
to all 19 NIR computational primitives. The implementation follows strict dependency order:
core library components first, then array serialisation, then entry-point wiring, then API
rewiring, then deletion of dead code, then property-based and integration tests.

All new code lives under `neurocnl/neurocnl/nir_cnl/`.
All modified entry points are in `neurocnl/neurocnl/pipeline.py` and
`neurocnl/neurocnl/compile.py`.
The API router `neurocnl/neurosim/app/routers/generation.py` is rewired, not rewritten.

---

## Tasks

- [x] 1. Create the `nir_cnl` package skeleton and IR types
  - [x] 1.1 Create `neurocnl/neurocnl/nir_cnl/__init__.py`
    - Create the directory `neurocnl/neurocnl/nir_cnl/` with an empty `__init__.py`
      that re-exports `NIR_Renderer`, `NIR_CNL_Parser`, `NIR_Compiler`, `ParseError`,
      and `CompileError` for convenient top-level imports.
    - Done when `from neurocnl.nir_cnl import NIR_Renderer` resolves without error.
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 1.2 Implement `neurocnl/neurocnl/nir_cnl/ir_types.py`
    - Define `ArraySpec(shape: tuple[int, ...])` dataclass with `slots=True`.
    - Define `NIRNodeRecord(name, nir_type, params, metadata, line)` dataclass
      with `slots=True`; `params` type is `dict[str, Any]` where any value is
      `scalar | ArraySpec | list` (explicit values).
    - Define `NIREdgeRecord(src, dst, line)` dataclass with `slots=True`.
    - No external imports beyond `dataclasses` and `typing`.
    - Done when all three dataclasses are importable and all fields match the design.
    - _Requirements: 3.1, 3.2_

- [x] 2. Implement the grammar module
  - [x] 2.1 Implement `neurocnl/neurocnl/nir_cnl/grammar.py`
    - Define `PRIMITIVE_PARAMS: dict[str, frozenset[str]]` — one entry for each of the
      18 named primitives (`Input`, `Output`, `IF`, `LIF`, `LI`, `CubaLIF`, `CubaLI`,
      `I`, `Linear`, `Affine`, `Scale`, `Conv1d`, `Conv2d`, `AvgPool2d`, `SumPool2d`,
      `Flatten`, `Delay`, `Threshold`) listing every valid parameter name from the NIR
      class constructor (case-sensitive, matching `nir.*` Python class args).
    - Define `ARRAY_PARAMS: dict[str, frozenset[str]]` — subset of `PRIMITIVE_PARAMS`
      keys whose values are numpy arrays (e.g. `weight`, `bias`, `scale`, `kernel`, `tau`,
      `r`, `v_leak`, `v_threshold`, `w_in`, `tau_syn`, `tau_mem`, `threshold`, `delay`
      where applicable per primitive).
    - Define `SENTENCE_PATTERNS: dict[str, re.Pattern]` — one compiled regex per
      primitive keyword; pattern must capture: node name (quoted), all parameter
      key-value pairs, and an optional `WITH metadata { ... }` clause.
    - Define `EDGE_PATTERN: re.Pattern` matching `Connect "<src>" -> "<dst>"`.
    - Define `GRAPH_PATTERN: re.Pattern` matching `NIRGraph "<name>"`.
    - Define `COMMENT_PATTERN: re.Pattern` matching `#` to end of line for stripping
      inline comments before matching.
    - Done when all 18 primitives have entries in `PRIMITIVE_PARAMS` and `SENTENCE_PATTERNS`,
      all patterns compile without error, and `PRIMITIVE_PARAMS["LIF"] == frozenset({"tau",
      "r", "v_leak", "v_threshold"})`.
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 1.7_
  - [x] 2.2 Write unit tests for grammar module
    - `test_all_19_primitives_have_patterns`: assert all 18 primitive names plus
      `NIRGraph` have entries in `SENTENCE_PATTERNS`.
    - `test_primitive_params_lif`: assert `PRIMITIVE_PARAMS["LIF"]` exactly matches
      `{"tau", "r", "v_leak", "v_threshold"}`.
    - `test_edge_pattern_matches`: assert `EDGE_PATTERN` matches
      `'Connect "a" -> "b"'` and captures src=`"a"`, dst=`"b"`.
    - `test_comment_stripped_before_match`: assert a LIF sentence with trailing
      `# inline comment` still matches after comment stripping.
    - _Requirements: 1.1, 1.4, 1.7_

- [x] 3. Implement the NIR_Renderer
  - [x] 3.1 Implement `neurocnl/neurocnl/nir_cnl/renderer.py` — `NIR_Renderer` class
    - `render(graph: nir.NIRGraph) -> str`: iterate `graph.nodes` dict (all node
      sentences first), then `graph.edges` list (all edge sentences after); return
      joined string.
    - `_render_node(name: str, node: nir.NIRNode) -> str`: dispatch on `type(node)`
      to produce the correct NIR-native sentence for each of the 18 primitives.
      - For array parameters: call `node.<param>.tolist()` and format with `%.17g`
        precision; if all elements are equal, emit a single scalar instead of the
        full array (scalar broadcast optimisation per design §5.2).
      - For unsupported node types: return `# unsupported: {type(node).__name__} '{name}'`
        without raising.
    - `_render_edge(src: str, dst: str) -> str`: return `Connect "{src}" -> "{dst}"`.
    - `_render_metadata(metadata: dict) -> str`: emit `WITH metadata { key: value, ... }`
      for str/int/float values only; for non-str/int/float values emit
      `# metadata key '<key>' omitted: unsupported value type` immediately after
      the node sentence.
    - Done when `NIR_Renderer().render(graph)` produces valid CNL text for a minimal
      Input → LIF → Linear → Output graph, all node sentences appear before any
      `Connect` sentence, and an unsupported node type emits a comment not an exception.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.6, 2.7, 7.1, 7.5_
  - [x] 3.2 Write unit tests for NIR_Renderer
    - One render test per primitive: construct the minimal `nir.*` node, call
      `_render_node`, assert the sentence begins with the correct keyword and includes
      all structural parameters by name.
    - `test_render_nodes_before_edges`: build a 3-node graph, assert every non-comment
      line before the first `Connect` sentence is a node sentence.
    - `test_unsupported_node_emits_comment`: pass a subclass of `nir.NIRNode` not in
      the 18 primitives; assert the returned string starts with `# unsupported:`.
    - `test_metadata_str_int_float_emitted`: node with `metadata={"a": "x", "b": 2,
      "c": 0.5}`; assert `WITH metadata { a: "x", b: 2, c: 0.5 }` appears in output.
    - `test_metadata_unsupported_type_emits_comment`: node with
      `metadata={"hist": [1, 2, 3]}`; assert comment line with `omitted: unsupported
      value type` appears; `WITH metadata` clause is absent.
    - _Requirements: 2.2, 2.3, 2.4, 2.7, 7.1, 7.5_

- [x] 4. Implement the NIR_CNL_Parser
  - [x] 4.1 Define `ParseError` exception in `neurocnl/neurocnl/nir_cnl/parser.py`
    - `ParseError(Exception)` with `errors: list[dict]` attribute; each dict has keys
      `code`, `message`, `line`, `raw`, `hint`.
    - Done when `ParseError(errors=[...])` is constructable and `exc.errors` is a list.
    - _Requirements: 6.1_
  - [x] 4.2 Implement `NIR_CNL_Parser.parse(text: str)` in `neurocnl/neurocnl/nir_cnl/parser.py`
    - Line-by-line scan: strip inline comments (using `COMMENT_PATTERN`), skip blank
      lines and lines starting with `#`.
    - For each substantive line: try each pattern in `SENTENCE_PATTERNS` then
      `EDGE_PATTERN` then `GRAPH_PATTERN`.
    - On a node match: extract node name, nir_type, and all key-value pairs; for each
      param name verify it is in `PRIMITIVE_PARAMS[nir_type]` — if not, accumulate a
      `ParseError` entry with `code="unknown_parameter"` and `hint` listing valid names.
    - Parse parameter values: scalar (float/int), shape-only `shape (d0, d1, ...)` →
      `ArraySpec`, inline bracket list `[...]` or `[[...], ...]` → nested Python list
      (passed to `numpy.asarray` in compiler).
    - Parse optional `WITH metadata { key: value, ... }` clause from the same line.
    - On an edge match: produce `NIREdgeRecord`.
    - On no match: accumulate `ParseError` entry with `code="syntax_error"`.
    - After scanning all lines: if any errors accumulated, raise `ParseError(errors=...)`
      with the complete list — do NOT return partial IR.
    - Otherwise return `list[NIRNodeRecord | NIREdgeRecord]`.
    - Done when: parsing the §4.11 example CNL produces 6 `NIRNodeRecord` + 5
      `NIREdgeRecord` with no errors; a sentence with an unknown param raises
      `ParseError` with `code="unknown_parameter"`; two bad lines in the same input
      produce a `ParseError` with exactly 2 entries in `errors`.
    - _Requirements: 1.4, 1.5, 1.6, 3.1, 3.2, 3.3, 6.1, 6.6, 7.2_
  - [x] 4.3 Write unit tests for NIR_CNL_Parser
    - `test_parse_lif_scalar`: `LIF "n" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0`;
      assert one `NIRNodeRecord` with `nir_type="LIF"` and `params["tau"] == 0.02`.
    - `test_parse_linear_shape_only`: `Linear "fc" weight shape (128, 784)`; assert
      `params["weight"] == ArraySpec(shape=(128, 784))`.
    - `test_parse_linear_explicit_values`: `Linear "fc" weight [[0.5, -0.3], [0.1, 0.9]]`;
      assert `params["weight"]` is a list that `numpy.asarray` reconstructs to shape `(2, 2)`.
    - `test_parse_edge`: `Connect "a" -> "b"`; assert `NIREdgeRecord(src="a", dst="b")`.
    - `test_parse_unknown_param_raises`: `LIF "n" tau_xyz 0.02`; assert `ParseError` with
      `errors[0]["code"] == "unknown_parameter"` and `"tau"` appears in `errors[0]["hint"]`.
    - `test_two_bad_lines_both_collected`: two non-matching lines; assert `len(errors) == 2`.
    - `test_metadata_clause_parsed`: sentence with `WITH metadata { rp: 0.002, src: "x" }`;
      assert `record.metadata == {"rp": 0.002, "src": "x"}`.
    - _Requirements: 1.4, 3.1, 3.2, 3.3, 6.1, 6.6, 7.2_

- [x] 5. Implement the NIR_Compiler
  - [x] 5.1 Implement `NIR_Compiler.compile(records)` in `neurocnl/neurocnl/nir_cnl/compiler.py`
    - Validate ghost nodes: for every `NIREdgeRecord`, assert `src` and `dst` are both
      in the set of `NIRNodeRecord.name` values; raise `CompileError(stage="materializer",
      code="ghost_node")` if not.
    - Validate duplicate edges: assert no `(src, dst)` pair appears twice; raise
      `CompileError(code="duplicate_edge")` if so.
    - Validate endpoints: assert at least one `NIRNodeRecord` has `nir_type="Input"` and
      at least one has `nir_type="Output"`; raise `CompileError(code="missing_endpoint")`
      if not.
    - For each `NIRNodeRecord`: call `_build_nir_node(record)` to construct the `nir.*`
      object.
    - Assemble and return `nir.NIRGraph(nodes={...}, edges=[...])`.
    - Reuse the existing `CompileError` and `Diagnostic` classes from
      `neurocnl/neurocnl/compile.py` — do not define new ones.
    - Done when: compiling the §4.11 example records produces a `nir.NIRGraph` with 6
      nodes and 5 edges; a ghost-node record raises `CompileError` with
      `code="ghost_node"`; no Input record raises `CompileError` with
      `code="missing_endpoint"`.
    - _Requirements: 3.4, 3.5, 6.3, 6.4, 6.5_
  - [x] 5.2 Implement `NIR_Compiler._build_nir_node(record: NIRNodeRecord) -> nir.NIRNode`
    - For each primitive: construct the correct `nir.*` class with positional/keyword
      arguments derived from `record.params`.
    - Scalar params: pass as `float` or `int` directly.
    - `ArraySpec` params: synthesize `numpy.zeros(shape, dtype=float)` — raise
      `CompileError(code="missing_shape")` if an array-bearing primitive provides neither
      value nor shape; raise `CompileError(code="invalid_shape")` if any dimension ≤ 0.
    - Explicit list params: call `numpy.asarray(values, dtype=np.float64)`.
    - Bias auto-derivation for `Conv2d` and `Affine` when weight is shape-only: bias
      shape is `(weight.shape[0],)` — synthesize `numpy.zeros((M,), dtype=float)`.
    - Metadata: store `record.metadata` in `node.metadata` after construction.
    - Done when `_build_nir_node` for every one of the 18 primitives produces the correct
      `nir.*` type; `Linear` with `ArraySpec(shape=(128, 784))` produces a node whose
      `weight.shape == (128, 784)` and `weight.dtype == float64`; `Linear` with no weight
      raises `CompileError(code="missing_shape")`.
    - _Requirements: 3.6, 3.7, 7.3, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
  - [x] 5.3 Write unit tests for NIR_Compiler
    - `test_ghost_node_raises`: record set with edge to undeclared node; assert
      `CompileError` with `code="ghost_node"`.
    - `test_duplicate_edge_raises`: two identical `NIREdgeRecord`s; assert `CompileError`
      with `code="duplicate_edge"`.
    - `test_missing_endpoint_raises`: records with no `Input`; assert `CompileError`
      with `code="missing_endpoint"`.
    - `test_missing_shape_raises`: `Linear` record with `params={}` (no weight); assert
      `CompileError` with `code="missing_shape"`.
    - `test_invalid_shape_raises`: `Linear` record with `weight shape (0, 128)`; assert
      `CompileError` with `code="invalid_shape"`.
    - `test_affine_bias_auto_derived`: `Affine` with `weight shape (4, 3)`; assert
      compiled node has `bias.shape == (4,)` and `numpy.all(bias == 0)`.
    - `test_conv2d_bias_auto_derived`: `Conv2d` with `weight shape (16, 1, 5, 5)`;
      assert compiled node has `bias.shape == (16,)`.
    - `test_metadata_stored_on_node`: record with `metadata={"rp": 0.002}`; assert
      compiled `nir.NIRNode.metadata["rp"] == 0.002`.
    - _Requirements: 3.4, 3.5, 3.7, 7.3, 8.1–8.6_

- [x] 6. Checkpoint — core components
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -k "nir_cnl" -x` from `neurocnl/`.
    Ensure all unit tests added in tasks 2–5 pass. Ask the user before proceeding
    if any test fails.

- [x] 7. Array serialisation — full float64 round-trip for weight-bearing primitives
  - [x] 7.1 Extend `NIR_Renderer._render_node` array formatting
    - For 1-D arrays: format as `[v0, v1, ..., vN]` using `"%.17g" % v` per element.
    - For 2-D arrays: format as `[[r0c0, r0c1, ...], [r1c0, ...]]` using `tolist()` +
      Python default `repr` (which gives exact float64 decimal strings).
    - For ≥3-D arrays (e.g. Conv2d kernel): use nested bracket lists following
      `ndarray.tolist()` recursively.
    - Scalar broadcast: if `numpy.all(arr == arr.flat[0])` emit single scalar value
      instead of full array; the compiler must broadcast it back via
      `numpy.full(shape, scalar, dtype=float64)` — implement that broadcast in
      `_build_nir_node`.
    - Done when a `nir.Linear` node with a `(4, 3)` weight matrix of random float64
      values survives `render → parse → compile` with `numpy.array_equal(original, recovered)`.
    - _Requirements: 2.5, 4.2, 4.3, 4.4_
  - [x] 7.2 Write unit tests for array serialisation
    - `test_1d_array_roundtrip`: random float64 vector of length 8; assert element-wise
      equality after render → parse → compile.
    - `test_2d_weight_roundtrip`: random `(4, 3)` float64 matrix; assert
      `numpy.array_equal` after round-trip.
    - `test_conv2d_kernel_roundtrip`: random `(2, 1, 3, 3)` float64 kernel; assert
      shape and values preserved after round-trip.
    - `test_scalar_broadcast`: all-equal array `[0.02, 0.02, 0.02]`; assert rendered
      sentence contains `tau 0.02` (scalar, not bracket list); assert compiled node has
      a 1-D array of correct shape filled with `0.02`.
    - _Requirements: 2.5, 4.2, 4.3, 4.4_

- [x] 8. Rewire `neurocnl/neurocnl/pipeline.py`
  - [x] 8.1 Rewrite `generate_cnl_from_nir()` in `neurocnl/neurocnl/pipeline.py`
    - Remove the existing body (calls to `nir_import_diagnostics`, `import_ir_from_nir`,
      `render_cnl_document`).
    - New body: instantiate `NIR_Renderer` from `neurocnl.nir_cnl.renderer` and return
      `renderer.render(graph)`.
    - Remove the import of `NirImportError` used only by the old implementation —
      but keep `NirImportError` and `NirImportDiagnostic` defined in this file because
      `generation.py` still imports them for HTTP error shaping (they will be removed
      in task 10 when `generation.py` is rewired).
    - Done when `generate_cnl_from_nir(graph)` on a `nir.LIF`-containing graph returns
      NIR-native CNL starting with `LIF` and not containing `threshold_firing` or
      `refractory_period`.
    - _Requirements: 2.1, 9.1, 9.2_
  - [x] 8.2 Rewrite `parse_spec_text()` in `neurocnl/neurocnl/pipeline.py`
    - Add helper `_is_nir_native(text: str) -> bool`: find the first non-empty,
      non-comment line; return `True` if it starts with any of the 18 primitive names,
      `Connect`, or `NIRGraph`.
    - Add helper `_parse_nir_native(text: str) -> list[ParseResult]`: call
      `NIR_CNL_Parser().parse(text)` and convert each `NIRNodeRecord`/`NIREdgeRecord`
      to `ParseResult` with `concept` equal to the primitive name (e.g. `"LIF"`,
      `"Conv2d"`, `"Connect"`); wrap any `ParseError` as `valid=False` entries.
    - In `parse_spec_text`: if `_is_nir_native(spec_text)` return
      `_parse_nir_native(spec_text)`; otherwise fall through to the existing biological
      parser path (kept for legacy during transition).
    - Done when `parse_spec_text("LIF \"n\" tau 0.02, r 1.0, v_leak 0.0, v_threshold
      1.0")` returns a list where `result[0]["parsed"]["concept"] == "LIF"`.
    - _Requirements: 9.2_
  - [x] 8.3 Write unit tests for updated pipeline entry points
    - `test_generate_cnl_from_nir_returns_nir_native`: minimal LIF graph; assert output
      contains `LIF` keyword and does not contain `MUST`, `sensory`, `motor`,
      `threshold_firing`, or `refractory_period`.
    - `test_parse_spec_text_nir_native_dispatch`: NIR-native CNL input; assert
      `results[0]["parsed"]["concept"]` is a NIR primitive name.
    - `test_parse_spec_text_biological_fallback`: input starting with `The network MUST`;
      assert the old biological path is used (result concept is `"lif_population"` or
      similar, not a NIR keyword).
    - _Requirements: 9.1, 9.2_

- [x] 9. Rewire `neurocnl/neurocnl/compile.py`
  - [x] 9.1 Rewrite `compile_to_nir()` in `neurocnl/neurocnl/compile.py` for NIR-native path
    - At the top of the function, after stage 1 parse, detect NIR-native input using
      `_is_nir_native(spec)` (import the helper from `pipeline`).
    - NIR-native path (new stages 1–4):
      - Stage 1: call `NIR_CNL_Parser().parse(spec)` directly; wrap any `ParseError`
        entries into `Diagnostic(stage="parse", ...)` objects and raise `CompileError`
        with the full list.
      - Stage 2: skip `ensure_nir_exportable` entirely (NIR_CNL_Parser enforces
        supported primitives by construction).
      - Stage 3: parser output is already `list[NIRNodeRecord | NIREdgeRecord]` — no
        `lower_to_ir` call.
      - Stage 4: call `NIR_Compiler().compile(records)`; map any `CompileError` raised
        by the compiler directly (re-raise as-is since it already carries `Diagnostic`s).
    - Biological legacy path: unchanged (existing stages 1–4 remain for non-NIR-native
      input).
    - Stage 5 (write to disk): unchanged for both paths.
    - Done when `compile_to_nir("Input \"x\" shape (2,)\nLIF \"n\" tau 0.02, r 1.0,
      v_leak 0.0, v_threshold 1.0\nOutput \"y\" shape (2,)\nConnect \"x\" -> \"n\"
      \nConnect \"n\" -> \"y\"")` returns a `nir.NIRGraph` with nodes `x`, `n`, `y`.
    - _Requirements: 3.3, 3.4, 3.5, 9.3, 9.4_
  - [x] 9.2 Write unit tests for `compile_to_nir` NIR-native path
    - `test_compile_nir_native_minimal`: minimal Input/LIF/Output CNL; assert returned
      `nir.NIRGraph` has correct node names and types.
    - `test_compile_nir_native_with_shape`: `Linear "fc" weight shape (4, 3)`; assert
      compiled node has `weight.shape == (4, 3)` and `numpy.all(weight == 0)`.
    - `test_compile_nir_native_parse_error_raises_compile_error`: bad CNL line; assert
      `CompileError` with `diagnostics[0].stage == "parse"`.
    - `test_compile_nir_native_ghost_node_raises`: CNL with edge to undeclared node;
      assert `CompileError` with `diagnostics[0].code == "ghost_node"`.
    - _Requirements: 3.3–3.5, 9.3_

- [x] 10. Checkpoint — entry points
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -x` from `neurocnl/`. Ensure all tests
    pass including the pre-existing test suite. Ask the user before proceeding if
    any test fails.

- [x] 11. Rewire `neurocnl/neurosim/app/routers/generation.py`
  - [x] 11.1 Update the `/generate-cnl-from-nir` route body
    - Route function `generate_cnl_from_uploaded_nir` currently catches `NirImportError`.
    - The new `generate_cnl_from_nir()` (after task 8.1) no longer raises
      `NirImportError` for supported primitives — the renderer emits comments instead.
    - Update the except block: catch any `Exception` for malformed `.nir` files and
      return HTTP 422 with `code="invalid_nir_file"`. If the rendered CNL text contains
      any `# unsupported:` lines, parse them out and return HTTP 422 with
      `code="unsupported_nir_import"` and a populated `diagnostics` array per design §8.4.
    - Done when POST of a `.nir` file with only supported primitives returns 200 with
      NIR-native CNL; POST of a `.nir` with an unsupported node type returns 422 with
      `diagnostics` array.
    - _Requirements: 5.1, 5.4_
  - [x] 11.2 Update the `/generate-cnl` route body
    - Remove the `if ... graph_to_canvas_canonical_cnl(graph)` branch.
    - All graphs now go through `generate_cnl_from_nir(deserialize_canvas_graph(graph))`
      unconditionally.
    - Remove the `CanonicalCanvasSyncError` import and its except clause (source file
      `neurocnl_bridge.py` will be deleted in task 12).
    - Done when POST with a CanvasGraph whose nodes have `nir_type` set returns
      NIR-native CNL; POST with a graph without `nir_type` also goes through the
      NIR_Renderer path.
    - _Requirements: 5.2_
  - [x] 11.3 Update the `/parse-cnl` route body
    - Remove the `build_neurosim_handoff_spec` call and `NeurosimHandoffRejectedError`
      except clause.
    - New body: call `NIR_CNL_Parser().parse(payload.cnl_spec)`, then
      `NIR_Compiler().compile(records)`, then
      `serialize_nir_to_canvas_graph(graph)` from `nir_graph_serializer`.
    - On `ParseError` or `CompileError`: return HTTP 422 with
      `{"message": "CNL parse failed: N errors.", "unsupported_concepts": []}`.
    - Done when POST of the §4.11 example CNL text returns a `CanvasGraph` with 6
      nodes and 5 edges.
    - _Requirements: 5.3_
  - [x] 11.4 Update the `/parse-cnl-canonical` route body
    - Replace `canonical_from_cnl` error message referencing
      `"canonical reflex-arc grammar (sensory → motor, lif_population, static_synapse)"`
      with a generic `"CNL parsed but produced an empty canvas."`.
    - Done when the route no longer contains the biological grammar description in any
      error message string.
    - _Requirements: 5.3, 9.1_

- [x] 12. Delete biological grammar files and test files
  - [x] 12.1 Delete service files replaced by the NIR_Renderer
    - Delete `neurocnl/neurosim/app/services/graph_to_cnl.py`
    - Delete `neurocnl/neurosim/app/services/neurocnl_bridge.py`
    - Delete `neurocnl/neurosim/app/services/semantic_cnl.py`
    - Done when all three files are absent and `ruff check neurocnl/` reports no
      `ImportError` or `F401` for these modules.
    - _Requirements: 9.1_
  - [x] 12.2 Delete biological parser and grammar files
    - Delete `neurocnl/neurocnl/cnl/cnl_parser.py`
    - Delete `neurocnl/neurocnl/cnl/cnl_grammar.md`
    - Done when files are absent. Verify that `pipeline.py` no longer imports
      from `neurocnl.cnl.cnl_parser` (the import was removed in task 8.2).
    - _Requirements: 9.1_
  - [x] 12.3 Delete the biological sample CNL file
    - Delete `neurocnl/neurocnl/simulation/reflex_arc.cnl`
    - Done when file is absent and no test or source file imports or reads it by path.
    - _Requirements: 9.1_
  - [x] 12.4 Delete biological parser test files
    - Delete `neurocnl/neurocnl/cnl/test_cnl_parser.py`
    - Delete `neurocnl/neurocnl/cnl/test_adaptive_spiking_parser.py`
    - Delete `neurocnl/neurocnl/cnl/test_background_noise_parser.py`
    - Delete `neurocnl/neurocnl/cnl/test_receptor_dynamics_parser.py`
    - Delete `neurocnl/neurocnl/cnl/test_short_term_plasticity_parser.py`
    - Delete `neurocnl/neurocnl/cnl/test_spatial_connectivity_parser.py`
    - Done when all six files are absent and `pytest --collect-only` does not list them.
    - _Requirements: 9.1_

- [x] 13. Checkpoint — post-deletion
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -x` and `ruff check neurocnl/` from
    `neurocnl/`. Confirm no broken imports and no test collection errors. Ask the
    user before proceeding if anything fails.

- [x] 14. Property-based tests
  - [x] 14.1 Create Hypothesis strategies in `neurocnl/neurocnl/tests/properties/test_nir_native_cnl_properties.py`
    - Implement `nir_graphs()` composite strategy: always include exactly one `Input` and
      one `Output` node; randomly select 0–4 intermediate nodes from supported types;
      edges form a valid DAG from Input to Output; all array params use float64.
    - Implement `lif_params()` composite: random float64 values for `tau`, `r`,
      `v_leak`, `v_threshold`.
    - Implement `weight_matrices()` composite: random shape `(M, N)` with M, N ∈ [1, 32];
      float64 values.
    - Implement `metadata_dicts()` composite: random dicts with str/int/float values only;
      string values max 1024 chars; 0–5 keys.
    - Implement `valid_shapes()` composite: random tuples of 1–4 positive integers each
      in [1, 16].
    - Implement `valid_conv2d_shapes()` composite: 4-tuples `(out_ch, in_ch, kH, kW)`
      with positive integer dimensions.
    - Done when all strategies are importable and `nir_graphs().example()` returns a
      `nir.NIRGraph` without error.
    - _Requirements: 2.5, 3.4, 4.1_
  - [x] 14.2 Write property test — Property 1: Full Round-Trip Identity
    - `# Feature: nir-native-cnl, Property 1: Full round-trip identity`
    - `@given(graph=nir_graphs()) @settings(max_examples=200)`
    - `test_round_trip_identity(graph)`: render → parse → compile; assert node key set
      identical, node types identical, scalar params equal within float64 precision,
      array params bitwise-equal (`numpy.array_equal`), edge set identical.
    - _Requirements: 2.5, 3.4, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 9.4_
  - [x] 14.3 Write property test — Property 2: Metadata Round-Trip Preservation
    - `# Feature: nir-native-cnl, Property 2: Metadata round-trip preservation`
    - `@given(node_type=sampled_from(SUPPORTED_PRIMITIVES), meta=metadata_dicts())`
    - `@settings(max_examples=200)`
    - `test_metadata_round_trip(node_type, meta)`: build minimal graph with metadata on
      the intermediate node; render → parse → compile; assert every key and value in
      `meta` survives exactly in the compiled `nir.NIRNode.metadata`.
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - [x] 14.4 Write property test — Property 3: Node-Sentence Before Edge-Sentence
    - `# Feature: nir-native-cnl, Property 3: Node sentences before edge sentences`
    - `@given(graph=nir_graphs()) @settings(max_examples=200)`
    - `test_node_sentences_before_edge_sentences(graph)`: assert
      `max(node_line_indices) < min(edge_line_indices)` for all non-comment lines.
    - _Requirements: 2.7_
  - [x] 14.5 Write property test — Property 4: Shape-Only Compilation Produces Zeros
    - `# Feature: nir-native-cnl, Property 4: Shape-only produces zeros array`
    - `@given(shape=valid_shapes()) @settings(max_examples=200)`
    - Build a minimal Input/Linear/Output CNL with `weight shape {shape}`; compile;
      assert `weight.shape == shape`, `numpy.all(weight == 0.0)`,
      `weight.dtype == numpy.float64`.
    - _Requirements: 3.6, 8.1, 8.2_
  - [x] 14.6 Write property test — Property 5: Bias Shape Derived from Out-Channels
    - `# Feature: nir-native-cnl, Property 5: Bias shape derived from weight out-channels`
    - `@given(shape=valid_conv2d_shapes()) @settings(max_examples=200)`
    - Build Conv2d-containing CNL with shape-only weight; compile; assert
      `node.bias.shape == (shape[0],)`.
    - _Requirements: 8.3, 8.4_
  - [x] 14.7 Write property test — Property 6: No Biological Vocabulary in Rendered CNL
    - `# Feature: nir-native-cnl, Property 6: No biological vocabulary in rendered CNL`
    - `@given(graph=nir_graphs()) @settings(max_examples=200)`
    - Call `generate_cnl_from_nir(graph)`; assert no word in
      `{"MUST", "MUST NOT", "sensory", "motor", "threshold_firing", "refractory_period"}`
      appears as a standalone token in the output.
    - _Requirements: 9.1_
  - [x] 14.8 Write property test — Property 7: Unknown Parameter Name Rejected
    - `# Feature: nir-native-cnl, Property 7: Unknown parameter name rejected`
    - `@given(primitive=sampled_from(list(PRIMITIVE_PARAMS.keys())), bad_param=text(...))`
    - Build a sentence with the bad param name; assert `ParseError` is raised with at
      least one entry where `code == "unknown_parameter"` and the `hint` lists valid
      params for that primitive.
    - _Requirements: 1.4, 6.6_
  - [x] 14.9 Write property test — Property 8: All Parse Errors Collected Before Failing
    - `# Feature: nir-native-cnl, Property 8: All parse errors collected before failing`
    - `@given(invalid_lines=lists(text().filter(lambda s: not _matches_any_grammar(s)), min_size=1))`
    - Assert `len(exc.value.errors) == len(invalid_lines)` after joining with `\n`.
    - _Requirements: 3.3, 6.2_

- [x] 15. Unit / example tests for all 18 primitives and error paths
  - [x] 15.1 Write per-primitive round-trip examples in `neurocnl/neurocnl/tests/test_nir_native_cnl.py`
    - One `test_roundtrip_<primitive>` function for each of the 18 primitives: construct
      a minimal graph containing that primitive between Input and Output; render → parse
      → compile; assert node names, node type, and all structural params preserved.
    - `test_unsupported_node_emits_comment`: renderer receives a custom subclass not in
      the 18 primitives; assert rendered text contains `# unsupported:`.
    - `test_ghost_node_raises_compile_error`: CNL with `Connect "x" -> "missing"` where
      `missing` is never declared; assert `CompileError` with `code="ghost_node"`.
    - `test_duplicate_edge_raises_compile_error`: two `Connect "a" -> "b"` lines; assert
      `CompileError` with `code="duplicate_edge"`.
    - `test_missing_endpoint_raises_compile_error`: CNL with no `Input` node; assert
      `CompileError` with `code="missing_endpoint"`.
    - `test_missing_shape_raises_compile_error`: `Linear "fc"` with no weight and no
      shape; assert `CompileError` with `code="missing_shape"`.
    - `test_invalid_shape_raises_compile_error`: `weight shape (0, 128)`; assert
      `CompileError` with `code="invalid_shape"`.
    - `test_metadata_unsupported_type_emits_comment`: `metadata={"x": [1, 2, 3]}`; assert
      renderer output contains `# metadata key 'x' omitted: unsupported value type`.
    - Done when all 18 + 8 test functions pass.
    - _Requirements: 2.2, 2.4, 3.4, 3.5, 4.1, 6.3–6.5, 7.5, 8.5, 8.6_

- [x] 16. Integration tests
  - [x] 16.1 Write API integration tests in `neurocnl/neurocnl/tests/test_nir_native_cnl_integration.py`
    - `test_generate_cnl_from_nir_endpoint`: write a minimal `nir.NIRGraph` to a temp
      `.nir` file; POST raw bytes to `/api/neurosim/generate-cnl-from-nir`; assert HTTP
      200 and `cnl_text` contains NIR-native keywords.
    - `test_parse_cnl_endpoint`: POST the §4.11 example CNL text to `/api/neurosim/parse-cnl`;
      assert HTTP 200 and the returned `CanvasGraph` has 6 nodes and 5 edges.
    - `test_generate_cnl_endpoint`: POST a `CanvasGraph` with `nir_type` values set to
      `/api/neurosim/generate-cnl`; assert HTTP 200 and `cnl_spec` starts with a NIR
      primitive keyword.
    - `test_422_on_unsupported_nir_type`: POST a `.nir` file containing a custom node
      type to `/api/neurosim/generate-cnl-from-nir`; assert HTTP 422 and
      `response.json()["diagnostics"]` is a non-empty list.
    - Done when all four integration tests pass against a running test server instance.
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 17. Final checkpoint — full test suite
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -v` and `ruff check neurocnl/` from
    `neurocnl/`. Ensure all tests pass, no stale imports exist, and `mypy neurocnl/`
    reports no new type errors introduced by this feature. Ask the user before
    closing if anything fails.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; remove `*`
  if test coverage is required before merging.
- Every task references specific files from the design's component map — there are no
  vague "implement X" tasks without a target file.
- The deletion tasks (12.1–12.4) must come after the entry-point rewiring (tasks 8–11)
  so that nothing references the deleted modules at the time of deletion.
- `CompileError` and `Diagnostic` from `neurocnl/neurocnl/compile.py` are reused by the
  NIR_Compiler — do not define new exception classes.
- The biological parser path in `pipeline.py` and `compile.py` is kept during transition
  and removed only after all routes have been confirmed working on the NIR-native path.
- Array serialisation (task 7) depends on tasks 3 and 4 being complete.
- Property tests (task 14) depend on tasks 3, 4, and 5 being complete.
- Integration tests (task 16) depend on tasks 8, 9, and 11 being complete.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1", "4.1"] },
    { "id": 3, "tasks": ["3.2", "4.2"] },
    { "id": 4, "tasks": ["4.3", "5.1"] },
    { "id": 5, "tasks": ["5.2"] },
    { "id": 6, "tasks": ["5.3", "7.1"] },
    { "id": 7, "tasks": ["7.2", "8.1", "8.2"] },
    { "id": 8, "tasks": ["8.3", "9.1"] },
    { "id": 9, "tasks": ["9.2", "11.1", "11.2", "11.3", "11.4"] },
    { "id": 10, "tasks": ["12.1", "12.2", "12.3", "12.4"] },
    { "id": 11, "tasks": ["14.1"] },
    { "id": 12, "tasks": ["14.2", "14.3", "14.4", "14.5", "14.6", "14.7", "14.8", "14.9"] },
    { "id": 13, "tasks": ["15.1"] },
    { "id": 14, "tasks": ["16.1"] }
  ]
}
```

---

## Phase 2: Component Manifests and Network Templates

These tasks create the component JSON files and canvas network templates that the Studio needs to render, display, and scaffold NIR-native graphs in the UI. They are independent of phases 1–17 above and can be done in any order relative to each other.

---

- [ ] 18. Create NIR component manifests for transforms and convolutions
  - The components system in `neurocnl/neurosim/app/services/components.py` reads JSON files
    from `neurocnl/neurosim/components/` recursively. New files here appear in the
    `/api/neurosim/components` endpoint automatically.
  - Create a new subdirectory: `neurocnl/neurosim/components/nir/`
  - Done when `load_components()` returns all 11 new component IDs without error.

  - [ ] 18.1 Create `neurocnl/neurosim/components/nir/nir_linear.json`
    - `id`: `"nir.Linear"`, `name`: `"Linear"`, `category`: `"Transforms"`,
      `description`: `"Dense linear transformation (weight matrix)."`, `icon`: `"grid_on"`
    - Parameters: `rows` (int, default 1, label "Output features"), `cols` (int, default 1,
      label "Input features"), `weight_fill` (float, default 0.0, label "Weight fill value")
    - Ports: `in` (input), `out` (output)
    - `cnl_template`: `'Linear "{name}" weight shape ({rows}, {cols})'`
    - Done when `load_components()["nir.Linear"]` exists and has the correct template.
    - _Requirements: 1.1, 4.4_

  - [ ] 18.2 Create `neurocnl/neurosim/components/nir/nir_affine.json`
    - `id`: `"nir.Affine"`, `category`: `"Transforms"`
    - Parameters: `rows`, `cols`, `weight_fill` (same as Linear)
    - `cnl_template`: `'Affine "{name}" weight shape ({rows}, {cols})'`
    - Done when `load_components()["nir.Affine"]` is registered.
    - _Requirements: 1.1, 4.4_

  - [ ] 18.3 Create `neurocnl/neurosim/components/nir/nir_scale.json`
    - `id`: `"nir.Scale"`, `category`: `"Transforms"`
    - Parameters: `scale_fill` (float, default 1.0, label "Scale value")
    - `cnl_template`: `'Scale "{name}" scale {scale_fill}'`
    - Done when `load_components()["nir.Scale"]` is registered.
    - _Requirements: 1.1_

  - [ ] 18.4 Create `neurocnl/neurosim/components/nir/nir_conv1d.json`
    - `id`: `"nir.Conv1d"`, `category`: `"Convolutions"`
    - Parameters: `out_channels` (int, default 16), `in_channels` (int, default 1),
      `kernel_size` (int, default 3), `stride` (int, default 1), `padding` (int, default 0),
      `dilation` (int, default 1), `groups` (int, default 1)
    - `cnl_template`: `'Conv1d "{name}" weight shape ({out_channels}, {in_channels}, {kernel_size}), stride {stride}, padding {padding}, dilation {dilation}, groups {groups}'`
    - Done when `load_components()["nir.Conv1d"]` is registered.
    - _Requirements: 1.1, 4.3_

  - [ ] 18.5 Create `neurocnl/neurosim/components/nir/nir_conv2d.json`
    - `id`: `"nir.Conv2d"`, `category`: `"Convolutions"`
    - Parameters: `out_channels` (int, default 16), `in_channels` (int, default 1),
      `kernel_h` (int, default 3), `kernel_w` (int, default 3), `stride_h` (int, default 1),
      `stride_w` (int, default 1), `padding_h` (int, default 0), `padding_w` (int, default 0),
      `dilation_h` (int, default 1), `dilation_w` (int, default 1), `groups` (int, default 1),
      `input_h` (int, default 28), `input_w` (int, default 28)
    - `cnl_template`: `'Conv2d "{name}" weight shape ({out_channels}, {in_channels}, {kernel_h}, {kernel_w}), stride ({stride_h}, {stride_w}), padding ({padding_h}, {padding_w}), dilation ({dilation_h}, {dilation_w}), groups {groups}, input_shape ({input_h}, {input_w})'`
    - Done when `load_components()["nir.Conv2d"]` is registered.
    - _Requirements: 1.1, 4.3_

  - [ ] 18.6 Create `neurocnl/neurosim/components/nir/nir_avgpool2d.json`
    - `id`: `"nir.AvgPool2d"`, `category`: `"Pooling"`
    - Parameters: `kernel_h` (int, default 2), `kernel_w` (int, default 2),
      `stride_h` (int, default 2), `stride_w` (int, default 2),
      `padding_h` (int, default 0), `padding_w` (int, default 0)
    - `cnl_template`: `'AvgPool2d "{name}" kernel_size ({kernel_h}, {kernel_w}), stride ({stride_h}, {stride_w}), padding ({padding_h}, {padding_w})'`
    - Done when `load_components()["nir.AvgPool2d"]` is registered.
    - _Requirements: 1.1_

  - [ ] 18.7 Create `neurocnl/neurosim/components/nir/nir_sumpool2d.json`
    - Same schema as AvgPool2d but `id`: `"nir.SumPool2d"`, `name`: `"SumPool2d"`,
      `description`: `"2D sum pooling."`
    - `cnl_template`: `'SumPool2d "{name}" kernel_size ({kernel_h}, {kernel_w}), stride ({stride_h}, {stride_w}), padding ({padding_h}, {padding_w})'`
    - Done when `load_components()["nir.SumPool2d"]` is registered.
    - _Requirements: 1.1_

  - [ ] 18.8 Create `neurocnl/neurosim/components/nir/nir_flatten.json`
    - `id`: `"nir.Flatten"`, `category`: `"Utility"`
    - Parameters: `start_dim` (int, default 1), `end_dim` (int, default -1)
    - `cnl_template`: `'Flatten "{name}" start_dim {start_dim}, end_dim {end_dim}'`
    - Done when `load_components()["nir.Flatten"]` is registered.
    - _Requirements: 1.1, 4.5_

  - [ ] 18.9 Create `neurocnl/neurosim/components/nir/nir_delay.json`
    - `id`: `"nir.Delay"`, `category`: `"Utility"`
    - Parameters: `delay` (float, default 0.001, unit "s", label "Delay (seconds)")
    - `cnl_template`: `'Delay "{name}" delay {delay}'`
    - Done when `load_components()["nir.Delay"]` is registered.
    - _Requirements: 1.1, 4.6_

  - [ ] 18.10 Create `neurocnl/neurosim/components/nir/nir_if.json`
    - `id`: `"nir.IF"` (the IF neuron — Integrate-and-Fire without leak), `category`: `"Neurons"`
    - Parameters: `n_neurons` (int, default 100), `r` (float, default 1.0, label "Resistance"),
      `v_threshold` (float, default 1.0, label "Spike threshold")
    - `cnl_template`: `'IF "{name}" r {r}, v_threshold {v_threshold}'`
    - Done when `load_components()["nir.IF"]` is registered.
    - _Requirements: 1.1_

  - [ ] 18.11 Create `neurocnl/neurosim/components/nir/nir_cuba_lif.json`
    - `id`: `"nir.CubaLIF"`, `category`: `"Neurons"`
    - Parameters: `n_neurons` (int, default 100), `tau_syn` (float, default 0.01, unit "s"),
      `tau_mem` (float, default 0.02, unit "s"), `r` (float, default 1.0),
      `v_leak` (float, default 0.0), `v_threshold` (float, default 1.0)
    - `cnl_template`: `'CubaLIF "{name}" tau_syn {tau_syn}, tau_mem {tau_mem}, r {r}, v_leak {v_leak}, v_threshold {v_threshold}'`
    - Done when `load_components()["nir.CubaLIF"]` is registered.
    - _Requirements: 1.1_

- [ ] 19. Write unit tests for new component manifests
  - File: `neurocnl/neurosim/tests/test_nir_components.py` (create)
  - `test_all_11_nir_components_load`: call `load_components()` and assert all of
    `["nir.Linear", "nir.Affine", "nir.Scale", "nir.Conv1d", "nir.Conv2d",
      "nir.AvgPool2d", "nir.SumPool2d", "nir.Flatten", "nir.Delay", "nir.IF", "nir.CubaLIF"]`
    are present in the returned dict.
  - `test_conv2d_cnl_template_produces_valid_nir_native_cnl`: format the `nir.Conv2d`
    template with default parameter values; pass the result through `NIR_CNL_Parser().parse()`;
    assert no `ParseError` is raised and the single record has `nir_type == "Conv2d"`.
  - `test_linear_cnl_template_produces_valid_nir_native_cnl`: same for `nir.Linear`.
  - Done when all three tests pass.
  - _Requirements: 1.1, 1.4_

- [ ] 20. Create NIR-native network templates
  - Canvas templates live in `neurocnl/neurosim/templates/` as JSON files. They must
    use the new `nir_type` and `component_id` fields that `nir_graph_serializer.py` expects.
  - Done when all three template files exist, are valid JSON, and the `/api/neurosim/templates`
    endpoint returns them.

  - [ ] 20.1 Create `neurocnl/neurosim/templates/mnist_snn.json`
    - Template name: `"MNIST Spiking CNN"`, id: `"mnist_snn"`
    - Description: `"3-layer spiking CNN for MNIST: Conv2d → CubaLIF → Flatten → Linear → Output"`
    - `cnl_spec`: NIR-native CNL text for the full network:
      ```
      NIRGraph "mnist_snn"

      Input "pixels" shape (1, 28, 28)
      Conv2d "conv1" weight shape (16, 1, 5, 5), stride (1, 1), padding (2, 2), dilation (1, 1), groups 1, input_shape (28, 28)
      CubaLIF "lif0" tau_syn 0.01, tau_mem 0.02, r 1.0, v_leak 0.0, v_threshold 1.0
      Flatten "flat1" start_dim 1, end_dim -1
      Linear "fc1" weight shape (10, 12544)
      Output "logits" shape (10,)

      Connect "pixels" -> "conv1"
      Connect "conv1" -> "lif0"
      Connect "lif0" -> "flat1"
      Connect "flat1" -> "fc1"
      Connect "fc1" -> "logits"
      ```
    - `graph.nodes`: 6 nodes with correct `nir_type` and `component_id` values matching
      `NIR_CANVAS_TYPE_SPECS`; positions spread horizontally at 240px increments.
    - `graph.edges`: 5 edges connecting the 6 nodes in order.
    - `graph.metadata`: `{"graph_kind": "nir", "layout": "linear"}`
    - Done when the template appears in `GET /api/neurosim/templates` and its `cnl_spec`
      can be parsed by `NIR_CNL_Parser().parse()` without error.
    - _Requirements: 1.1, 4.1, 4.3, 4.4_

  - [ ] 20.2 Create `neurocnl/neurosim/templates/lif_feedforward.json`
    - Template name: `"LIF Feedforward"`, id: `"lif_feedforward"`
    - Description: `"Minimal feedforward SNN: Input → Linear → LIF → Output"`
    - `cnl_spec`:
      ```
      NIRGraph "lif_feedforward"

      Input "input" shape (784,)
      Linear "fc1" weight shape (128, 784)
      LIF "lif1" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0
      Linear "fc2" weight shape (10, 128)
      Output "output" shape (10,)

      Connect "input" -> "fc1"
      Connect "fc1" -> "lif1"
      Connect "lif1" -> "fc2"
      Connect "fc2" -> "output"
      ```
    - 5 nodes, 4 edges, `graph_kind: "nir"`.
    - Done when parseable and returns from `/api/neurosim/templates`.
    - _Requirements: 1.1, 4.2_

  - [ ] 20.3 Create `neurocnl/neurosim/templates/delay_network.json`
    - Template name: `"Delayed Spiking Circuit"`, id: `"delay_network"`
    - Description: `"LIF network with axonal delay demonstrating NIR Delay nodes."`
    - `cnl_spec`:
      ```
      NIRGraph "delay_network"

      Input "stimulus" shape (10,)
      LIF "neurons" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0
      Delay "axon" delay 0.005
      Linear "readout" weight shape (4, 10)
      Output "spikes" shape (4,)

      Connect "stimulus" -> "neurons"
      Connect "neurons" -> "axon"
      Connect "axon" -> "readout"
      Connect "readout" -> "spikes"
      ```
    - Done when parseable and returns from `/api/neurosim/templates`.
    - _Requirements: 1.1, 4.6_

- [ ] 21. Write unit tests for new templates
  - File: `neurocnl/neurosim/tests/test_nir_templates.py` (create)
  - `test_all_3_nir_templates_load`: call the templates endpoint (or load files directly)
    and assert `"mnist_snn"`, `"lif_feedforward"`, `"delay_network"` are present.
  - `test_mnist_snn_cnl_is_parseable`: take `cnl_spec` from `mnist_snn.json`, run
    `NIR_CNL_Parser().parse()`, assert 6 `NIRNodeRecord`s and 5 `NIREdgeRecord`s.
  - `test_lif_feedforward_cnl_is_parseable`: same for `lif_feedforward` (5 nodes, 4 edges).
  - `test_delay_network_cnl_is_parseable`: same for `delay_network` (5 nodes, 4 edges).
  - `test_template_graph_kind_is_nir`: assert `graph.metadata["graph_kind"] == "nir"` for
    each of the three templates.
  - Done when all five tests pass.
  - _Requirements: 1.1, 5.3_
