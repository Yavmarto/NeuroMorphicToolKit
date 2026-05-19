# Requirements Document

## Introduction

The NeuroCNL toolkit currently contains two incompatible systems for bidirectional CNL ↔ NIR synchronization. System A (the biological reflex-arc CNL) is hardcoded to exactly two nodes and cannot express the 19 NIR computational primitives. System B (the NIR-native canvas serializer) already handles all 19 NIR node types and is solid. The broken sync occurs because `generate-cnl` and `parse-cnl` route through System A, while NIR file loading routes through System B — so any real NIR graph (with `nir.LIF`, `nir.Conv2d`, `nir.Linear`, etc.) produces CNL text that either fails to parse or describes the wrong thing, with no round-trip.

This feature replaces the CNL text layer with a **NIR-native CNL** — a minimal, readable grammar where sentences directly describe NIR node types and their topology. The biological vocabulary (`refractory_period`, `STDP`, `threshold_firing`) is demoted from the grammar core to optional metadata annotations. The primary goal is: **load a `.nir` file → get accurate, readable CNL text**. The secondary goal is: **write NIR-native CNL from scratch → compile to a valid `nir.NIRGraph`**.

The existing NIR-native canvas system (`nir_graph_serializer.py`, `nir_canvas.py`) is preserved and extended. The biological reflex-arc grammar (`neurocnl_bridge.py`, `graph_to_cnl.py`, `cnl_to_graph.py`) is fully replaced. No backward compatibility with the old biological CNL is required or maintained.

---

## Glossary

- **NIR_Native_CNL**: The new grammar system defined by this feature — sentences that describe NIR node types and topology in readable controlled natural language.
- **NIR_Renderer**: The component that converts a `nir.NIRGraph` (or the canvas IR) into NIR-native CNL text.
- **NIR_CNL_Parser**: The component that parses NIR-native CNL text into a structured IR that can be materialized into a `nir.NIRGraph`.
- **NIR_Compiler**: The extended `compile_to_nir()` entry point that accepts NIR-native CNL and returns a `nir.NIRGraph`.
- **Primitive**: One of the 19 NIR computational node types: `Input`, `Output`, `IF`, `LIF`, `LI`, `CubaLIF`, `CubaLI`, `I`, `Linear`, `Affine`, `Scale`, `Conv1d`, `Conv2d`, `AvgPool2d`, `SumPool2d`, `Flatten`, `Delay`, `Threshold`.
- **NIRGraph**: The `nir.NIRGraph` container that holds a dict of named nodes and a list of directed edges.
- **Canvas_Graph**: The `CanvasGraph` data structure used by the NeuroSim canvas frontend, produced by `serialize_nir_to_canvas_graph`.
- **Biological_Grammar**: The existing sensory-motor reflex-arc CNL grammar (`cnl_parser.py`) that speaks in biological terms. This grammar is fully replaced and no longer supported.
- **Round_Trip**: The property that `parse(render(graph))` produces a graph with the same node types, topology, and declared parameters as the original.
- **Metadata_Field**: The `metadata: Dict[str, Any]` attribute present on every `nir.NIRNode`, used to carry biological annotations and CNL provenance through serialization.
- **Dummy_Array**: A `numpy.zeros(shape)` or `numpy.ones(shape)` array synthesized during compilation when the CNL text omits explicit weight values, satisfying NIR's requirement for concrete arrays.

---

## Requirements

### Requirement 1: NIR-Native CNL Grammar

**User Story:** As a neuromorphic engineer, I want a readable grammar that directly maps to NIR node types, so that the CNL text I read and write is an accurate description of the underlying NIR graph.

#### Acceptance Criteria

1. THE NIR_Native_CNL SHALL define one grammar sentence form for each of the 19 NIR Primitive node types.
2. THE NIR_Native_CNL SHALL define one grammar sentence form for declaring directed edges between named nodes.
3. THE NIR_Native_CNL SHALL define one grammar sentence form for declaring a NIRGraph with a name.
4. WHEN a NIR_Native_CNL sentence references a node parameter (e.g., `tau`, `v_threshold`, `kernel_size`), THE sentence SHALL use the same parameter name used by the `nir.*` Python class for that Primitive, with matching being case-sensitive; IF a sentence uses an unrecognised parameter name for a known Primitive, THEN THE NIR_CNL_Parser SHALL raise `ParseError` with `code="unknown_parameter"` (see Requirement 7 criterion 6).
5. THE NIR_Native_CNL SHALL support optional metadata annotations on any node sentence using a `WITH metadata { key: value }` clause, so biological concepts such as `refractory_period` can be preserved without being part of the grammar core; metadata values in `WITH metadata { ... }` clauses MUST be string, integer, or float literals — nested objects and lists are not supported in the grammar surface.
6. WHERE a node parameter is a multi-dimensional array (e.g., `weight` for `Linear`, `kernel` for `Conv2d`), THE NIR_Native_CNL SHALL allow the parameter to be declared by shape only (e.g., `weight shape (128, 784)`) as an alternative to providing explicit numeric values — explicit numeric values remain valid; 1D arrays (vectors) may be declared as `weight shape (N,)`.
7. THE NIR_Native_CNL SHALL use `#` as the single-line comment character.

---

### Requirement 2: NIR Graph → CNL Text (Rendering)

**User Story:** As a user who loads a `.nir` file, I want the system to produce readable, accurate CNL text that describes every node and connection in the graph, so that I can read and understand the network I loaded.

#### Acceptance Criteria

1. WHEN a `nir.NIRGraph` is passed to the NIR_Renderer, THE NIR_Renderer SHALL produce a CNL text string containing one sentence per node and one sentence per directed edge.
2. WHEN the NIR_Renderer encounters a node whose type is one of the 19 Primitives, THE NIR_Renderer SHALL emit a NIR_Native_CNL sentence for that Primitive that includes the node name, node type, and all structural parameters defined for that Primitive type.
3. WHEN the NIR_Renderer encounters a node whose `nir.NIRNode.metadata` dict is non-empty, THE NIR_Renderer SHALL emit those entries as `WITH metadata { ... }` clauses on the corresponding sentence.
4. WHEN the NIR_Renderer encounters a node type that is not one of the 19 Primitives, THE NIR_Renderer SHALL emit a comment line of the form `# unsupported: <nir_type> '<node_name>'` rather than raising an exception.
5. IF the input is a valid `nir.NIRGraph` containing only supported Primitives, THEN THE NIR_Renderer SHALL produce CNL text such that `NIR_CNL_Parser.parse(NIR_Renderer.render(graph))` produces a graph where node names, node types, edge topology, scalar parameters, and array weight values are all preserved exactly (round-trip identity property).
6. THE NIR_Renderer SHALL preserve the node name used as the dict key in `nir.NIRGraph.nodes` as the name in the CNL sentence, so that the round-trip produces matching node identifiers.
7. WHEN the NIR_Renderer produces CNL text for a `nir.NIRGraph`, THE NIR_Renderer SHALL emit all node sentences before any edge sentences, so that the NIR_CNL_Parser can resolve node name references without requiring forward declaration.

---

### Requirement 3: CNL Text → NIR Graph (Parsing and Compilation)

**User Story:** As a developer writing a neuromorphic model in CNL from scratch, I want to compile my NIR-native CNL text directly into a `nir.NIRGraph`, so that I can export it to a `.nir` file and run it on any supported simulator.

#### Acceptance Criteria

1. WHEN the NIR_CNL_Parser receives a valid NIR-native CNL sentence declaring a Primitive node, THE NIR_CNL_Parser SHALL produce a structured IR node record with the node's name, type, and declared parameters.
2. WHEN the NIR_CNL_Parser receives a valid NIR-native CNL sentence declaring an edge, THE NIR_CNL_Parser SHALL produce an IR edge record with the source and target node names.
3. IF a NIR_Native_CNL sentence does not match any known grammar pattern, THEN THE NIR_CNL_Parser SHALL record a structured `ParseError` for that line with a machine-readable `code`, `message`, and the offending line number, and SHALL continue processing remaining lines to collect all parse errors before failing; THE NIR_CNL_Parser SHALL produce no partial IR output when parse errors exist — the IR is only returned after all lines succeed.
4. WHEN the NIR_Compiler receives a valid parsed IR produced by the NIR_CNL_Parser, THE NIR_Compiler SHALL produce a `nir.NIRGraph` that passes `nir.NIRGraph`'s own structural validation; "valid parsed IR" means all edge source/target names resolve to declared node records AND at least one `Input` and one `Output` node record is present.
5. IF the NIR_Compiler receives IR where any edge references a node name not declared in the IR node set, or where duplicate edges exist, or where no `Input` or `Output` node is declared, THEN THE NIR_Compiler SHALL raise `CompileError` with `stage="materializer"` and a `Diagnostic` whose `code` is `"ghost_node"`, `"duplicate_edge"`, or `"missing_endpoint"` respectively, and SHALL NOT produce a `nir.NIRGraph`.
6. WHEN a CNL sentence declares a node parameter by shape only (e.g., `weight shape (128, 784)`), THE NIR_Compiler SHALL synthesize a Dummy_Array of `numpy.zeros(shape)` for the corresponding `nir.*` constructor argument.
7. WHEN the NIR_Compiler receives CNL text that contains a `WITH metadata { ... }` clause, THE NIR_Compiler SHALL store those key-value pairs in the corresponding `nir.NIRNode.metadata` dict so they travel with the serialized `.nir` file.
8. WHEN the NIR_Compiler receives CNL text that was produced by the NIR_Renderer from a `nir.NIRGraph` containing only supported Primitives, THE NIR_Compiler SHALL produce a `nir.NIRGraph` without raising `CompileError`.

---

### Requirement 4: Support All 19 NIR Primitives

**User Story:** As a neuromorphic engineer working with spiking CNNs, SNNs, or mixed architectures, I want every NIR node type to be expressible in CNL text, so that no primitive is silently dropped or misrepresented.

#### Acceptance Criteria

1. THE NIR_Native_CNL SHALL provide grammar coverage for: `Input`, `Output`, `IF`, `LIF`, `LI`, `CubaLIF`, `CubaLI`, `I`, `Linear`, `Affine`, `Scale`, `Conv1d`, `Conv2d`, `AvgPool2d`, `SumPool2d`, `Flatten`, `Delay`, `Threshold` — 18 named Primitives plus the `NIRGraph` container.
2. WHEN a `nir.LIF` node is rendered and reparsed, THE round-trip SHALL preserve `tau`, `r`, `v_leak`, and `v_threshold` parameter values exactly within float64 precision.
3. WHEN a `nir.Conv2d` node is rendered and reparsed, THE round-trip SHALL preserve the `weight` array values exactly within float64 precision, and SHALL preserve `stride`, `padding`, `dilation`, `groups`, and `input_shape` structural parameters.
4. WHEN a `nir.Linear` node is rendered and reparsed, THE round-trip SHALL preserve the `weight` array values exactly within float64 precision.
5. WHEN a `nir.Flatten` node is rendered and reparsed, THE round-trip SHALL preserve `start_dim` and `end_dim`.
6. WHEN a `nir.Delay` node is rendered and reparsed, THE round-trip SHALL preserve the scalar delay value in seconds.
7. WHEN a `nir.Threshold` node is rendered and reparsed, THE round-trip SHALL preserve the threshold value.

---

### Requirement 5: API Route Integration

**User Story:** As a frontend developer or CLI user, I want the `/generate-cnl-from-nir`, `/generate-cnl`, and `/parse-cnl` endpoints to use the NIR-native CNL system so that uploading any `.nir` file produces accurate, parseable CNL text and parsing CNL text produces a correct canvas graph.

#### Acceptance Criteria

1. WHEN the `/api/neurosim/generate-cnl-from-nir` endpoint receives a valid `.nir` binary payload containing any of the 19 supported Primitives, THE endpoint SHALL return CNL text produced by the NIR_Renderer.
2. WHEN the `/api/neurosim/generate-cnl` endpoint receives a `CanvasGraph`, THE endpoint SHALL return CNL text produced by the NIR_Renderer for all graphs.
3. WHEN the `/api/neurosim/parse-cnl` endpoint receives NIR-native CNL text, THE endpoint SHALL return a `CanvasGraph` that is structurally equivalent to the graph that would be produced by compiling the CNL through the NIR_Compiler and then passing it through `serialize_nir_to_canvas_graph`.
4. IF the `/api/neurosim/generate-cnl-from-nir` endpoint receives a `.nir` file containing an unsupported node type, THEN THE endpoint SHALL return HTTP 422 with a structured error body containing a `diagnostics` array describing which node types are unsupported.
5. THE `/api/neurosim/nir/import` and `/api/neurosim/nir/export` canvas routes SHALL remain unmodified: these routes operate on the canvas layer, not the CNL text layer, and are out of scope for this feature.

---

### Requirement 6: Fail-Closed Error Handling and Diagnostics

**User Story:** As a developer debugging a CNL compilation failure, I want structured, actionable error messages that identify exactly which sentence failed and why, so that I can fix the problem without guessing.

#### Acceptance Criteria

1. WHEN the NIR_CNL_Parser encounters a sentence it cannot parse, THE NIR_CNL_Parser SHALL raise a `ParseError` containing a dict with keys `code`, `message`, `line`, `raw`, and `hint`.
2. WHEN the NIR_Compiler encounters one or more parse errors, THE NIR_Compiler SHALL raise `CompileError` whose `diagnostics` list contains one entry for each parse error, with all errors collected from the full input text.
3. IF the NIR_Compiler receives CNL that compiles to a `nir.NIRGraph` with a ghost node (an edge references a node name not in `nodes`), THEN THE NIR_Compiler SHALL raise `CompileError` with `stage="materializer"` and `code="ghost_node"`.
4. IF the NIR_Compiler receives CNL that compiles to a `nir.NIRGraph` with a duplicate edge, THEN THE NIR_Compiler SHALL raise `CompileError` with `stage="materializer"` and `code="duplicate_edge"`.
5. IF the NIR_Compiler receives CNL that compiles to a `nir.NIRGraph` with no `Input` node or no `Output` node, THEN THE NIR_Compiler SHALL raise `CompileError` with `stage="materializer"` and `code="missing_endpoint"`.
6. IF any CNL sentence contains an unrecognized parameter name for a known Primitive (e.g., `tau_xyz` for `nir.LIF`), THEN THE NIR_CNL_Parser SHALL raise `ParseError` with `code="unknown_parameter"` and a `hint` that enumerates the complete list of valid parameter names for the specified Primitive.

---

### Requirement 7: Metadata Preservation

**User Story:** As a user who annotates a NIR graph with biological or provenance metadata, I want those annotations to survive the full CNL round-trip (render → parse → compile), so that none of my non-structural information is silently dropped.

#### Acceptance Criteria

1. WHEN a `nir.NIRNode` has a non-empty `metadata` dict, THE NIR_Renderer SHALL include those entries as a `WITH metadata { key: value, ... }` clause in the emitted CNL sentence.
2. WHEN the NIR_CNL_Parser processes a sentence containing a `WITH metadata { ... }` clause, THE NIR_CNL_Parser SHALL parse the key-value pairs and attach them to the corresponding IR node record.
3. WHEN the NIR_Compiler materializes an IR node record that has attached metadata key-value pairs, THE NIR_Compiler SHALL store those pairs in the resulting `nir.NIRNode.metadata` dict.
4. WHEN the NIR_Renderer emits a `WITH metadata { ... }` clause and that CNL is subsequently parsed by the NIR_CNL_Parser, THE NIR_CNL_Parser SHALL produce metadata key-value pairs where each key matches the original key exactly and each string or numeric value matches the original value exactly, with string lengths up to 1024 characters and numeric precision limited only by float64 representation.
5. IF a `nir.NIRNode.metadata` dict contains values that are not string, integer, or float (e.g., lists, nested dicts, None), THEN THE NIR_Renderer SHALL skip those entries and emit a comment of the form `# metadata key '<key>' omitted: unsupported value type` immediately after the node sentence.

---

### Requirement 8: Shape Consistency and Dummy Array Generation

**User Story:** As a user writing CNL without specifying exact weight matrices, I want the compiler to generate correctly-shaped dummy arrays automatically, so that the resulting `nir.NIRGraph` passes NIR's type-checking without requiring me to specify every weight value.

#### Acceptance Criteria

1. WHEN the NIR_Compiler synthesizes a Dummy_Array for a shape-declared parameter, THE NIR_Compiler SHALL use `numpy.zeros(shape, dtype=float)` as the default fill strategy.
2. WHEN a `nir.Linear` node is declared with `weight shape (out_features, in_features)`, THE NIR_Compiler SHALL produce a weight array of shape `(out_features, in_features)`.
3. WHEN a `nir.Conv2d` node is declared with `weight shape (out_channels, in_channels, kH, kW)`, THE NIR_Compiler SHALL produce a weight array of shape `(out_channels, in_channels, kH, kW)` and a bias array of shape `(out_channels,)`.
4. WHEN a `nir.Affine` node is declared with `weight shape (M, N)`, THE NIR_Compiler SHALL produce a weight array of shape `(M, N)` and a bias array of shape `(M,)`.
5. IF a CNL sentence declares a Primitive that requires a concrete array (e.g., `Linear`) but provides neither explicit values nor a shape declaration, THEN THE NIR_Compiler SHALL raise `CompileError` with `code="missing_shape"` and a `hint` describing the required parameter.
6. IF a CNL sentence declares a shape containing a non-positive dimension (e.g., `weight shape (0, 128)`), THEN THE NIR_Compiler SHALL raise `CompileError` with `code="invalid_shape"` and a `hint` stating that all shape dimensions must be positive integers.

---

### Requirement 9: NIR-Native CNL as the Primary Sync Path

**User Story:** As a developer maintaining the NeuroCNL toolkit, I want a single, correct primary path for NIR ↔ CNL bidirectional sync, so that the two-system architectural break is eliminated and there is only one grammar to maintain.

#### Acceptance Criteria

1. WHEN `generate_cnl_from_nir()` is called with any `nir.NIRGraph` containing supported Primitives, THE returned CNL text SHALL contain NIR-native CNL keywords only and SHALL NOT contain biological vocabulary (`MUST`, `MUST NOT`, `sensory`, `motor`, `threshold_firing`, `refractory_period`).
2. WHEN `parse_spec_text()` receives a line that begins with a NIR-native CNL keyword (e.g., `LIF`, `Conv2d`, `Connect`), THE function SHALL return a parse result with `concept` equal to the NIR Primitive name.
3. THE `neurocnl.compile.compile_to_nir()` public entry point SHALL accept NIR-native CNL text and return a `nir.NIRGraph` without requiring the caller to use a different function.
4. WHEN the NIR_Renderer renders a graph and the output CNL is immediately passed to the NIR_Compiler, THE NIR_Compiler SHALL produce a `nir.NIRGraph` whose node type set, edge set, and array parameter values are identical to the original input graph (full round-trip closure).
