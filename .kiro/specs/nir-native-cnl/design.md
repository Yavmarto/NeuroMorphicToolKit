# Design Document: NIR-Native CNL (`nir-native-cnl`)

## Overview

NeuroCNL currently has two incompatible sync paths. The biological reflex-arc grammar (System A)
can only express two-node sensory → motor graphs, while the NIR-native canvas serialiser
(System B) already handles all 19 NIR node types. The live `/generate-cnl` and `/parse-cnl`
routes go through System A, so any real NIR graph produces CNL that is wrong or fails to parse.

This design replaces the CNL text layer entirely with a **NIR-native CNL** — a minimal,
readable grammar where sentences directly describe NIR node types and topology. The biological
vocabulary is demoted to optional `WITH metadata { ... }` annotations. The existing canvas
system (`nir_graph_serializer.py`, `nir_canvas.py`) is preserved unchanged.

**Primary path that must work:**

```
.nir file
  → nir.read()
  → generate_cnl_from_nir()  [NIR_Renderer]
  → readable CNL text
  → compile_to_nir()          [NIR_CNL_Parser + NIR_Compiler]
  → nir.NIRGraph (identical to original)
```

**No backward compatibility** with the old biological grammar. It is fully replaced.


## Architecture

The new system introduces three components and modifies three entry points. Everything else
that is not listed in the deletion table is preserved.

### High-Level Component Map

```
┌───────────────────────────────────────────────────────────────┐
│  NeuroCNL                                                     │
│                                                               │
│  neurocnl/nir_cnl/                                            │
│    ├── renderer.py          NIR_Renderer                      │
│    ├── parser.py            NIR_CNL_Parser                    │
│    ├── compiler.py          NIR_Compiler                      │
│    ├── grammar.py           sentence patterns + token tables  │
│    └── ir_types.py          NIRNodeRecord, NIREdgeRecord       │
│                                                               │
│  Modified entry points:                                       │
│    neurocnl/pipeline.py     generate_cnl_from_nir()           │
│    neurocnl/pipeline.py     parse_spec_text()                 │
│    neurocnl/compile.py      compile_to_nir()                  │
│                                                               │
│  Preserved (read-only from this feature):                     │
│    backend/app/services/nir_graph_serializer.py               │
│    backend/app/services/nir_canvas.py                         │
│    neurosim/app/routers/generation.py  (rewired, not rewritten)│
└───────────────────────────────────────────────────────────────┘
```

### Data Flow: NIR → CNL (Render Direction)

```
nir.NIRGraph
    │
    ▼
NIR_Renderer.render(graph: nir.NIRGraph) → str
    │  iterates graph.nodes (dict)
    │  for each node:
    │    calls _render_node(name, node) → str sentence
    │    if node.metadata non-empty: appends WITH metadata {...}
    │  iterates graph.edges (list of tuples)
    │  for each edge:
    │    calls _render_edge(src, dst) → str sentence
    │  node sentences first, edge sentences after
    ▼
CNL text (str)
```

### Data Flow: CNL → NIR (Compile Direction)

```
CNL text (str)
    │
    ▼
NIR_CNL_Parser.parse(text: str) → list[NIRNodeRecord | NIREdgeRecord]
    │  line-by-line scan
    │  regex match against SENTENCE_PATTERNS[primitive]
    │  for each match: builds NIRNodeRecord with params dict
    │  collects all ParseError before raising
    ▼
list[NIRNodeRecord | NIREdgeRecord]
    │
    ▼
NIR_Compiler.compile(records) → nir.NIRGraph
    │  validates: ghost nodes, duplicate edges, missing Input/Output
    │  for each NIRNodeRecord: calls _build_nir_node(record)
    │    scalar params → direct float/int
    │    shape-only params → numpy.zeros(shape, dtype=float)
    │    explicit array params → numpy.asarray(values, dtype=float)
    │    metadata → stored in nir.*node.metadata
    │  builds nir.NIRGraph(nodes=..., edges=...)
    ▼
nir.NIRGraph
```


## Components and Interfaces

### 3.1 NIR_Renderer (`neurocnl/nir_cnl/renderer.py`)

```python
class NIR_Renderer:
    def render(self, graph: nir.NIRGraph) -> str:
        """Convert a nir.NIRGraph to NIR-native CNL text.

        All node sentences are emitted before any edge sentences.
        Unsupported node types produce a comment line instead of raising.
        """

    def _render_node(self, name: str, node: nir.NIRNode) -> str:
        """Emit one CNL sentence for a supported primitive node."""

    def _render_edge(self, src: str, dst: str) -> str:
        """Emit one CNL sentence for a directed edge."""

    def _render_metadata(self, metadata: dict[str, Any]) -> str:
        """Emit WITH metadata { ... } clause; skip non-str/int/float values."""
```

### 3.2 NIR_CNL_Parser (`neurocnl/nir_cnl/parser.py`)

```python
@dataclass(slots=True)
class NIRNodeRecord:
    name: str
    nir_type: str           # e.g. "LIF", "Conv2d"
    params: dict[str, Any]  # key → scalar | {"shape": tuple} | {"values": list}
    metadata: dict[str, Any]
    line: int

@dataclass(slots=True)
class NIREdgeRecord:
    src: str
    dst: str
    line: int

class NIR_CNL_Parser:
    def parse(self, text: str) -> list[NIRNodeRecord | NIREdgeRecord]:
        """Parse NIR-native CNL text.

        Collects all ParseError instances before raising, so callers
        receive every error in the spec at once.
        Raises ParseError (a list-bearing exception) if any line fails.
        """
```

`ParseError` carries:

```python
@dataclass
class ParseError(Exception):
    errors: list[dict]  # each: {code, message, line, raw, hint}
```

### 3.3 NIR_Compiler (`neurocnl/nir_cnl/compiler.py`)

```python
class NIR_Compiler:
    def compile(
        self,
        records: list[NIRNodeRecord | NIREdgeRecord],
    ) -> nir.NIRGraph:
        """Materialise a list of IR records into a nir.NIRGraph.

        Validates ghost nodes, duplicate edges, and missing Input/Output
        before constructing any nir.* objects.
        Raises CompileError (stage="materializer") on structural failures.
        """

    def _build_nir_node(self, record: NIRNodeRecord) -> nir.NIRNode:
        """Construct the correct nir.* object from an IR node record."""
```

### 3.4 Grammar Module (`neurocnl/nir_cnl/grammar.py`)

Holds:
- `SENTENCE_PATTERNS: dict[str, re.Pattern]` — one compiled regex per primitive keyword
- `PRIMITIVE_PARAMS: dict[str, set[str]]` — valid parameter names per primitive
- `ARRAY_PARAMS: dict[str, set[str]]` — which parameters are arrays per primitive
- `EDGE_PATTERN: re.Pattern` — regex for edge sentences
- `GRAPH_PATTERN: re.Pattern` — regex for graph header sentences


## CNL Grammar: Concrete Sentence Patterns

### Design Principles

- One sentence form per primitive. Sentence always begins with the NIR type name as the keyword.
- Named node with `"<name>"` quoted identifier.
- Parameters are key-value pairs separated by commas after a colon.
- Arrays may be given as explicit bracket lists `[v0, v1, ...]` OR by shape `shape (d0, d1, ...)`.
- Directed edge uses `Connect "<src>" -> "<dst>"`.
- Graph container uses `NIRGraph "<name>"`.
- `#` introduces a comment to end-of-line.
- Optional `WITH metadata { key: value, ... }` clause at the end of any node sentence.

### 4.1 Graph Container

```
NIRGraph "<name>"
```

Example:
```
NIRGraph "my_snn"
```

### 4.2 Input / Output (I/O nodes)

```
Input "<name>" shape (<d0>, <d1>, ...)
Output "<name>" shape (<d0>, <d1>, ...)
```

Examples:
```
Input "pixels" shape (1, 28, 28)
Output "logits" shape (10,)
```

`shape` is the tensor shape declared in `nir.Input.input_type` / `nir.Output.output_type`.

### 4.3 Neuron Dynamics

**IF** (Integrate-and-Fire):
```
IF "<name>" r <scalar>, v_threshold <scalar>
```

Example:
```
IF "integrate1" r 1.0, v_threshold 1.0
```

**LIF** (Leaky Integrate-and-Fire):
```
LIF "<name>" tau <scalar|array>, r <scalar|array>, v_leak <scalar|array>, v_threshold <scalar|array>
```

Example — scalar broadcast:
```
LIF "lif0" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0
```

Example — explicit per-neuron arrays:
```
LIF "lif0" tau [0.02, 0.02, 0.02], r [1.0, 1.0, 1.0], v_leak [0.0, 0.0, 0.0], v_threshold [1.0, 1.0, 1.0]
```

**LI** (Leaky Integrator):
```
LI "<name>" tau <scalar|array>, r <scalar|array>, v_leak <scalar|array>
```

**CubaLIF** (Current-Based LIF):
```
CubaLIF "<name>" tau_syn <scalar|array>, tau_mem <scalar|array>, r <scalar|array>, v_leak <scalar|array>, v_threshold <scalar|array>, w_in <scalar|array>
```

**CubaLI** (Current-Based Leaky Integrator):
```
CubaLI "<name>" tau_syn <scalar|array>, tau_mem <scalar|array>, r <scalar|array>, v_leak <scalar|array>
```

**I** (Integrator):
```
I "<name>" r <scalar|array>
```

### 4.4 Linear Transformations

**Linear** — explicit values:
```
Linear "<name>" weight [<row0_col0>, <row0_col1>, ...; <row1_col0>, ...]
```

**Linear** — shape only:
```
Linear "<name>" weight shape (<out_features>, <in_features>)
```

Example:
```
Linear "fc1" weight shape (128, 784)
Linear "fc1_small" weight [[0.5, -0.3], [0.1, 0.9]]
```

Semicolons separate rows in an inline matrix literal. The compiler always stores the
full numpy array.

**Affine** — explicit:
```
Affine "<name>" weight [<...>], bias [<b0>, <b1>, ...]
```

**Affine** — shape only (bias auto-derived as zeros of shape `(M,)`):
```
Affine "<name>" weight shape (<M>, <N>)
```

**Scale**:
```
Scale "<name>" scale [<s0>, <s1>, ...]
```

or scalar:
```
Scale "<name>" scale <scalar>
```

### 4.5 Convolutions

**Conv1d**:
```
Conv1d "<name>" weight shape (<out_ch>, <in_ch>, <kW>), stride <int>, padding <int|"same">, dilation <int>, groups <int>
```

or with explicit weight:
```
Conv1d "<name>" weight [<...>], stride <int>, padding <int>, dilation <int>, groups <int>
```

**Conv2d**:
```
Conv2d "<name>" weight shape (<out_ch>, <in_ch>, <kH>, <kW>), stride (<sH>, <sW>), padding (<pH>, <pW>), dilation (<dH>, <dW>), groups <int>, input_shape (<iH>, <iW>)
```

or with explicit weight:
```
Conv2d "<name>" weight [[...]], stride (1, 1), padding (0, 0), dilation (1, 1), groups 1, input_shape (28, 28)
```

### 4.6 Pooling

**AvgPool2d**:
```
AvgPool2d "<name>" kernel_size (<kH>, <kW>), stride (<sH>, <sW>), padding (<pH>, <pW>)
```

**SumPool2d**:
```
SumPool2d "<name>" kernel_size (<kH>, <kW>), stride (<sH>, <sW>), padding (<pH>, <pW>)
```

### 4.7 Utility Nodes

**Flatten**:
```
Flatten "<name>" start_dim <int>, end_dim <int>
```

**Delay**:
```
Delay "<name>" delay <scalar>
```

**Threshold**:
```
Threshold "<name>" threshold <scalar|array>
```

### 4.8 Edge Sentence

```
Connect "<src>" -> "<dst>"
```

Example:
```
Connect "pixels" -> "conv1"
Connect "conv1" -> "lif0"
Connect "lif0" -> "fc1"
Connect "fc1" -> "logits"
```

### 4.9 Metadata Annotation

Any node sentence may be followed by a `WITH metadata { ... }` clause on the same line:

```
LIF "lif0" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0 WITH metadata { refractory_period: 0.002, source: "snnTorch" }
```

Values must be string literals (quoted), integer literals, or float literals.
Nested objects and lists are not supported in metadata values.

### 4.10 Comment Syntax

```
# This is a single-line comment
LIF "lif0" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0  # inline comment
```

### 4.11 Complete Example — Spiking CNN Fragment

```
# 3-layer SNN: conv → lif → linear → output
NIRGraph "mnist_snn"

Input "pixels" shape (1, 28, 28)
Conv2d "conv1" weight shape (16, 1, 5, 5), stride (1, 1), padding (2, 2), dilation (1, 1), groups 1, input_shape (28, 28)
LIF "lif0" tau 0.02, r 1.0, v_leak 0.0, v_threshold 1.0
Flatten "flat1" start_dim 1, end_dim -1
Linear "fc1" weight shape (10, 12544)
Output "logits" shape (10,)

Connect "pixels" -> "conv1"
Connect "conv1" -> "lif0"
Connect "lif0" -> "flat1"
Connect "flat1" -> "fc1"
Connect "fc1" -> "logits"
```


## Data Models

### 5.1 NIRNodeRecord

```python
@dataclass(slots=True)
class NIRNodeRecord:
    name: str
    nir_type: str                   # one of the 18 primitive names
    params: dict[str, Any]          # param_name → scalar | ArraySpec | float list
    metadata: dict[str, str | int | float]
    line: int                       # source line for error reporting

@dataclass(slots=True)
class ArraySpec:
    """Represents a shape-only array declaration."""
    shape: tuple[int, ...]

@dataclass(slots=True)
class NIREdgeRecord:
    src: str
    dst: str
    line: int
```

### 5.2 Array Serialization in CNL Text

The requirement that weight values survive the round-trip exactly rules out shape-only
rendering for graphs that already have concrete arrays. The chosen format is **inline
bracket notation** with full float64 precision.

**Decision: inline bracket notation with row-major layout**

Rationale:
- Readable without external tools (unlike base64)
- No external file references (unlike `.npy` or `.h5` side-files)
- Full float64 round-trip via Python `repr()` precision (`%.17g` format)
- Rows delimited by `;` inside `[...]` for 2-D arrays; nested `[...]` for ≥3-D arrays

Alternatives considered and rejected:
- **Base64 + numpy frombuffer**: not human-readable, defeats the "readable CNL" goal
- **Shape-only (zeros)**: loses the actual trained weights, violating the weight-preservation requirement
- **External `.npy` files referenced by path**: breaks the single-text-file contract

**Format specification:**

1-D vector: `[v0, v1, ..., vN]` where each `vI` is formatted with `%.17g`.

2-D matrix (row × col):
```
[[r0c0, r0c1, ...], [r1c0, r1c1, ...]]
```

4-D Conv2d kernel (out, in, kH, kW) — nested bracket lists following numpy's `tolist()`:
```
[[[[v, ...], ...], ...], ...]
```

The renderer calls `numpy.ndarray.tolist()` and passes the result through Python's default
`repr` which produces exact float64 decimal strings. The parser calls
`numpy.asarray(parsed_literal, dtype=float64)`.

Scalar broadcast: when all elements of an array are equal, the renderer emits a single
scalar instead of the full array (e.g., `tau 0.02` rather than `tau [0.02, 0.02, 0.02]`).
The compiler always broadcasts scalars to the correct size via `numpy.full(size, scalar)`.

### 5.3 Metadata Value Encoding

Metadata values in CNL text are typed literals:
- String: double-quoted, e.g. `"snnTorch"`, max 1024 chars
- Integer: bare integer, e.g. `42`
- Float: decimal, e.g. `0.002`

Non-str/int/float values in `nir.NIRNode.metadata` are skipped with a comment:
```
# metadata key 'weight_history' omitted: unsupported value type
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Full Round-Trip Identity

*For any* valid `nir.NIRGraph` containing only supported Primitives, rendering it to CNL text and compiling that text back to a `nir.NIRGraph` SHALL produce a graph where:
- the node key set is identical
- the node type of each node is identical
- all scalar parameter values are equal within float64 precision
- all array parameter values are bitwise-equal (same shape, same dtype, same element values)
- the edge set is identical

**Validates: Requirements 2.5, 3.4, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 9.4**

### Property 2: Metadata Round-Trip Preservation

*For any* `nir.NIRNode` whose `metadata` dict contains only string, integer, or float values,
rendering then parsing then compiling SHALL produce a `nir.NIRNode.metadata` dict where
every key matches the original key exactly and every value matches the original value exactly
(strings up to 1024 chars; numerics limited only by float64 precision).

**Validates: Requirements 7.1, 7.2, 7.3, 7.4**

### Property 3: Node-Sentence / Edge-Sentence Ordering Invariant

*For any* valid `nir.NIRGraph` passed to the NIR_Renderer, every line in the rendered CNL
text that is an edge sentence (`Connect`) SHALL have a line index strictly greater than
every line that is a node sentence, ensuring parsers can resolve node names without
forward declaration.

**Validates: Requirements 2.7**

### Property 4: Shape-Only Compilation Produces Zeros Array

*For any* tuple of positive integers `(d0, d1, ..., dN)` used as a shape-only parameter
declaration for any array-bearing Primitive, the NIR_Compiler SHALL produce a `numpy.zeros`
array of exactly that shape with `dtype=float64`.

**Validates: Requirements 3.6, 8.1, 8.2**

### Property 5: Bias Shape Derived from Weight Out-Channels

*For any* shape-only declaration of `nir.Conv2d` or `nir.Affine` with weight shape
`(M, ...)`, the NIR_Compiler SHALL synthesize a bias array of shape `(M,)`.

**Validates: Requirements 8.3, 8.4**

### Property 6: No Biological Vocabulary in Rendered CNL

*For any* `nir.NIRGraph` containing only supported Primitives, the text produced by
`generate_cnl_from_nir()` SHALL NOT contain any of the following tokens as standalone
words: `MUST`, `MUST NOT`, `sensory`, `motor`, `threshold_firing`, `refractory_period`.

**Validates: Requirements 9.1**

### Property 7: Unknown Parameter Name Rejected with Structured Error

*For any* CNL sentence that uses a parameter name not in `PRIMITIVE_PARAMS[nir_type]` for
a known Primitive, the NIR_CNL_Parser SHALL raise `ParseError` containing an error entry
with `code="unknown_parameter"` and a `hint` that lists all valid parameter names for that
Primitive.

**Validates: Requirements 1.4, 6.6**

### Property 8: All Parse Errors Collected Before Failing

*For any* CNL text containing N lines that each fail to match any grammar pattern, the
NIR_CNL_Parser SHALL collect exactly N `ParseError` entries before raising, and SHALL
produce no partial IR records for those lines.

**Validates: Requirements 3.3, 6.2**


## What Changes in the Three Entry Points

### 6.1 `generate_cnl_from_nir()` in `neurocnl/pipeline.py`

**Current behavior:** calls `nir_import_diagnostics()` + `import_ir_from_nir()` +
`render_cnl_document()` — routes through the biological IR and its population-centric
document renderer, which cannot express any node type other than `LIF`.

**New behavior:**

```python
def generate_cnl_from_nir(graph: nir.NIRGraph) -> str:
    """Generate NIR-native CNL text from a NIR graph (all 19 primitives)."""
    from neurocnl.nir_cnl.renderer import NIR_Renderer
    renderer = NIR_Renderer()
    return renderer.render(graph)
```

`NirImportError` is no longer raised for supported primitives. If any node type is
unsupported, the renderer emits a comment line and continues. The caller can inspect
the returned text for `# unsupported:` comments if needed.

### 6.2 `parse_spec_text()` in `neurocnl/pipeline.py`

**Current behavior:** calls `neurocnl.cnl.cnl_parser.parse()` (the biological grammar
parser) line-by-line.

**New behavior:** routes through `NIR_CNL_Parser` when the first non-comment, non-empty
line begins with a NIR-native keyword (any of the 18 primitive names, `Connect`,
`NIRGraph`). Falls back to the old biological parser only for legacy biological CNL
text that still begins with `The network MUST` etc. (during a transitional period; the
old path is removed when the migration is complete).

In practice, for all new code:

```python
def parse_spec_text(spec_text: str) -> list[ParseResult]:
    if _is_nir_native(spec_text):
        return _parse_nir_native(spec_text)   # NIR_CNL_Parser path
    return _parse_biological(spec_text)        # legacy path, to be deleted
```

`_is_nir_native` checks if the first substantive line starts with one of the 18
primitive keywords, `Connect`, or `NIRGraph`.

For NIR-native lines, each `ParseResult` entry has `concept` equal to the primitive
name (e.g. `"LIF"`, `"Conv2d"`, `"Connect"`).

### 6.3 `compile_to_nir()` in `neurocnl/compile.py`

**Current behavior:** parse → exportability gate → `lower_to_ir()` →
`Materializer().materialize()`.

**New behavior:** same 5-stage pipeline, but stages 1–4 are replaced for NIR-native
CNL text:

- **Stage 1 (parse):** calls `NIR_CNL_Parser.parse(spec)` instead of the biological parser
- **Stage 2 (exportability gate):** removed — NIR_CNL_Parser already enforces
  supported-primitive-only by construction
- **Stage 3 (lower to IR):** no `lower_to_ir()` call; parser output is already a list of
  `NIRNodeRecord`/`NIREdgeRecord` (the IR)
- **Stage 4 (materialize):** calls `NIR_Compiler.compile(records)` instead of
  `Materializer().materialize(ir_model)`
- **Stage 5 (write to disk):** unchanged

The `Diagnostic` dataclass and `CompileError` exception are unchanged; the new stages
produce the same structured diagnostics.

For biological CNL text (legacy only), stages 1–4 are unchanged.


## What Gets Deleted

The following files and functions are fully removed as part of this feature. Nothing that
is not in this list should be touched.

### 7.1 Files Deleted

| File | Reason |
|---|---|
| `neurocnl/neurosim/app/services/graph_to_cnl.py` | Biological graph → CNL renderer; replaced by NIR_Renderer |
| `neurocnl/neurosim/app/services/neurocnl_bridge.py` | Biological reflex-arc bridge (sensory/motor check, `get_canonical_canvas_sync_issues`, `graph_to_canvas_canonical_cnl`, etc.); replaced entirely |
| `neurocnl/neurosim/app/services/semantic_cnl.py` | `build_reflex_arc_semantic_lines()` helper; no longer needed |
| `neurocnl/neurocnl/cnl/cnl_parser.py` | Biological CNL parser (`parse()`, `ParseError` for bio grammar); replaced by NIR_CNL_Parser |
| `neurocnl/neurocnl/cnl/cnl_grammar.md` | Biological grammar spec document; replaced by this design doc |
| `neurocnl/neurocnl/simulation/reflex_arc.cnl` | Sample biological CNL file; no longer valid CNL |
| `neurocnl/neurocnl/cnl/test_cnl_parser.py` | Tests for the biological parser |
| `neurocnl/neurocnl/cnl/test_adaptive_spiking_parser.py` | Biological-grammar-specific parser tests |
| `neurocnl/neurocnl/cnl/test_background_noise_parser.py` | Biological-grammar-specific parser tests |
| `neurocnl/neurocnl/cnl/test_receptor_dynamics_parser.py` | Biological-grammar-specific parser tests |
| `neurocnl/neurocnl/cnl/test_short_term_plasticity_parser.py` | Biological-grammar-specific parser tests |
| `neurocnl/neurocnl/cnl/test_spatial_connectivity_parser.py` | Biological-grammar-specific parser tests |

### 7.2 Functions Deleted (from files that are otherwise kept)

| File | Function | Reason |
|---|---|---|
| `neurocnl/neurocnl/pipeline.py` | `import_ir_from_nir()` (via `cnl/document.py`) | Replaced by `NIR_Renderer` |
| `neurocnl/neurocnl/pipeline.py` | `nir_import_diagnostics()` (via `cnl/document.py`) | Replaced by `NIR_Renderer`'s comment fallback |
| `neurocnl/neurocnl/pipeline.py` | `render_cnl_document()` (via `cnl/document.py`) | Replaced by `NIR_Renderer` |
| `neurocnl/neurocnl/compile.py` | `ensure_nir_exportable()` call | Redundant when using NIR_CNL_Parser |
| `neurocnl/neurosim/app/routers/generation.py` | import of `graph_to_canvas_canonical_cnl` | Source file deleted |
| `neurocnl/neurosim/app/routers/generation.py` | import of `CanonicalCanvasSyncError` | Source file deleted |
| `neurocnl/neurocnl/ir/materializer.py` | `Materializer.materialize()` (for new path) | New path uses `NIR_Compiler`; old `Materializer` kept for legacy biological path during transition |

### 7.3 Routes Rewired (not deleted)

`neurocnl/neurosim/app/routers/generation.py` keeps all route functions but updates their
internals:

- `/generate-cnl`: removes the `graph_to_canvas_canonical_cnl` branch; all graphs go through
  `NIR_Renderer` via `generate_cnl_from_nir(deserialize_canvas_graph(graph))`
- `/parse-cnl`: removes `build_neurosim_handoff_spec` call; routes directly through
  `NIR_CNL_Parser` + `NIR_Compiler` + `serialize_nir_to_canvas_graph`
- `/parse-cnl-canonical`: updated to use NIR_CNL_Parser; the error message referencing
  "canonical reflex-arc grammar (sensory → motor, lif_population, static_synapse)" is removed
- `/generate-cnl-from-nir`: unchanged signature; body calls `NIR_Renderer` directly


## Error Handling

### 8.1 ParseError

Raised by `NIR_CNL_Parser.parse()`. Carries a list of per-line error dicts:

```python
{
    "code":    "unknown_primitive" | "unknown_parameter" | "syntax_error" | ...,
    "message": str,
    "line":    int,
    "raw":     str,   # the offending line
    "hint":    str,   # e.g. "Valid parameters for LIF: tau, r, v_leak, v_threshold"
}
```

The parser accumulates **all** errors before raising so callers see the full error
list in one go.

### 8.2 CompileError (stage="materializer")

Raised by `NIR_Compiler.compile()` for structural graph problems. Uses the existing
`CompileError` / `Diagnostic` classes from `neurocnl/compile.py`:

| Condition | `code` |
|---|---|
| Edge references undeclared node | `"ghost_node"` |
| Duplicate edge `(src, dst)` | `"duplicate_edge"` |
| No `Input` or `Output` node | `"missing_endpoint"` |
| Array parameter required but not provided | `"missing_shape"` |
| Shape contains a non-positive dimension | `"invalid_shape"` |

### 8.3 Unsupported Node Type in Renderer

When `NIR_Renderer._render_node()` encounters a node type not in the 19 primitives, it
emits:

```
# unsupported: nir.CustomNode 'node_name'
```

and continues. No exception is raised. The rendered CNL for the unsupported node's
outgoing/incoming edges is still emitted; the NIR_CNL_Parser will reject those edges
at compile time with `code="ghost_node"` because the referenced name has no node
declaration.

This design keeps rendering non-fatal while ensuring compilation catches the gap.

### 8.4 HTTP Error Responses

`/generate-cnl-from-nir` with unsupported content → HTTP 422:

```json
{
  "code": "unsupported_nir_import",
  "message": "NIR graph contains unsupported node types",
  "diagnostics": [
    {
      "code": "unsupported_primitive",
      "message": "Node 'custom_op' has unsupported type 'nir.CustomNode'",
      "node_id": "custom_op",
      "primitive": "nir.CustomNode",
      "hint": "Supported primitives: Input, Output, IF, LIF, ..."
    }
  ]
}
```

`/parse-cnl` with invalid CNL → HTTP 422:

```json
{
  "message": "CNL parse failed: 2 errors.",
  "unsupported_concepts": []
}
```


## Testing Strategy

### 9.1 PBT Applicability Assessment

The NIR-native CNL feature is a **parser + serializer + data transformation** system.
The core behaviors — rendering to text, parsing from text, compiling to NIR objects —
are pure functions with clear input/output behavior and large input spaces (arbitrary
graph topologies, array shapes, parameter values). Property-based testing is the right
tool for the round-trip and structural correctness properties.

PBT is **not** applied to:
- The API routes (`/generate-cnl`, `/parse-cnl`, etc.) — these are integration tests
- NIR's own structural validation — that is NIR's responsibility, not ours

### 9.2 Property-Based Testing Library

Use **Hypothesis** (Python), version-pinned. Each property test runs a minimum of
**200 iterations** (set via `@settings(max_examples=200)`).

Location: `neurocnl/neurocnl/tests/properties/test_nir_native_cnl_properties.py`

Tag format: `# Feature: nir-native-cnl, Property N: <short description>`

### 9.3 Hypothesis Strategies (Input Generators)

```python
# Strategy: valid NIRGraph with random supported nodes and edges
@composite
def nir_graphs(draw) -> nir.NIRGraph:
    """Generate a random valid NIRGraph with supported primitives."""
    # always include one Input and one Output
    # random selection of 0–4 intermediate nodes from supported types
    # edges form a valid DAG from Input to Output
    ...

@composite
def lif_params(draw) -> dict:
    """Generate random float64 parameter values for nir.LIF."""
    ...

@composite
def weight_matrices(draw) -> np.ndarray:
    """Generate random float64 weight matrices of random valid shapes."""
    ...

@composite
def metadata_dicts(draw) -> dict[str, str | int | float]:
    """Generate random metadata dicts with only str/int/float values."""
    ...

@composite
def valid_shapes(draw) -> tuple[int, ...]:
    """Generate random tuples of positive integers as array shapes."""
    ...
```

### 9.4 Property Test Implementations

Each property test below corresponds to a Correctness Property from Section 6.

**Property 1 — Full Round-Trip Identity:**
```python
# Feature: nir-native-cnl, Property 1: Full round-trip identity
@given(graph=nir_graphs())
@settings(max_examples=200)
def test_round_trip_identity(graph):
    renderer = NIR_Renderer()
    compiler = NIR_Compiler()
    parser = NIR_CNL_Parser()
    cnl = renderer.render(graph)
    records = parser.parse(cnl)
    recovered = compiler.compile(records)
    assert_graphs_equal(graph, recovered)  # checks types, params, edges, arrays
```

**Property 2 — Metadata Round-Trip:**
```python
# Feature: nir-native-cnl, Property 2: Metadata round-trip preservation
@given(node_type=sampled_from(SUPPORTED_PRIMITIVES), meta=metadata_dicts())
@settings(max_examples=200)
def test_metadata_round_trip(node_type, meta):
    graph = build_minimal_graph_with_metadata(node_type, meta)
    cnl = NIR_Renderer().render(graph)
    records = NIR_CNL_Parser().parse(cnl)
    recovered = NIR_Compiler().compile(records)
    for name, node in recovered.nodes.items():
        if name in graph.nodes:
            assert node.metadata == graph.nodes[name].metadata
```

**Property 3 — Node-Sentence Before Edge-Sentence:**
```python
# Feature: nir-native-cnl, Property 3: Node sentences before edge sentences
@given(graph=nir_graphs())
@settings(max_examples=200)
def test_node_sentences_before_edge_sentences(graph):
    cnl = NIR_Renderer().render(graph)
    lines = [l.strip() for l in cnl.splitlines() if l.strip() and not l.startswith('#')]
    node_lines = [i for i, l in enumerate(lines) if not l.startswith('Connect')]
    edge_lines = [i for i, l in enumerate(lines) if l.startswith('Connect')]
    if node_lines and edge_lines:
        assert max(node_lines) < min(edge_lines)
```

**Property 4 — Shape-Only Compilation Produces Zeros:**
```python
# Feature: nir-native-cnl, Property 4: Shape-only produces zeros array
@given(shape=valid_shapes())
@settings(max_examples=200)
def test_shape_only_produces_zeros(shape):
    cnl = f'Input "x" shape {shape}\nLinear "fc" weight shape {shape}\nOutput "y" shape ({shape[0]},)\nConnect "x" -> "fc"\nConnect "fc" -> "y"'
    records = NIR_CNL_Parser().parse(cnl)
    graph = NIR_Compiler().compile(records)
    weight = graph.nodes["fc"].weight
    assert weight.shape == shape
    assert np.all(weight == 0.0)
    assert weight.dtype == np.float64
```

**Property 5 — Bias Shape from Out-Channels:**
```python
# Feature: nir-native-cnl, Property 5: Bias shape derived from weight out-channels
@given(shape=valid_conv2d_shapes())
@settings(max_examples=200)
def test_bias_shape_from_out_channels(shape):
    out_ch = shape[0]
    cnl = build_conv2d_shape_only_cnl(shape)
    graph = NIR_Compiler().compile(NIR_CNL_Parser().parse(cnl))
    assert graph.nodes["conv"].bias.shape == (out_ch,)
```

**Property 6 — No Biological Vocabulary in Output:**
```python
# Feature: nir-native-cnl, Property 6: No biological vocabulary in rendered CNL
BIOLOGICAL_TOKENS = {"MUST", "MUST NOT", "sensory", "motor", "threshold_firing", "refractory_period"}

@given(graph=nir_graphs())
@settings(max_examples=200)
def test_no_biological_vocabulary(graph):
    cnl = generate_cnl_from_nir(graph)
    words = set(re.findall(r'\b\w+\b', cnl))
    assert words.isdisjoint(BIOLOGICAL_TOKENS)
```

**Property 7 — Unknown Parameter Rejected:**
```python
# Feature: nir-native-cnl, Property 7: Unknown parameter name rejected
@given(
    primitive=sampled_from(list(PRIMITIVE_PARAMS.keys())),
    bad_param=text(alphabet=ascii_lowercase, min_size=3).filter(
        lambda s: s not in PRIMITIVE_PARAMS.get(primitive, set())
    ),
)
@settings(max_examples=200)
def test_unknown_parameter_raises(primitive, bad_param):
    cnl = f'{primitive} "n" {bad_param} 1.0'
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    assert any(e["code"] == "unknown_parameter" for e in exc_info.value.errors)
```

**Property 8 — All Parse Errors Collected:**
```python
# Feature: nir-native-cnl, Property 8: All parse errors collected before failing
@given(invalid_lines=lists(text().filter(lambda s: not _matches_any_grammar(s)), min_size=1))
@settings(max_examples=200)
def test_all_parse_errors_collected(invalid_lines):
    cnl = "\n".join(invalid_lines)
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    assert len(exc_info.value.errors) == len(invalid_lines)
```

### 9.5 Unit / Example Tests

Located in `neurocnl/neurocnl/tests/test_nir_native_cnl.py`:

- One example per primitive: render + parse round-trip for each of 18 node types
- `test_unsupported_node_emits_comment`: pass a custom nir.NIRNode subclass to renderer
- `test_ghost_node_raises_compile_error`: CNL with edge to undeclared node
- `test_duplicate_edge_raises_compile_error`: two `Connect "a" -> "b"` lines
- `test_missing_endpoint_raises_compile_error`: CNL with no Input or no Output
- `test_missing_shape_raises_compile_error`: `Linear "fc"` with no weight and no shape
- `test_invalid_shape_raises_compile_error`: `Linear "fc" weight shape (0, 128)`
- `test_metadata_unsupported_type_emits_comment`: node with `metadata["x"] = [1,2,3]`
- `test_http_422_on_unsupported_nir_type`: integration test on the API route

### 9.6 Integration Tests

Located in `neurocnl/neurocnl/tests/test_nir_native_cnl_integration.py`:

- `test_generate_cnl_from_nir_endpoint`: POST real .nir fixture to `/generate-cnl-from-nir`
- `test_parse_cnl_endpoint`: POST NIR-native CNL to `/parse-cnl`, assert valid CanvasGraph
- `test_generate_cnl_endpoint`: POST CanvasGraph with nir_type set, assert NIR-native CNL
- `test_422_on_unsupported_nir_type`: POST .nir with unknown node type, assert 422

