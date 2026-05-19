# Implementation Plan: NIR-Native Controlled Natural Language

## Overview

Convert the feature design into a series of prompts for a code-generation
LLM that will implement each step with incremental progress. Make sure
that each prompt builds on the previous prompts, and ends with wiring
things together. There should be no hanging or orphaned code that isn't
integrated into a previous step. Focus ONLY on tasks that involve
writing, modifying, or testing code.

The plan is ordered so that the legacy structured-DSL implementation is
deleted or rewritten **before** any new natural-language code is built.
This order is required: leaving the legacy modules in place while the new
parser/renderer is constructed would leave existing tests passing on the
old surface and silently regress the new one.

## Tasks

- [x] 1. Inventory and remove legacy grammar implementations
  - [x] 1.1 Scan the repository for forbidden tokens
    - Write `neurocnl/neurocnl/tests/nir_native_cnl/test_static_repo_invariants.py` (new file) that walks every `.py` under `neurocnl/neurocnl/` and `neurocnl/neurosim/`, parses each module's AST, and asserts that no module's source — outside string literals and outside lines that start with `#` — contains any of the Biological_Grammar keywords (`sensory`, `motor`, `MUST`, `MUST NOT`, `threshold_firing`, `refractory_period`, `STDP`) or any Structured_DSL_Token form (quoted node identifier adjacent to a Primitive keyword, `->`/`→`/`=>` arrow between identifiers, bare comma-separated `<key> <value>` pair without an English connective).
    - Run the test now (it MUST fail) and capture the file list it reports as the legacy-removal manifest for tasks 1.2–1.5.
    - _Requirements: 8.6, 8.7_

  - [x] 1.2 Delete legacy nir_cnl grammar module and tests that target it
    - Delete `neurocnl/neurocnl/nir_cnl/grammar.py` (structured-DSL `SENTENCE_PATTERNS`, `EDGE_PATTERN`, `GRAPH_PATTERN` for `Connect "x" -> "y"`).
    - Delete `neurocnl/neurocnl/tests/test_nir_native_cnl.py` and `neurocnl/neurocnl/tests/test_nir_native_cnl_integration.py` (both pin the structured-DSL surface and the biological-keyword denylist).
    - Delete `neurocnl/neurocnl/tests/properties/test_nir_native_cnl_properties.py` (property tests on the structured-DSL form).
    - _Requirements: 8.6, 8.7_

  - [x] 1.3 Delete legacy biological-grammar parser and its dependents
    - Delete `neurocnl/neurocnl/cnl/_bio_cnl_parser.py` (the biological reflex-arc CNL parser).
    - Edit `neurocnl/neurocnl/pipeline.py`: remove the `_NIR_NATIVE_KEYWORDS` set, remove `_is_nir_native`, remove the legacy biological branch in `parse_spec_text`, and remove every `from neurocnl.cnl._bio_cnl_parser import ...`.
    - Edit `neurocnl/neurocnl/compile.py`: remove the entire `else:` branch (legacy biological path) and remove `from neurocnl.pipeline import _is_nir_native, parse_spec_text`.
    - _Requirements: 8.3, 8.4, 8.6_

  - [x] 1.4 Remove or rewrite tests that exclusively exercise the biological grammar
    - Edit `neurocnl/neurocnl/generation/test_nengo_generator.py`: delete every test that imports `_bio_cnl_parser`. If a test mixes biological CNL with downstream IR assertions and the IR contract is independent of the parser, replace the parser call with a direct IR-construction call; otherwise delete the test.
    - Edit `neurocnl/neurocnl/ir/test_ir_lowering.py`: same pattern.
    - Edit `neurocnl/neurocnl/layers/test_layer1_validator.py`: same pattern.
    - Edit `neurocnl/neurocnl/test_planner.py`: same pattern.
    - Edit `neurocnl/neurocnl/tests/properties/test_physics_properties.py`: same pattern.
    - _Requirements: 8.6, 8.7_

  - [x] 1.5 Sweep neurosim manifests, templates, and demo specs for forbidden tokens
    - Search every file under `neurocnl/neurosim/` (manifests, templates, examples) and every `.cnl` file under `neurocnl/demos/` for Structured_DSL_Tokens and Biological_Grammar keywords appearing outside string literals.
    - For each match: rewrite the file using the new `Define <noun phrase> named <id> with ...` and `Connect <src> to <target>.` forms — or, if the file existed solely to exercise the legacy grammar, delete it.
    - Re-run the static-scan test from task 1.1; it MUST now report zero matches.
    - _Requirements: 8.6, 8.7_

- [x] 2. Build the grammar tables (data-only foundation)
  - [x] 2.1 Create the grammar tables module
    - Create `neurocnl/neurocnl/nir_cnl/grammar_tables.py` (new file).
    - Define `primitive_phrases: dict[str, str]` with the 18 entries from the design document's English-to-Primitive mapping table.
    - Define `noun_phrase_to_primitive: dict[str, str]` as the inverse mapping (case-insensitive lookup keys).
    - Define `parameter_phrases: dict[str, dict[str, ParamSpec]]` covering every constructor argument of every Primitive listed in the design document's parameter-phrase mapping table; each `ParamSpec` carries the canonical English phrase, the value kind (`scalar`, `vector`, `tensor`, `int_tuple`, `int_scalar`), the rank, and whether the parameter has a default.
    - Define `keyword_set: frozenset[str]` containing `{"Define", "Create", "named", "with", "and", "Connect", "to", "network", "annotated", "metadata", "equal", "shape"}`.
    - Define `forbidden_biological_keywords: frozenset[str]` containing the seven Biological_Grammar tokens.
    - Define `structured_dsl_token_patterns: list[re.Pattern]` for the four Structured_DSL_Token forms.
    - Module imports nothing beyond the standard library so it loads at import time without `numpy` or `nir`.
    - _Requirements: 1.2, 1.5, 1.10, 8.1, 8.2_

  - [ ]* 2.2 Write property test for grammar table coverage
    - **Property 6 partial: every Primitive has exactly one canonical noun phrase**
    - Test that `set(primitive_phrases.keys())` equals exactly `{"Input", "Output", "IF", "LIF", "LI", "CubaLIF", "CubaLI", "I", "Linear", "Affine", "Scale", "Conv1d", "Conv2d", "AvgPool2d", "SumPool2d", "Flatten", "Delay", "Threshold"}`; assert `len(set(primitive_phrases.values())) == 18` (no duplicate phrases); assert `parameter_phrases.keys() == primitive_phrases.keys()`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_grammar_tables.py`
    - **Validates: Requirements 1.2, 2.1**

- [x] 3. Define intermediate-record types and shared error types
  - [x] 3.1 Rewrite ir_types.py for the new record set
    - Rewrite `neurocnl/neurocnl/nir_cnl/ir_types.py` (replace contents).
    - Define `ArraySpec(shape: tuple[int, ...])` and `ArrayValues(shape: tuple[int, ...], values: tuple[float, ...])` both `frozen=True, slots=True`.
    - Define `NIRNodeRecord(name, primitive, params, metadata, line)` with `params: dict[str, int | float | ArraySpec | ArrayValues | tuple[int, ...]]` and `metadata: dict[str, str | int | float]`.
    - Define `NIREdgeRecord(src, target, line)`.
    - Define `NetworkContainer(name, line)`.
    - The module imports only from `dataclasses` and `typing`.
    - _Requirements: 4.1, 11.1, 1.7_

  - [x] 3.2 Create the errors module
    - Create `neurocnl/neurocnl/nir_cnl/errors.py` (new file).
    - Define `Diagnostic(code, message, line, raw, hint, stage)` as a slots dataclass; `stage ∈ {"parser", "materializer", "validator"}`.
    - Define `ParseError(Exception)` carrying `errors: list[Diagnostic]`; `__init__` accepts the list and builds a concise summary message.
    - Define `RenderError(Exception)` carrying `code: str` and `offending_token: str`.
    - Re-export `CompileError` and `Diagnostic` from `neurocnl.compile` so the codebase has exactly one `CompileError` class.
    - _Requirements: 9.1, 9.2_

- [x] 4. Build the legacy-token validator
  - [x] 4.1 Create the validator module
    - Create `neurocnl/neurocnl/nir_cnl/validator.py` (new file).
    - Define `scan_for_legacy_tokens(text: str) -> list[Diagnostic]` that finds every Structured_DSL_Token and every Biological_Grammar keyword outside double-quoted string literals and outside `#`-prefixed comment lines.
    - Diagnostic codes are `"structured_dsl_token"` or `"legacy_grammar"`; each diagnostic has `stage="validator"`, the offending line number, the offending token in `raw`, and a `hint` naming the offending form.
    - _Requirements: 1.8, 8.4, 8.5_

  - [ ]* 4.2 Write property test: parser rejects every legacy-grammar input
    - **Property 3: Parser rejects every legacy-grammar input**
    - Generate input strings that splice a Biological_Grammar keyword OR a Structured_DSL_Token into otherwise-valid (or empty) NL_Sentence prose, randomly choosing positions; assert `NIR_CNL_Parser().parse(text)` raises `ParseError` with at least one diagnostic whose `code` is `"structured_dsl_token"` or `"legacy_grammar"`, and `compile_to_nir(text)` raises `CompileError` whose diagnostics include `code="legacy_grammar"`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_legacy_token_properties.py`
    - **Validates: Requirements 1.8, 8.3, 8.4**

- [x] 5. Build the renderer
  - [x] 5.1 Implement core node and edge rendering
    - Rewrite `neurocnl/neurocnl/nir_cnl/renderer.py` (replace contents).
    - Implement `NIR_Renderer.render(graph) -> str` that iterates `graph.nodes` and `graph.edges`, dispatches on `type(node)` to per-Primitive emitter functions, emits one node sentence per node and one edge sentence per edge, and assembles the text with `"\n".join(...) + "\n"`.
    - Implement helpers `_format_scalar(v)` (uses `repr(float(v))`), `_format_array_shape(arr)`, `_format_array_values(arr)`, and `_format_int_tuple(t)`.
    - Implement per-Primitive emitter functions for every Primitive listed in the design's parameter-phrase mapping table; each emitter looks up the canonical noun phrase from `primitive_phrases` and the parameter phrases from `parameter_phrases[primitive]`.
    - Choose `Define an` vs `Define a` based on whether the noun phrase begins with a vowel letter (case-insensitive on the first letter).
    - Join parameter clauses with commas and `, and` (or `and ` when there are exactly two clauses) per Requirement 1.4.
    - _Requirements: 2.1, 3.1, 3.2, 3.3, 3.4_

  - [x] 5.2 Implement array-bearing parameter rendering for round-trip identity
    - In `renderer.py`, for every Primitive whose Round-Trip identity is asserted by Requirements 5.5–5.10, emit array-bearing parameters as the two-clause form `<phrase> shape (d1, ..., dN)` plus `<phrase> values (v1, ..., vM)` with values in C-order and each value formatted by `repr(float(v))`.
    - Handle the 1-D `(N,)` trailing-comma convention; handle the rank-0 case as a single scalar.
    - _Requirements: 2.4, 2.5, 5.5, 5.6, 5.7, 5.13_

  - [x] 5.3 Implement metadata rendering and unsupported-node fall-through
    - In `renderer.py`, render every node's `metadata` dict in ascending lexicographic order of keys: each entry whose value is `str | int | float (finite)` becomes one `annotated with metadata <key> equal to <value>` clause appended to the parameter list; each entry whose value is unsupported emits a `# metadata <key> on <node_name> omitted: unsupported value type` comment line on its own line immediately after the node sentence.
    - For nodes whose type is not one of the 18 Primitives, emit a `# unsupported node type <T> for node <name>` line in place of the node sentence and continue.
    - For edges referencing unsupported or absent endpoints, emit `# unsupported edge from <src> to <target>` and continue.
    - _Requirements: 3.5, 3.6, 3.7, 10.1, 10.5_

  - [x] 5.4 Wire the renderer to the legacy-token validator
    - In `renderer.py`, before returning the assembled text, call `scan_for_legacy_tokens(text)`; if any diagnostic is produced, raise `RenderError(code="legacy_grammar_emission", offending_token=...)` and return no partial output.
    - _Requirements: 8.5_

  - [ ]* 5.5 Write per-Primitive snapshot tests for the renderer
    - For each of the 18 Primitives, build a known instance with deterministic parameter values, render, and assert the output equals the canonical sentence in the design's parameter-phrase mapping table.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_renderer_examples.py`
    - _Requirements: 2.1, 3.4_

  - [ ]* 5.6 Write property test: renderer never emits legacy-grammar tokens
    - **Property 2: Renderer never emits legacy-grammar tokens**
    - Generate random `nir.NIRGraph` instances over the 18 Primitives via the shared `nir_graph_strategy()` Hypothesis generator; render; assert `scan_for_legacy_tokens(text)` returns an empty diagnostic list.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_legacy_token_properties.py`
    - **Validates: Requirements 3.8, 8.1, 8.2, 8.5**

  - [ ]* 5.7 Write property test: rendered sentences satisfy structural shape
    - **Property 6: Sentence structural shape**
    - Generate random graphs; render; assert each NL_Sentence is ≤ 1024 characters and ≤ 64 whitespace tokens; assert connective placement (commas + final `and`); assert one sentence per node and one per edge; assert all node sentences precede all edge sentences in source order.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_round_trip_properties.py`
    - **Validates: Requirements 1.1, 1.4, 3.1, 3.2, 3.4**

- [ ] 6. Build the parser
  - [x] 6.1 Implement tokenization and sentence splitting
    - Rewrite `neurocnl/neurocnl/nir_cnl/parser.py` (replace contents).
    - Implement `_tokenize(text) -> list[Token]` that strips `#`-prefixed comment lines and splits the remainder into tokens (English words, identifiers, numeric literals, parenthesised tuple literals, double-quoted strings, periods).
    - Implement `_split_sentences(tokens) -> list[list[Token]]` that splits the token stream on `.` tokens.
    - _Requirements: 1.1, 1.9_

  - [x] 6.2 Implement node-declaration sentence parsing
    - In `parser.py`, implement `_parse_node_sentence(tokens) -> NIRNodeRecord` that:
      - matches `(?i)(define|create) (a|an)` as the verb phrase;
      - greedily consumes the longest noun phrase from `noun_phrase_to_primitive` (case-insensitive), raising `ParseError(code="unknown_primitive_phrase", hint=<sorted list of valid phrases>)` on mismatch;
      - parses `named <identifier>` validating the identifier regex `[A-Za-z_][A-Za-z0-9_]*` and length ≤ 64, raising `ParseError(code="invalid_identifier")` on mismatch;
      - parses optional `with <param-clause>{, <param-clause>}* [, and <param-clause>]` clauses, looking up each `<english_parameter_phrase>` against `parameter_phrases[primitive]`;
      - parses each parameter value as scalar, shape literal, parenthesised int tuple, or double-quoted string per the value-kind in the parameter-phrase table;
      - parses any number of trailing `annotated with metadata <key> equal to <value>` clauses into the record's metadata dict, raising `ParseError(code="duplicate_metadata_key")` on byte-equal duplicate keys.
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 1.10, 1.11, 1.12, 10.2, 10.6_

  - [x] 6.3 Implement edge and network-container sentence parsing
    - In `parser.py`, implement `_parse_edge_sentence(tokens) -> NIREdgeRecord` matching `(?i)Connect <src> to <target>` with both identifiers validated against the regex.
    - Implement `_parse_network_sentence(tokens) -> NetworkContainer` matching `(?i)Define a network named <id>` (and the `Create a` synonym).
    - _Requirements: 1.6, 1.7_

  - [x] 6.4 Implement diagnostic accumulation and duplicate-identifier detection
    - In `parser.py`, implement `NIR_CNL_Parser.parse(text) -> list[NIRNodeRecord | NIREdgeRecord | NetworkContainer]` that calls the legacy-token validator first, then iterates sentences accumulating diagnostics.
    - On any node sentence, check whether the identifier is already declared in the same network container; if so, append a `Diagnostic(code="duplicate_identifier", ...)` and skip the record.
    - When the diagnostics list is non-empty after processing all sentences, raise `ParseError(errors=...)`.
    - Cap the diagnostic list at 10,000 entries; sort by `line` ascending with ties broken by occurrence order.
    - _Requirements: 1.13, 9.1, 9.3, 9.4_

  - [ ]* 6.5 Write property test: comments and case toggling are parse-output-invariant
    - **Property 4: Comments and keyword casing are parse-output-invariant**
    - Generate valid CNL texts via render-from-graph; insert random `# ...` lines at random positions and randomly toggle the case of any subset of the 12 case-insensitive keywords; assert `parse(transformed) == parse(original)` under structural record equality.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_round_trip_properties.py`
    - **Validates: Requirements 1.9, 1.10**

  - [ ]* 6.6 Write property test: identifier round-trip preservation
    - **Property 5: Identifier round-trip preservation**
    - Generate identifier strings matching `[A-Za-z_][A-Za-z0-9_]*` of length 1–64; embed each in a minimal valid graph; render; parse; assert each round-tripped identifier is byte-equal to the original.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_round_trip_properties.py`
    - **Validates: Requirements 1.3, 3.3**

  - [ ]* 6.7 Write property test: unknown phrase and duplicate identifier diagnostics
    - **Property 7: Unknown phrases and duplicate identifiers raise documented diagnostics**
    - Generate strings that are NOT in `primitive_phrases.values()`; assert `unknown_primitive_phrase` is raised. Generate parameter phrases that are NOT in `parameter_phrases[primitive].values()`; assert `unknown_parameter_phrase` is raised with `hint` equal to the alphabetised list. Generate pairs of node sentences sharing an identifier; assert `duplicate_identifier` is raised.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_diagnostic_properties.py`
    - **Validates: Requirements 1.11, 1.12, 1.13, 4.8, 9.5, 9.6**

- [x] 7. Checkpoint — run static scan and parser/renderer tests
  - Run `PYTHONPATH=. pytest neurocnl/neurocnl/tests/nir_native_cnl/ -q`; ensure the static-scan test from task 1.1 reports zero forbidden tokens, the grammar-table coverage test passes, and the renderer/parser property tests pass. Ensure all tests pass, ask the user if questions arise.

- [ ] 8. Build the compiler
  - [x] 8.1 Implement structural validation passes
    - Rewrite `neurocnl/neurocnl/nir_cnl/compiler.py` (replace contents).
    - Implement `NIR_Compiler.compile(records) -> nir.NIRGraph` that runs validation phases in order: ghost nodes (`code="ghost_node"`), duplicate edges (`code="duplicate_edge"`), missing endpoints (`code="missing_endpoint"`).
    - Each phase collects all diagnostics for the phase before deciding whether to raise; on raise, downstream phases do not run; on raise, no `nir.NIRGraph` is constructed.
    - _Requirements: 4.5, 4.6, 4.7_

  - [x] 8.2 Implement parameter materialization for scalar and array kinds
    - In `compiler.py`, implement per-Primitive builder functions that:
      - resolve `ArraySpec` to `numpy.zeros(shape, dtype=float)` (Dummy_Array);
      - resolve `ArrayValues` to `numpy.asarray(values, dtype=float).reshape(shape)`;
      - resolve scalar parameters as Python `int`/`float` and broadcast to the correct shape where the `nir.*` constructor expects an array;
      - resolve `int_tuple` structural parameters (`stride`, `padding`, `dilation`, `input_shape`, `kernel_size`) as `numpy.asarray(values, dtype=int)` or plain int tuples per the `nir.*` constructor signature;
      - validate `ArraySpec.shape` against the documented rank and the `[1, 4096]` dim range; raise `CompileError(code="shape_rank_mismatch")` or `code="invalid_shape"` on mismatch;
      - raise `CompileError(code="shape_for_scalar")` if a scalar param is supplied as `ArraySpec`;
      - raise `CompileError(code="missing_required_parameter")` for required-no-default args;
      - raise `CompileError(code="missing_shape")` for required array params with no clause.
    - _Requirements: 2.6, 2.7, 2.8, 2.9, 2.10, 11.1, 11.6, 11.7, 11.8_

  - [x] 8.3 Implement Affine and Conv2d auto-bias derivation
    - In `compiler.py`, when an `Affine` or `Conv2d` record has a `weight` clause and no `bias` clause, derive `bias = numpy.zeros((weight.shape[0],), dtype=float)`.
    - When the record has both clauses, use the explicit bias; never let auto-derivation override it.
    - _Requirements: 11.2, 11.3, 11.4, 11.5_

  - [x] 8.4 Wire metadata into materialized nodes
    - In `compiler.py`, after constructing each `nir.*` node, set `node.metadata = dict(record.metadata)` preserving Python types as parsed.
    - _Requirements: 10.3, 10.4_

  - [ ]* 8.5 Write property test: structural validation
    - **Property 8: Compile-time structural validation**
    - Generate record lists violating exactly one of `ghost_node`, `duplicate_edge`, `missing_endpoint`, `missing_required_parameter`, `missing_shape`, `shape_rank_mismatch`, `shape_for_scalar`; assert `CompileError` is raised with the expected `code`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_diagnostic_properties.py`
    - **Validates: Requirements 2.6, 2.9, 2.10, 4.5, 4.6, 4.7, 11.6, 11.8**

  - [ ]* 8.6 Write property test: shape literals compile to numpy.zeros
    - **Property 9: Shape literal compiles to numpy.zeros(shape, dtype=float)**
    - Generate shape tuples of rank 1–4 with each dim in `[1, 4096]`; build minimal node sentences using the `<phrase> shape (...)` form with no values clause; compile; assert the materialized array equals `numpy.zeros(shape, dtype=float)` element-wise. Generate invalid shape tuples (negative, zero, fractional, non-numeric) and assert parser raises `invalid_shape`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_shape_properties.py`
    - **Validates: Requirements 2.4, 2.5, 2.7, 2.8, 4.3, 4.9, 11.1, 11.7**

  - [ ]* 8.7 Write property test: auto-bias derivation
    - **Property 10: Auto-bias derivation for Affine and Conv2d**
    - For random `Affine` and `Conv2d` weight shapes, generate sentences with weight-only and weight+bias clauses; compile; assert the resulting bias array equals `numpy.zeros((out_channels,), dtype=float)` in the weight-only case and equals the explicit bias in the weight+bias case.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_shape_properties.py`
    - **Validates: Requirements 11.2, 11.3, 11.4, 11.5**

- [x] 9. Wire the new package public surface
  - [x] 9.1 Rewrite the package __init__.py
    - Rewrite `neurocnl/neurocnl/nir_cnl/__init__.py` to re-export `NIR_Renderer`, `NIR_CNL_Parser`, `NIR_Compiler`, `ParseError`, `RenderError`, `CompileError`, `Diagnostic`, plus the public types `NIRNodeRecord`, `NIREdgeRecord`, `NetworkContainer`, `ArraySpec`, `ArrayValues`.
    - Remove the legacy `try/except ImportError` deferred-import scaffolding.
    - _Requirements: 8.6_

  - [x] 9.2 Rewire `compile_to_nir` and pipeline entry points
    - Edit `neurocnl/neurocnl/compile.py`: the function becomes single-path: call `scan_for_legacy_tokens(spec)` first (raising `CompileError(code="legacy_grammar")` on any match), then call `NIR_CNL_Parser().parse(spec)`, then call `NIR_Compiler().compile(records)`, then optionally write to `save_to`.
    - Edit `neurocnl/neurocnl/pipeline.py`: replace `parse_spec_text` with a thin adapter that calls `NIR_CNL_Parser().parse(spec_text)` and converts records to the `ParseResult` TypedDict shape; replace `generate_cnl_from_nir` with a one-liner that calls `NIR_Renderer().render(graph)`.
    - _Requirements: 8.3, 8.4, 7.1, 7.3_

- [x] 10. Rewire the API router
  - [x] 10.1 Update generation router endpoints
    - Edit `neurocnl/neurosim/app/routers/generation.py`:
      - `/api/neurosim/generate-cnl-from-nir` reads up to 10 MB of `.nir` bytes, calls `nir.read`, calls `NIR_Renderer().render`, and returns CNL text. On 18-Primitive-violation, return HTTP 422 with one diagnostic entry per offending node. On invalid `.nir` binary, return HTTP 400.
      - `/api/neurosim/generate-cnl` validates payload size ≤ 10 MB, calls `deserialize_canvas_graph(graph)` exactly once (no helper wrapper), calls `NIR_Renderer().render`, and returns the result.
      - `/api/neurosim/parse-cnl` validates payload size ≤ 1 MB and UTF-8 decoding, calls `NIR_CNL_Parser().parse` and `NIR_Compiler().compile`, then calls `serialize_nir_to_canvas_graph(nir_graph)` exactly once. On any `ParseError`/`CompileError`, return HTTP 422 with the documented diagnostics array. On 500, return the diagnostic-generation-failure payload.
    - Do not modify any code under `backend/app/services/nir_graph_serializer.py` or `backend/app/services/nir_canvas.py`.
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 12.1, 12.2, 12.3, 12.4, 12.5_

  - [ ]* 10.2 Write API integration tests
    - File: `neurocnl/neurosim/tests/test_router_generation_endpoints.py` (new file).
    - Use `fastapi.testclient.TestClient`. Test that a valid round-trip succeeds for each of the three endpoints. Test that a `.nir` containing an unsupported node type returns HTTP 422 with the documented diagnostics shape. Test that bad CNL returns 422; oversized payload returns 400; broken `.nir` binary returns 400.
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

- [x] 11. Headline regression: round-trip every reference NIR fixture
  - [x] 11.1 Build the round-trip equality helper
    - Create `neurocnl/neurocnl/tests/nir_native_cnl/_round_trip.py` (new file).
    - Implement `assert_round_trip_equal(g_in, g_out)` that asserts: same node-key set; same `type(...)` per key; bit-equal scalar parameters via `numpy.array_equal` and float64 exact equality; bit-equal arrays with identical `shape` and `dtype`; integer-tuple structural parameters equal under Python `==`; same multiset of `(src, target)` edges; metadata dict equal under Python `==` with type-preservation (`type(g_out.metadata[k]) is type(g_in.metadata[k])` for every key).
    - Emit a structured `AssertionError` naming the failing node identifier or edge endpoint pair, the parameter name, and the input vs recovered values per Requirement 5.14.
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10, 5.11, 5.14_

  - [x] 11.2 Implement the parameterized fixture regression test
    - Create `neurocnl/neurocnl/tests/nir_native_cnl/test_reference_fixtures.py` (new file).
    - Define `FIXTURES_DIR = Path(__file__).resolve().parents[4] / "NIR graphs"` (note the space) and `FIXTURE_NAMES` listing the eight fixture filenames.
    - Define `@pytest.mark.parametrize("fixture_name", FIXTURE_NAMES, ids=FIXTURE_NAMES)` over a function `test_reference_fixture_round_trip(fixture_name)` that loads the file with `nir.read`, calls `NIR_Renderer().render`, calls `NIR_CNL_Parser().parse`, calls `NIR_Compiler().compile`, and calls `assert_round_trip_equal`.
    - Each parameterized case is independent so a renderer regression on one fixture does not block the parser tests for the remaining fixtures.
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.7, 6.8_

  - [ ]* 11.3 Write property test: round-trip identity
    - **Property 1: Round-trip identity for all supported NIRGraphs**
    - Build a Hypothesis strategy `nir_graph_strategy()` that generates random `nir.NIRGraph` instances over the 18 Primitives with random valid parameter values, random valid identifiers, random valid metadata, and at least one `Input` and one `Output` node. Render → parse → compile → `assert_round_trip_equal`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_round_trip_properties.py`
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10, 5.11, 5.13, 10.1, 10.2, 10.3, 10.4, 11.1, 11.2, 11.3, 11.4**

  - [ ]* 11.4 Write property test: unsupported node and edge handling
    - **Property 13: Unsupported node and edge handling**
    - Generate graphs that include one or more synthetic node objects whose type is not one of the 18 Primitives; render; assert one `# unsupported node type ...` line per such node and one `# unsupported edge from ...` line per incident edge; no exception is raised; the surviving subgraph satisfies `assert_round_trip_equal`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_round_trip_properties.py`
    - **Validates: Requirements 3.6, 3.7, 5.12**

- [ ] 12. Diagnostic and metadata edge cases
  - [ ]* 12.1 Write property test: diagnostic field contract
    - **Property 11: Diagnostic field contract**
    - Generate failing inputs (mix of parser and compiler failures); assert every collected `Diagnostic` has `code` matching `[a-z][a-z0-9_]{0,63}`, `message` of length 1–500, `line` in `[1, 1_000_000]`, `raw` of length 0–1000, `hint` of length 0–1000, and `stage` in the documented set; assert ordering by `line` ascending; assert no graph or record list is returned alongside the exception.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_diagnostic_properties.py`
    - **Validates: Requirements 9.1, 9.2, 9.3, 9.4**

  - [ ]* 12.2 Write property test: metadata unsupported-value and duplicate-key handling
    - **Property 12: Metadata unsupported-value and duplicate-key handling**
    - Generate metadata dicts containing values of unsupported types (lists, dicts, `None`, `NaN`, `±inf`); render; assert one `# metadata ... omitted` comment per such entry and no `annotated with metadata` clause for the entry. Generate sentences with two `annotated with metadata <key>` clauses sharing a key; assert parser raises `duplicate_metadata_key`.
    - File: `neurocnl/neurocnl/tests/nir_native_cnl/test_diagnostic_properties.py`
    - **Validates: Requirements 10.5, 10.6**

- [x] 13. Final checkpoint — full regression
  - Run `PYTHONPATH=. pytest neurocnl/tests/`. Confirm: every parameterized case in `test_reference_fixtures.py` passes; every property test passes 100 iterations; the static-scan test reports zero forbidden tokens; the API integration tests pass. Ensure all tests pass, ask the user if questions arise.

## Task Dependency Graph

```json
{
  "waves": [
    {"wave": 1, "tasks": ["1"]},
    {"wave": 2, "tasks": ["2", "3"]},
    {"wave": 3, "tasks": ["4"]},
    {"wave": 4, "tasks": ["5", "6"]},
    {"wave": 5, "tasks": ["7"]},
    {"wave": 6, "tasks": ["8"]},
    {"wave": 7, "tasks": ["9"]},
    {"wave": 8, "tasks": ["10", "11", "12"]},
    {"wave": 9, "tasks": ["13"]}
  ]
}
```

Critical path: 1 → 2 → 3 → 4 → 5 → 7 → 8 → 9 → 10 → 11 → 13. Task 1 must
complete before any other task because it deletes and rewrites files
that tasks 2–10 also touch. Tasks 11.2 (the eight-fixture regression)
and 13 (the final checkpoint) are blocking acceptance gates per
Requirement 6.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP.
- Tasks 1.1 → 1.5 MUST run before any code in tasks 2 → 13 is written; the new grammar cannot coexist with the legacy modules because identical filenames are rewritten in place.
- Task 11.2 is the headline acceptance test from Requirement 6 and the primary success criterion of this feature.
- Property test files carry the tag `# Feature: nir-native-cnl, Property N: <description>` immediately above each `@given` test function per the project's PBT conventions.
- The full regression command per Requirement 6.6 is `PYTHONPATH=. pytest neurocnl/tests/`.
