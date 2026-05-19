# Requirements Document

## Introduction

The NeuroCNL toolkit ships a **Controlled Natural Language** (CNL) text layer that is supposed to describe a Neuromorphic Intermediate Representation (NIR) graph in readable English so that engineers and non-engineers can read, write, and review neuromorphic networks as prose. The current `nir-native-cnl` implementation fails this promise on two distinct axes:

1. **The grammar is not natural language.** It is a structured DSL with quoted identifiers, comma-separated key/value parameter lists, and arrow operators — for example `LIF "lif1" tau 0.01, r 1, v_leak 1.2, v_threshold 1` followed by `Connect "in" -> "linear1"`. A reader cannot consume this as English sentences; only a programmer who already knows the DSL can.
2. **The implementation does not work on real NIR graphs.** Eight reference NIR files in `<workspace_root>/NIR graphs/` (`braille_noDelay_bias_zero.nir`, `braille_noDelay_bias_zero_subgraph.nir`, `braille_noDelay_noBias_subtract.nir`, `braille_noDelay_noBias_subtract_subgraph.nir`, `cnn_sinabs.nir`, `lif_norse.nir`, `lif_rockpool.nir`, `two_lif_neurons.nir`) cannot complete the round-trip `.nir → CNL → parse → NIRGraph`. None of these eight files is exercised by the existing test suite, so the breakage shipped silently.

This feature replaces the CNL text layer with a true natural-language CNL surface that reads as English sentences and is regression-tested against the eight reference NIR files. The NIR canvas serializer (`backend/app/services/nir_graph_serializer.py`, `backend/app/services/nir_canvas.py`) is out of scope and is preserved unchanged. The previous biological reflex-arc grammar **and** the previous structured-syntax `nir-native-cnl` grammar are both fully replaced; no backward compatibility is required for either legacy form.

The primary success criterion is end-to-end: loading any of the eight reference NIR files produces CNL prose that a reader can understand, and parsing that prose back recovers a NIR graph with the same nodes, edges, and parameter values.

---

## Glossary

- **NIR**: Neuromorphic Intermediate Representation, the `nir` Python package and `.nir` HDF5 file format used to exchange neuromorphic graphs between simulators.
- **NIRGraph**: The `nir.NIRGraph` container holding a dict of named `nir.NIRNode` instances and a list of directed `(source_name, target_name)` edges.
- **Primitive**: One of the 18 supported NIR node types: `Input`, `Output`, `IF`, `LIF`, `LI`, `CubaLIF`, `CubaLI`, `I`, `Linear`, `Affine`, `Scale`, `Conv1d`, `Conv2d`, `AvgPool2d`, `SumPool2d`, `Flatten`, `Delay`, `Threshold`. The `NIRGraph` container itself is a separate construct expressible in CNL but is not counted as a Primitive.
- **NIR_Native_CNL**: The natural-language CNL surface defined by this feature; the grammar described in Requirement 1 and the sentence forms required by Requirement 2.
- **NL_Sentence**: A single NIR_Native_CNL sentence. Each NL_Sentence ends with a period and describes exactly one node, one edge, or one container declaration.
- **NIR_Renderer**: The component that converts a `nir.NIRGraph` into NIR_Native_CNL text.
- **NIR_CNL_Parser**: The component that parses NIR_Native_CNL text into a structured intermediate record set.
- **NIR_Compiler**: The component that converts the NIR_CNL_Parser's intermediate record set into a `nir.NIRGraph`.
- **Reference_Fixtures**: The eight files at `<workspace_root>/NIR graphs/`: `braille_noDelay_bias_zero.nir`, `braille_noDelay_bias_zero_subgraph.nir`, `braille_noDelay_noBias_subtract.nir`, `braille_noDelay_noBias_subtract_subgraph.nir`, `cnn_sinabs.nir`, `lif_norse.nir`, `lif_rockpool.nir`, `two_lif_neurons.nir`.
- **Round_Trip**: For an input `nir.NIRGraph G`, the operation `parse(render(G))` producing a `nir.NIRGraph G'` such that `G'` and `G` have the same node names, the same node types per name, the same scalar parameter values within float64 precision, the same array parameter values within float64 precision, and the same set of directed edges.
- **Structured_DSL_Tokens**: The closed set of disallowed surface markers that distinguish a structured DSL from natural-language prose. A token sequence belongs to this set if it contains any of the following observable forms outside a CNL comment line: (a) a double-quoted node identifier such as `"lif1"`, (b) an arrow operator between identifiers such as `->` or `→` or `=>`, (c) a comma-separated bare key/value parameter list with no English connective such as `tau 0.01, r 1, v_leak 1.2`, or (d) a statement consisting of a bare Primitive type keyword followed by positional arguments such as `LIF "lif1" tau 0.01`.
- **Metadata_Field**: The `metadata: Dict[str, Any]` attribute on every `nir.NIRNode`, used to carry annotations through serialization.
- **Dummy_Array**: A `numpy.zeros(shape, dtype=float)` array synthesized by the NIR_Compiler when a CNL sentence declares an array parameter by shape only.
- **Biological_Grammar**: The previous sensory/motor reflex-arc CNL grammar identifiable by the keyword token set `{sensory, motor, MUST, MUST NOT, threshold_firing, refractory_period, STDP}` appearing as grammar keywords (i.e., outside string literals). Replaced and unsupported.
- **Structured_Syntax_Grammar**: The previous `nir-native-cnl` grammar that used Structured_DSL_Tokens. Replaced and unsupported.

---

## Requirements

### Requirement 1: Natural-Language Grammar Surface

**User Story:** As an engineer or domain expert reading a NeuroCNL description, I want each sentence to read as English prose, so that I can understand the network without learning a new DSL syntax.

#### Acceptance Criteria

1. THE NIR_Native_CNL SHALL define each NL_Sentence as a sequence of unquoted English words and numeric or shape literals terminated by a period, where the sentence length is at most 1024 characters and at most 64 whitespace-delimited tokens.
2. THE NIR_Native_CNL SHALL begin every node-declaration NL_Sentence with one of the verb phrases `Define` or `Create`, followed by a noun phrase identifying the Primitive type drawn from a documented English-to-Primitive mapping table that lists exactly one canonical noun phrase per Primitive.
3. THE NIR_Native_CNL SHALL introduce a node identifier in a node-declaration NL_Sentence using the connective phrase `named <identifier>`, where `<identifier>` matches the regular expression `[A-Za-z_][A-Za-z0-9_]*`, has length 1 to 64 characters, and is not enclosed in quotes.
4. THE NIR_Native_CNL SHALL introduce parameter clauses in a node-declaration NL_Sentence using the connective `with`, with at most 32 parameter clauses per sentence, multiple parameter clauses separated by commas, and the final clause optionally preceded by `and`.
5. THE NIR_Native_CNL SHALL express each parameter clause as `<english_parameter_phrase> <value>`, where `<english_parameter_phrase>` is drawn from a documented parameter mapping table that maps each phrase one-to-one to a `nir.*` constructor argument name for the host Primitive, and `<value>` is one of: a numeric literal matching the regular expression `-?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?`, a shape literal of the form `shape (d1, d2, ...)`, or — for free-text metadata values only — a double-quoted string literal whose unescaped content is at most 256 characters.
6. THE NIR_Native_CNL SHALL express every directed edge as a stand-alone NL_Sentence of the form `Connect <source_identifier> to <target_identifier>.`, where both identifiers are unquoted and match the regular expression in criterion 3.
7. THE NIR_Native_CNL SHALL express a graph container declaration as a stand-alone NL_Sentence of the form `Define a network named <identifier>.`, optionally followed by node and edge sentences that belong to that network, where `<identifier>` matches the regular expression in criterion 3.
8. THE NIR_Native_CNL SHALL NOT use any Structured_DSL_Tokens. IF the NIR_CNL_Parser encounters a Structured_DSL_Token in the input, THEN THE NIR_CNL_Parser SHALL raise a `ParseError` whose `code` is `"structured_dsl_token"` and whose `hint` names the offending token form.
9. THE NIR_Native_CNL SHALL treat any line whose first non-whitespace character (where whitespace is defined as space, tab, or any Unicode whitespace) is `#` as a comment and ignore the line during parsing.
10. THE NIR_Native_CNL SHALL be case-insensitive for the closed set of English keywords `{Define, Create, named, with, and, Connect, to, network, annotated, metadata, equal, shape}` and case-sensitive for node identifiers, parameter values, metadata keys, and metadata string contents.
11. IF a node-declaration NL_Sentence uses a noun phrase that is not present in the documented English-to-Primitive mapping table from criterion 2, THEN THE NIR_CNL_Parser SHALL raise a `ParseError` whose `code` is `"unknown_primitive_phrase"` and whose `hint` lists every valid noun phrase from the mapping table.
12. IF a node-declaration NL_Sentence uses an `<english_parameter_phrase>` that is not present in the parameter mapping table from criterion 5 for the host Primitive of the sentence, THEN THE NIR_CNL_Parser SHALL raise a `ParseError` whose `code` is `"unknown_parameter_phrase"` and whose `hint` lists every valid `<english_parameter_phrase>` for the host Primitive.
13. IF two node-declaration NL_Sentences inside the same network container use the same node identifier, THEN THE NIR_CNL_Parser SHALL raise a `ParseError` whose `code` is `"duplicate_identifier"` and whose `hint` names the duplicated identifier.

---

### Requirement 2: One Sentence Form Per NIR Primitive

**User Story:** As a developer extending the toolkit, I want exactly one canonical NL_Sentence form per NIR Primitive, so that rendering is deterministic and parsing is unambiguous.

#### Acceptance Criteria

1. THE NIR_Native_CNL SHALL define exactly one canonical node-declaration NL_Sentence form for each of the 18 Primitives listed in the Glossary.
2. THE NIR_Native_CNL SHALL define exactly one canonical edge-declaration NL_Sentence form, as specified in Requirement 1 criterion 6.
3. THE NIR_Native_CNL SHALL define exactly one canonical container-declaration NL_Sentence form, as specified in Requirement 1 criterion 7.
4. WHEN a parameter of a Primitive is an array of two or more dimensions (for example `weight` for `Linear`, `weight` for `Conv2d`), THE NIR_Native_CNL SHALL allow the parameter clause to use a shape-only literal `shape (d1, d2, ...)` as a substitute for an explicit numeric tensor value, where every `dᵢ` is a positive integer ≥ 1.
5. WHEN a parameter of a Primitive is a 1-D vector, THE NIR_Native_CNL SHALL accept the shape literal `shape (N,)` with the trailing comma, where `N` is a positive integer ≥ 1, mirroring NumPy's 1-D shape convention.
6. WHEN a parameter of a Primitive is a scalar, THE NIR_Native_CNL SHALL require an explicit numeric literal in the parameter clause and SHALL NOT accept a shape literal in that clause.
7. WHEN a node-declaration NL_Sentence omits a parameter that has a default value defined by the corresponding `nir.*` constructor for that parameter, THE NIR_Compiler SHALL use the constructor default for that parameter.
8. WHEN a node-declaration NL_Sentence specifies a parameter clause using a shape literal, THE NIR_Compiler SHALL synthesize a Dummy_Array as defined in Requirement 11 criterion 1 instead of using the constructor default for that parameter.
9. IF a node-declaration NL_Sentence specifies a shape literal for a scalar parameter, THEN THE NIR_Compiler SHALL reject the sentence by raising `CompileError` with `code="shape_for_scalar"` naming the offending parameter, AND THE NIR_Compiler SHALL NOT instantiate the corresponding `nir.*` node.
10. IF a node-declaration NL_Sentence omits a parameter that does not have a default value defined by the corresponding `nir.*` constructor and provides neither an explicit value nor a shape literal for that parameter, THEN THE NIR_Compiler SHALL reject the sentence by raising `CompileError` with `code="missing_required_parameter"` naming the offending parameter, AND THE NIR_Compiler SHALL NOT instantiate the corresponding `nir.*` node.

---

### Requirement 3: Render NIR Graph to Natural-Language CNL

**User Story:** As a user who has loaded a `.nir` file, I want the system to produce a readable English description of the graph, so that I can review the network as prose.

#### Acceptance Criteria

1. WHEN a `nir.NIRGraph` is passed to the NIR_Renderer, THE NIR_Renderer SHALL emit a CNL text in which every node in `nir.NIRGraph.nodes` is described by exactly one node-declaration NL_Sentence and every edge in `nir.NIRGraph.edges` is described by exactly one edge-declaration NL_Sentence that references both the source node identifier and the target node identifier using the matching dict keys from `nir.NIRGraph.nodes`.
2. WHEN the NIR_Renderer emits a CNL text for a `nir.NIRGraph`, THE NIR_Renderer SHALL emit all node-declaration NL_Sentences before any edge-declaration NL_Sentence, ordering the node-declaration NL_Sentences in the order their keys appear in `nir.NIRGraph.nodes` and ordering the edge-declaration NL_Sentences in the order their entries appear in `nir.NIRGraph.edges`.
3. WHEN the NIR_Renderer emits a node-declaration NL_Sentence, THE NIR_Renderer SHALL use the dict key from `nir.NIRGraph.nodes` verbatim as the node identifier introduced after `named`.
4. WHEN the NIR_Renderer emits a node-declaration NL_Sentence for a Primitive, THE NIR_Renderer SHALL include exactly one `with` clause for every structural parameter that the corresponding `nir.*` class declares as a constructor argument, and SHALL connect each parameter name to its value using English connectives rather than comma-separated bare key/value pairs, arrow operators, or brace syntax.
5. WHEN the NIR_Renderer encounters a node whose `metadata` dict is non-empty, THE NIR_Renderer SHALL emit one parameter clause per metadata entry using the form `annotated with metadata <key> equal to <value>`, joining successive entries with English connectives.
6. IF the NIR_Renderer encounters a node whose type is not one of the 18 Primitives, THEN THE NIR_Renderer SHALL emit a comment line of the form `# unsupported node type <nir_type> for node <node_name>`, SHALL NOT raise an exception, AND SHALL continue processing every remaining node and edge in the graph, emitting one such comment for each unsupported node encountered.
7. IF an edge in `nir.NIRGraph.edges` references a node identifier that the NIR_Renderer treated as unsupported under criterion 6 or that is absent from `nir.NIRGraph.nodes`, THEN THE NIR_Renderer SHALL emit a comment line of the form `# unsupported edge from <source_name> to <target_name>` in place of the edge-declaration NL_Sentence, SHALL NOT raise an exception, AND SHALL continue processing the remaining edges.
8. THE NIR_Renderer SHALL produce CNL text that contains no Structured_DSL_Tokens.

---

### Requirement 4: Parse Natural-Language CNL to NIR Graph

**User Story:** As a developer authoring a network in CNL, I want my prose description to compile into a valid `nir.NIRGraph`, so that I can export it to a `.nir` file and run it on any supported simulator.

#### Acceptance Criteria

1. WHEN the NIR_CNL_Parser receives a CNL text consisting of valid NL_Sentences, each terminated by a period, THE NIR_CNL_Parser SHALL produce an intermediate record set containing exactly one node record per node-declaration NL_Sentence and exactly one edge record per edge-declaration NL_Sentence, preserving source-order indices.
2. WHEN the NIR_Compiler receives a valid intermediate record set, THE NIR_Compiler SHALL produce a `nir.NIRGraph` whose `nodes` dict is keyed by node-record identifier and whose `edges` list preserves the source-order of edge records, with each node materialized by calling the corresponding `nir.*` constructor using the parameter bindings carried on its node record.
3. WHEN a node-declaration NL_Sentence specifies an array parameter using a shape literal whose every dimension is an integer in the inclusive range 1 to 4096, THE NIR_Compiler SHALL synthesize a Dummy_Array of `numpy.zeros(shape, dtype=float)` and pass it to the corresponding `nir.*` constructor argument.
4. IF a CNL text contains one or more NL_Sentences that fail to parse, THEN THE NIR_CNL_Parser SHALL collect a structured `ParseError` for every failing sentence — each carrying the failing sentence's source-order index and a non-empty reason string — before returning, AND THE NIR_CNL_Parser SHALL NOT return any intermediate record set.
5. IF the NIR_Compiler receives an intermediate record set in which an edge record references a node identifier that is not present in the node record set, THEN THE NIR_Compiler SHALL raise `CompileError` with `code="ghost_node"` naming the source identifier, the target identifier, and the missing identifier, AND THE NIR_Compiler SHALL NOT emit a `nir.NIRGraph`.
6. IF the NIR_Compiler receives an intermediate record set containing two or more edge records with identical source and target identifiers, THEN THE NIR_Compiler SHALL raise `CompileError` with `code="duplicate_edge"` enumerating the source-order indices of all duplicate edge records, AND THE NIR_Compiler SHALL NOT emit a `nir.NIRGraph`.
7. IF the NIR_Compiler receives an intermediate record set containing zero `Input` nodes or zero `Output` nodes or both, THEN THE NIR_Compiler SHALL raise `CompileError` with `code="missing_endpoint"` naming which role(s) (`Input`, `Output`, or both) are missing, AND THE NIR_Compiler SHALL NOT emit a `nir.NIRGraph`.
8. IF a node-declaration NL_Sentence uses a parameter phrase that is not mapped to any constructor argument of the named Primitive, THEN THE NIR_CNL_Parser SHALL raise `ParseError` with `code="unknown_parameter"` carrying the offending phrase and the named Primitive, and a `hint` enumerating every valid parameter phrase for that Primitive.
9. IF a node-declaration NL_Sentence specifies a shape literal whose dimensions are not all integers in the inclusive range 1 to 4096, THEN THE NIR_CNL_Parser SHALL raise `ParseError` with `code="invalid_shape"` naming the offending parameter and the offending dimension value, AND THE NIR_CNL_Parser SHALL NOT return any intermediate record set.

---

### Requirement 5: Round-Trip Identity for Supported Graphs

**User Story:** As a user who reads CNL produced by the NIR_Renderer and feeds it back to the NIR_Compiler, I want the output graph to be identical to the input graph, so that the CNL surface is a lossless view of the NIR graph.

#### Acceptance Criteria

1. WHEN the NIR_Renderer renders a `nir.NIRGraph` containing only Primitives and the resulting CNL text is passed to `NIR_CNL_Parser` followed by `NIR_Compiler`, THE recovered `nir.NIRGraph` SHALL have the same set of node identifiers as the input graph, with no identifier added, dropped, or renamed.
2. WHEN the Round_Trip is performed on a `nir.NIRGraph` containing only Primitives, THE recovered graph SHALL have the same node type for each node identifier as the input graph, where node type equality is the equality of the fully qualified `nir.*` class.
3. WHEN the Round_Trip is performed on a `nir.LIF` node, THE recovered node SHALL preserve `tau`, `r`, `v_leak`, and `v_threshold` bit-equal under IEEE 754 float64 representation.
4. WHEN the Round_Trip is performed on a `nir.CubaLIF` node, THE recovered node SHALL preserve `tau_syn`, `tau_mem`, `r`, `v_leak`, and `v_threshold` bit-equal under IEEE 754 float64 representation.
5. WHEN the Round_Trip is performed on a `nir.Linear`, `nir.Affine`, or `nir.Scale` node, THE recovered node SHALL preserve every weight and bias array with identical `shape`, identical `dtype`, and elementwise bit-equal under IEEE 754 float64 representation.
6. WHEN the Round_Trip is performed on a `nir.Conv1d` or `nir.Conv2d` node, THE recovered node SHALL preserve `weight` and `bias` arrays with identical `shape`, identical `dtype`, and elementwise bit-equality, AND SHALL preserve `stride`, `padding`, `dilation`, `groups`, and `input_shape` as integer values or integer-tuples that compare equal to the input under Python `==`.
7. WHEN the Round_Trip is performed on a `nir.AvgPool2d` or `nir.SumPool2d` node, THE recovered node SHALL preserve `kernel_size`, `stride`, and `padding` as integer values or integer-tuples that compare equal to the input under Python `==`.
8. WHEN the Round_Trip is performed on a `nir.Flatten` node, THE recovered node SHALL preserve `start_dim` and `end_dim` as integer values that compare equal to the input under Python `==`.
9. WHEN the Round_Trip is performed on a `nir.Delay` node, THE recovered node SHALL preserve the delay value in seconds bit-equal under IEEE 754 float64 representation.
10. WHEN the Round_Trip is performed on a `nir.Threshold` node, THE recovered node SHALL preserve the threshold value bit-equal under IEEE 754 float64 representation.
11. WHEN the Round_Trip is performed on a `nir.NIRGraph`, THE recovered graph SHALL have the same multiset of directed `(source, target)` edges as the input graph, with no edge added, no edge dropped, and no edge endpoint reversed.
12. IF the NIR_Renderer is asked to render a `nir.NIRGraph` containing a node whose type is not one of the 18 Primitives, THEN THE NIR_Renderer SHALL handle that node per Requirement 3 criterion 6 (comment-line emission) AND THE round-trip identity criteria 1–11 SHALL be evaluated only over the subset of nodes and edges that exclude that unsupported node and any edges incident to it.
13. WHEN the NIR_Renderer renders any array-bearing parameter of a node whose Round_Trip identity is asserted by criteria 5, 6, 7, 9, or 10, THE NIR_Renderer SHALL emit an explicit numeric literal for every element of that parameter, AND SHALL NOT emit a shape-only literal for that parameter.
14. WHEN a Round_Trip identity assertion required by criteria 1–13 fails for any node or edge, THE failure SHALL be reported with the failing node identifier or edge endpoint pair, the parameter name, and the divergence (input value versus recovered value), so that the failure is observable to the test harness.

---

### Requirement 6: Reference NIR Fixture Regression

**User Story:** As a maintainer, I want a regression test against the eight reference NIR files, so that real-world graphs cannot silently break the round-trip.

#### Acceptance Criteria

1. WHEN the NIR_Renderer is invoked on a file in Reference_Fixtures, THE NIR_Renderer SHALL produce a CNL text of `str` type and SHALL NOT raise any exception.
2. WHEN the NIR_CNL_Parser is invoked on the CNL text produced by the NIR_Renderer for a file in Reference_Fixtures, THE NIR_CNL_Parser SHALL return an intermediate record set with an empty `ParseError` collection.
3. WHEN the NIR_Compiler is invoked on the intermediate record set produced by the NIR_CNL_Parser for a file in Reference_Fixtures, THE NIR_Compiler SHALL return a `nir.NIRGraph` and SHALL NOT raise `CompileError`.
4. WHEN the Round_Trip is performed on the `nir.NIRGraph` loaded from each file in Reference_Fixtures, THE recovered graph SHALL satisfy every criterion in Requirement 5.
5. THE regression test suite for this feature SHALL include exactly one parameterized test case per file in Reference_Fixtures, each test ID containing the fixture's base filename, exercising load → render → parse → compile → compare.
6. WHEN the regression test suite is invoked via `PYTHONPATH=. pytest neurocnl/tests/`, THE suite SHALL execute every parameterized case from criterion 5 with no additional CLI arguments, no environment variables beyond `PYTHONPATH`, and no configuration files.
7. IF the NIR_Renderer raises an exception on a file in Reference_Fixtures, THEN THE regression test for that file SHALL fail with a message identifying the render stage and the fixture base filename, AND THE downstream parse, compile, and compare stages SHALL NOT execute for that file.
8. IF the NIR_Renderer raises an exception on a file in Reference_Fixtures, THEN the regression tests for the remaining seven files SHALL still execute their full load → render → parse → compile → compare pipeline, so that parser regressions are not masked by renderer regressions.

---

### Requirement 7: API Endpoint Integration

**User Story:** As a frontend developer or CLI consumer, I want the existing CNL-related API endpoints to use the new natural-language grammar, so that uploads and round-trips through HTTP work end-to-end.

#### Acceptance Criteria

1. WHEN the `/api/neurosim/generate-cnl-from-nir` endpoint receives a `.nir` binary payload that is at most 10 megabytes and contains only Primitives, THE endpoint SHALL return CNL text produced by the NIR_Renderer in the natural-language grammar defined in Requirement 1, within 5 seconds of the request being received.
2. WHEN the `/api/neurosim/generate-cnl` endpoint receives a `CanvasGraph` payload at most 10 megabytes produced by the NIR canvas serializer, THE endpoint SHALL return CNL text produced by the NIR_Renderer in the natural-language grammar defined in Requirement 1, within 5 seconds of the request being received.
3. WHEN the `/api/neurosim/parse-cnl` endpoint receives NIR_Native_CNL text at most 1 megabyte, THE endpoint SHALL return a `CanvasGraph` that satisfies the equivalence definition in Requirement 5 against the result of compiling the CNL through the NIR_Compiler and serializing the resulting `nir.NIRGraph` through the existing canvas serializer, within 5 seconds of the request being received.
4. IF the `/api/neurosim/generate-cnl-from-nir` endpoint receives a `.nir` payload containing one or more node types outside the 18 Primitives, THEN THE endpoint SHALL return HTTP 422 with a JSON body whose `diagnostics` array contains exactly one entry per offending node, each entry naming the unsupported node type and the corresponding node identifier, with each field a non-empty string.
5. IF the `/api/neurosim/parse-cnl` endpoint receives CNL text that produces any `ParseError` or `CompileError`, THEN THE endpoint SHALL return HTTP 422 with a JSON body whose `diagnostics` array contains exactly one entry per collected error, each carrying `code` (non-empty string), `message` (non-empty string), `line` (integer ≥ 1), and `hint` (string, possibly empty) fields.
6. IF the `/api/neurosim/generate-cnl-from-nir` endpoint receives a payload that is not a valid `.nir` binary, the `/api/neurosim/parse-cnl` endpoint receives a payload that is not valid UTF-8 text, or any of the three endpoints receives a payload that exceeds the size cap declared in criteria 1, 2, or 3, THEN THE endpoint SHALL return HTTP 400 with a JSON body whose `error` field is a non-empty string identifying which validation failed.
7. IF the `/api/neurosim/generate-cnl-from-nir` endpoint or the `/api/neurosim/parse-cnl` endpoint cannot construct a complete `diagnostics` array because the diagnostic-generation path itself raised an exception, THEN THE endpoint SHALL return HTTP 500 with an error body identifying the diagnostic-generation failure, AND THE endpoint SHALL NOT return HTTP 422 with a partial or placeholder diagnostics array.
8. THE `/api/neurosim/nir/import` and `/api/neurosim/nir/export` canvas routes SHALL preserve their existing observable surfaces — request schema, response schema, HTTP status codes, and observable behavior — since the canvas serializer is preserved.

---

### Requirement 8: Replacement of Legacy Grammars

**User Story:** As a maintainer of NeuroCNL, I want both legacy CNL grammars removed so that there is one and only one CNL surface to maintain.

#### Acceptance Criteria

1. WHEN the NIR_Renderer renders any `nir.NIRGraph`, THE output text SHALL contain none of the tokens `sensory`, `motor`, `MUST`, `MUST NOT`, `threshold_firing`, `refractory_period`, or `STDP` outside of double-quoted string literals (these tokens MAY appear inside metadata string values, since metadata is opaque to the grammar).
2. WHEN the NIR_Renderer renders any `nir.NIRGraph`, THE output text SHALL contain no Structured_DSL_Tokens, where Structured_DSL_Tokens are defined as: (a) double-quoted node identifier literals adjacent to a Primitive type keyword, (b) ASCII or Unicode arrow tokens (`->`, `→`, `=>`) appearing between two identifiers, or (c) bare comma-separated `<key> <value>` parameter pairs that are not preceded by an English connective keyword.
3. THE `compile_to_nir()` public entry point SHALL accept only NIR_Native_CNL input.
4. IF `compile_to_nir()` receives input matching the Biological_Grammar shape — defined as the presence of one or more of the keywords `sensory`, `motor`, `MUST`, `MUST NOT`, `threshold_firing`, `refractory_period`, or `STDP` outside any double-quoted string literal — or matching the Structured_Syntax_Grammar shape — defined as the presence of any Structured_DSL_Token per criterion 2 — THEN `compile_to_nir()` SHALL raise `CompileError` with `code="legacy_grammar"` AND SHALL NOT produce a `nir.NIRGraph`.
5. IF any rendering or compilation path inside this feature would emit text containing Structured_DSL_Tokens or Biological_Grammar grammar keywords as defined in criteria 1 and 2, THEN THE NIR_Renderer or NIR_Compiler SHALL halt before emitting that output and SHALL raise an internal `RenderError` with `code="legacy_grammar_emission"` naming the offending token, regardless of whether the input was natural-language CNL or a `nir.NIRGraph`, AND SHALL produce no partial output text.
6. THE feature delivery SHALL ensure that no module under `neurocnl/` declares — through its top-level docstring, its module name, or its sole exported public identifiers — a purpose tied exclusively to the Biological_Grammar or the Structured_Syntax_Grammar, and SHALL ensure that no remaining module imports a parser, renderer, or compiler entry point that targets either legacy grammar.
7. THE feature delivery SHALL ensure that no test under `neurocnl/` contains an assertion fixture or assertion target whose CNL input or expected CNL output uses any keyword from the set `{sensory, motor, MUST, MUST NOT, threshold_firing, refractory_period, STDP}` outside a double-quoted string literal or any Structured_DSL_Token per criterion 2.

---

### Requirement 9: Diagnostics and Fail-Closed Errors

**User Story:** As a developer debugging a CNL document, I want structured, line-anchored diagnostics, so that I can locate and fix problems without guessing.

#### Acceptance Criteria

1. WHEN the NIR_CNL_Parser raises a `ParseError`, THE error object SHALL carry the fields `code`, `message`, `line`, `raw`, and `hint`, where `code` matches the regular expression `[a-z][a-z0-9_]{0,63}`, `message` is a string of length 1 to 500 characters, `line` is an integer in the range 1 to 1,000,000 representing the 1-indexed line number of the offending NL_Sentence, `raw` is the verbatim text of that line truncated to at most 1,000 characters, and `hint` is a string of length 0 to 1,000 characters.
2. WHEN the NIR_Compiler raises a `CompileError`, THE error object SHALL carry a `diagnostics` list of length 1 to 10,000 with one entry per distinct failure, and each entry SHALL carry the same five fields named in criterion 1 plus a `stage` field whose value is exactly one of the strings `"parser"`, `"materializer"`, or `"validator"`.
3. WHEN the NIR_CNL_Parser encounters multiple failing NL_Sentences in a single input of up to 100,000 lines, THE NIR_CNL_Parser SHALL collect every failure (capped at 10,000 collected diagnostics) before returning, ordered by ascending `line` with ties broken by occurrence order in the input, so that the caller sees all diagnostics at once in a deterministic order.
4. IF a CNL input produces any diagnostic, THEN neither the NIR_CNL_Parser nor the NIR_Compiler SHALL return a `nir.NIRGraph`, return an intermediate record set, or write any partial output, AND each component SHALL raise its declared error type carrying every collected diagnostic.
5. WHEN a diagnostic is produced for an unrecognized parameter phrase whose host Primitive is one of the 18 Primitives, THE diagnostic's `hint` field SHALL list every valid parameter phrase for that Primitive in ascending case-insensitive alphabetical order, separated by `", "`.
6. IF a diagnostic is produced for an unrecognized parameter phrase whose referenced Primitive is not one of the 18 Primitives, THEN THE diagnostic's `hint` field SHALL be the literal string `"unknown primitive"` and SHALL NOT enumerate parameter phrases.

---

### Requirement 10: Metadata Round-Trip

**User Story:** As a user who annotates NIR nodes with biological or provenance metadata, I want those annotations to survive the full Round_Trip so that no non-structural information is silently dropped.

#### Acceptance Criteria

1. WHEN the NIR_Renderer renders a node whose `metadata` dict has at least one entry whose value is a string of length 0 to 1024 characters, an integer in the range -2^53 to 2^53, or a finite IEEE 754 float64 (excluding `NaN`, `+inf`, `-inf`), THE NIR_Renderer SHALL emit one `annotated with metadata <key> equal to <value>` parameter clause per such entry, in ascending lexicographic order of the metadata key, where string values are double-quoted and numeric values are unquoted.
2. WHEN the NIR_CNL_Parser parses an `annotated with metadata <key> equal to <value>` clause, THE parser SHALL attach the key/value pair to the corresponding intermediate node record, preserving the source value type as Python `str`, `int`, or `float` according to whether the surface literal was double-quoted, an integer literal, or a decimal/float literal.
3. WHEN the NIR_Compiler materializes a node record carrying metadata key/value pairs, THE compiler SHALL store those pairs in the resulting `nir.NIRNode.metadata` dict using the same key strings and the same Python value types preserved by the parser under criterion 2.
4. WHEN the Round_Trip is performed on a node whose metadata values are restricted to strings, integers, and finite floats as defined in criterion 1, THE recovered node's metadata dict SHALL satisfy `recovered.metadata == original.metadata` under Python equality AND every recovered value SHALL have the same Python type as the corresponding original value.
5. IF a node's metadata dict contains a value that is not a string, integer, or finite float as defined in criterion 1 (for example a list, a nested dict, `None`, `NaN`, or `±inf`), THEN THE NIR_Renderer SHALL skip that entry, SHALL NOT emit an `annotated with metadata` clause for it, AND SHALL emit exactly one comment line of the form `# metadata <key> on <node_name> omitted: unsupported value type` immediately following the corresponding node-declaration NL_Sentence, with one comment line per skipped entry in ascending lexicographic order of the metadata key.
6. IF the NIR_CNL_Parser encounters two or more `annotated with metadata` clauses on the same node-declaration NL_Sentence whose keys are byte-equal strings, THEN THE NIR_CNL_Parser SHALL raise `ParseError` with `code="duplicate_metadata_key"` naming the duplicated key, AND SHALL NOT attach any metadata pair from that sentence to the intermediate node record.

---

### Requirement 11: Shape Declarations and Dummy Arrays

**User Story:** As a user authoring a network in CNL without specifying every weight value, I want shape-only declarations to compile into correctly-shaped placeholder arrays so that the resulting `nir.NIRGraph` passes NIR's type checks.

#### Acceptance Criteria

1. WHEN the NIR_Compiler synthesizes a Dummy_Array, THE synthesized array SHALL be `numpy.zeros(shape, dtype=float)` with `shape` equal to the tuple of positive integers parsed from the shape literal in left-to-right dimension order.
2. WHEN a `nir.Linear` node is declared with a `weight shape (out_features, in_features)` clause where both dimensions are positive integers, THE NIR_Compiler SHALL produce a weight array whose `shape` attribute equals the tuple `(out_features, in_features)` exactly in that order.
3. WHEN a `nir.Conv2d` node is declared with a `weight shape (out_channels, in_channels, kH, kW)` clause and no explicit bias clause, THE NIR_Compiler SHALL produce a weight array whose `shape` attribute equals `(out_channels, in_channels, kH, kW)` exactly and a bias array whose `shape` attribute equals `(out_channels,)` exactly.
4. WHEN a `nir.Affine` node is declared with a `weight shape (M, N)` clause and no explicit bias clause, THE NIR_Compiler SHALL produce a weight array whose `shape` attribute equals `(M, N)` exactly and a bias array whose `shape` attribute equals `(M,)` exactly.
5. WHEN a `nir.Conv2d` or `nir.Affine` node is declared with a weight clause AND an explicit bias clause (either an explicit numeric tensor or a shape literal), THE NIR_Compiler SHALL use the explicit bias clause as the source of the bias array AND SHALL NOT derive the bias array from the weight clause.
6. IF a node-declaration NL_Sentence declares a Primitive that requires a concrete array but provides neither an explicit numeric tensor nor a shape literal for that array parameter, THEN THE NIR_Compiler SHALL raise `CompileError` with `code="missing_shape"` carrying a field that names the missing parameter using the parameter name as written in the host Primitive's contract.
7. IF a shape literal contains a non-integer numeric token (for example `1.5`), a non-numeric token, or a non-positive integer (for example `0` or `-1`), THEN THE NIR_CNL_Parser SHALL raise `ParseError` with `code="invalid_shape"` and a `hint` stating that all dimensions must be positive integers, AND SHALL NOT emit a node record for the offending sentence.
8. IF a shape literal's dimension count does not match the rank declared by the host Primitive's contract for that parameter (for example a 3-tuple supplied for `nir.Linear` `weight`), THEN THE NIR_Compiler SHALL raise `CompileError` with `code="shape_rank_mismatch"` carrying fields naming the parameter and the expected rank.

---

### Requirement 12: Boundary with the Preserved Canvas Serializer

**User Story:** As a maintainer, I want a clean boundary between the CNL text layer (this feature) and the NIR canvas serializer (preserved), so that changes to the CNL surface do not destabilize the canvas pipeline.

#### Acceptance Criteria

1. THE feature delivery SHALL NOT modify the public interface — defined as the set of non-underscore-prefixed exported symbols pinned to the feature branch's merge-base with `main` — of `backend/app/services/nir_graph_serializer.py`.
2. THE feature delivery SHALL NOT modify the public interface — defined as the set of non-underscore-prefixed exported symbols pinned to the feature branch's merge-base with `main` — of `backend/app/services/nir_canvas.py`.
3. WHEN the `/api/neurosim/parse-cnl` endpoint converts a parsed `nir.NIRGraph` into a `CanvasGraph`, THE conversion SHALL be performed by exactly one direct call to the existing canvas serializer's public entry point, passing the `nir.NIRGraph` unchanged and returning the serializer's `CanvasGraph` output unchanged, with no helper wrapper that adds, removes, reorders, or modifies fields, nodes, edges, or attributes on either input or output.
4. WHEN the `/api/neurosim/generate-cnl` endpoint converts a `CanvasGraph` into a `nir.NIRGraph` for rendering, THE conversion SHALL be performed by exactly one direct call to the existing canvas serializer's public entry point, passing the `CanvasGraph` unchanged and returning the serializer's `nir.NIRGraph` output unchanged, with no helper wrapper that adds, removes, reorders, or modifies fields, nodes, edges, or attributes on either input or output.
5. IF the canvas serializer's public entry point raises an exception during the conversions described in criteria 3 and 4, THEN THE endpoint SHALL propagate that exception to its outer error-handling layer without catching or transforming it inside the conversion site, AND SHALL NOT emit a partial `CanvasGraph` or partial `nir.NIRGraph`.
