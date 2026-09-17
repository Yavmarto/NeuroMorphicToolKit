# CNL → NIR Developer Guide

This is the primary developer reference for the direct `CNL → IR → NIR`
compilation pipeline implemented in `neurocnl`. It covers every stage of the
pipeline, what goes wrong and why, how to inspect lowering fidelity, and how
to use the result.

For the grammar reference (sentence patterns and examples), see
[`neurocnl/cnl/cnl_grammar.md`](../neurocnl/cnl/cnl_grammar.md).
For per-backend fidelity verdicts, see [`docs/support_matrix.md`](support_matrix.md).
For the architectural decision record, see [`docs/ADR-001-CNL-NIR-Direct-Translation.md`](../docs/ADR-001-CNL-NIR-Direct-Translation.md).

---

## Background

NeuroCNL historically compiled to NIR via Nengo: `CNL → Nengo → NIR`. That
path was bottlenecked by Nengo's primitive coverage and made bidirectional
translation hard (NIR → CNL) because Nengo's stateful simulation objects
carry no clean reverse mapping.

As of ADR-001 (2026-05-14), the primary compilation surface is a direct
`CNL → IR → NIR` path. **Nengo is retained as an optional simulation
execution backend only — it is never constructed during `compile_to_nir()`.**

---

## The Five-Stage Pipeline

```
CNL text (spec : str)
    │
    ▼  Stage 1 — parse
parse_spec_text()                        [neurocnl/pipeline.py]
    │  Returns: list[ParsedSentence]
    │  Errors: ParseError per line
    ▼  Stage 2 — exportability gate
ensure_nir_exportable()                  [neurocnl/export/nir_exporter.py]
    │  Fail-closed: raises ValueError if any concept maps to "not_lowered"
    ▼  Stage 3 — IR lowering
lower_to_ir(parsed_specs)               [neurocnl/ir/lowering.py]
    │  Returns: NetworkIR
    │  Errors: LoweringError
    ▼  Stage 4 — NIR materialization
Materializer().materialize(network_ir)  [neurocnl/ir/materializer.py]
    │  Returns: nir.NIRGraph
    │  Errors: MaterializerError
    ▼  Stage 5 — write to disk (optional)
nir.write(path, graph)                  [nir package]
    │
    ▼
.nir file
```

All five stages are orchestrated by the public entrypoint:

```python
from neurocnl import compile_to_nir, CompileError

graph = compile_to_nir(spec)  # in-memory
graph = compile_to_nir(spec, save_to="out.nir")  # + write to disk
```

The function is **fail-closed**: any stage failure raises `CompileError` with
structured `Diagnostic` objects rather than silently producing a dishonest
graph.

---

## Stage 1: Parsing (`parse_spec_text`)

### What it does

`parse_spec_text(spec)` passes each non-empty, non-`#` line through a
regex-based dispatcher in `cnl_parser.py`. The dispatcher tests 21 concept
pattern groups in declaration order and returns the first match.

### Output shape

Each line produces a `ParsedSentence` TypedDict:

```python
{
    "concept": "threshold_firing",
    "subject": "sensory neuron",
    "action": "fire",
    "verb": "MUST",
    "negated": False,
    "condition": "membrane potential exceeds 1.0",
    "raw": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
    "line": 3,  # only when called with a line number
    # concept-specific extras:
    "matrix_kind": ...,  # synaptic_weight only
    "weight_matrix": ...,
    "weight_shape": ...,
    "shape": ...,  # population_coding, network_topology
    "connectivity_pattern": ...,  # spatial_connectivity
    "connectivity_mask": ...,
    "connection_density": ...,
    "locality_radius": ...,
}
```

### Important parser constraints

- **`synaptic_weight`** requires the literal subject form
  `The connection from <X> to <Y>`. Shorthand like `The sensory to motor
  connection` will not match.
- **`threshold_firing`**, **`refractory_period`**, and
  **`membrane_potential_decay`** require subjects that end with `neuron`
  or `population`.
- **`timing_declaration`** only accepts three strict sentence families:
  `operate WITH timestep of`, `use discrete delays quantized to`, and
  `run AT Nx biological speed`.
- Parsing is case-insensitive throughout.

### The four required concepts for NIR compilation

A spec that omits any of these will fail at the exportability gate because
a valid LIF-based NIR graph cannot be emitted without them:

1. `threshold_firing` (maps to `nir.LIF.v_threshold`)
2. `membrane_potential_decay` (maps to `nir.LIF.tau`)
3. `synaptic_weight` (maps to `nir.Linear.weight`)
4. `network_topology` or `population_coding` (declares populations so
   `nir.Input`/`nir.Output` boundaries can be synthesized)

---

## Stage 2: Exportability Gate (`ensure_nir_exportable`)

### What it does

Before expensive IR lowering, the gate checks that every concept in the spec
has a fidelity verdict that is not `"not_lowered"`. Concepts rated
`"not_lowered"` cannot be represented in NIR even as advisory metadata, so
compiling them would produce a silently wrong graph.

### Concepts currently blocked (`"not_lowered"`)

| Concept | Reason |
|---|---|
| `akida_hardware` | Akida routing is handled by the Neurochip module, not the NIR materializer |
| `akida_spatiotemporal` | Same as above |

If your spec includes either of these, `compile_to_nir()` will raise
`CompileError` at stage 2 with `code="unsupported_concepts"`.

---

## Stage 3: IR Lowering (`lower_to_ir`)

### What it does

`lower_to_ir(parsed_specs)` walks each `ParsedSentence` and merges its
semantics into a `NetworkIR` typed graph. The IR is backend-agnostic and
carries full provenance (source line, raw sentence, concept name) on every
population, connection, learning rule, and timing declaration.

### `NetworkIR` structure

```python
@dataclass
class NetworkIR:
    populations: dict[str, PopulationIR]
    connections: list[ConnectionIR]
    learning_rules: list[LearningRuleIR]
    timing_declarations: list[TimingDeclarationIR]
    akida_hardware: AkidaHardwareIR | None
    akida_connection_properties: list[AkidaConnectionPropertyIR]
    metadata: dict  # neuromodulation_rules, global_receptor_dynamics, etc.
```

### `PopulationIR` key fields

| Field | Set by concept |
|---|---|
| `size` | `population_coding`, `network_topology` |
| `dimensions` | `population_coding` |
| `shape` | `population_coding` (optional) |
| `role` | `"input"` or `"output"` for boundary populations |
| `threshold` | `threshold_firing` |
| `refractory_period` | `refractory_period` |
| `membrane_time_constant` | `membrane_potential_decay` |
| `attributes["adaptive_spiking_enabled"]` | `adaptive_spiking` |
| `attributes["homeostatic_target_rate_hz"]` | `homeostatic_plasticity` |
| `attributes["background_noise_value"]` | `background_noise` |

### `ConnectionIR` key fields

| Field | Set by concept |
|---|---|
| `weight` | `synaptic_weight`, `inhibitory_connection` |
| `polarity` | `"excitatory"` or `"inhibitory"` |
| `delay` | `axonal_delay` |
| `connectivity_pattern` | `spatial_connectivity`, `lateral_inhibition` |
| `attributes["receptor_type"]` | `receptor_dynamics` |
| `attributes["short_term_plasticity_type"]` | `short_term_plasticity` |

### Population name normalization

The lowering layer normalizes population subjects before using them as
dictionary keys. The rules are:
- Strip leading `The ` / `A `.
- Strip trailing ` neuron`, ` neurons`, ` population`, ` populations`, ` membrane potential`.
- Lowercase and collapse whitespace.
- `"input population"` → `"input"`, `"output population"` → `"output"`.

This is why a sentence like
`The sensory population MUST encode input using 100 neurons` and
`The connection from sensory to motor MUST have WITH synaptic weight of 0.5`
correctly resolve to the same `"sensory"` population key.

---

## Stage 4: NIR Materialization (`Materializer`)

### What it does

`Materializer().materialize(network_ir)` converts the semantic `NetworkIR`
into a tensor-backed `nir.NIRGraph`:

1. **Dimension inference** — derives flattened neuron counts from `size`,
   `shape` (product of axes), or `dimensions`, falling back to
   `default_population_size = 1`.
2. **Node creation** — maps each `PopulationIR` to one of:
   - `nir.Input` (role == `"input"`)
   - `nir.Output` (role == `"output"`)
   - `nir.LIF` (all others)
3. **Weight synthesis** — creates `nir.Linear` nodes for each `ConnectionIR`.
   See [Weight synthesis](#weight-synthesis) below.
4. **Delay nodes** — where a connection has an effective delay, inserts a
   `nir.Delay` node between the weight and the target LIF.
5. **Synthetic I/O boundaries** — auto-injects `nir.Input` for populations
   with no incoming connections, and auto-injects `nir.Output` for leaf nodes
   when no explicit output population exists.

### Weight synthesis

| Connection description | Result in NIR |
|---|---|
| Scalar weight `w` | Dense `(target, source)` matrix filled with `sign * abs(w)` |
| Explicit 2D matrix `[[...]]` | Exact `nir.Linear.weight` tensor |
| Identity matrix declaration | `np.eye(N)` |
| Diagonal matrix `[d1, d2, ...]` | `np.diag([d1, d2, ...])` |
| One-to-one (`connectivity_pattern`) | Diagonal weight matrix |
| Explicit binary mask | `mask * scalar_weight` |
| STP depression with `utilization_rate` | Weight scaled by `(1 − utilization_rate)` |
| Lateral inhibition (with shape info) | Local-radius inhibitory mask |
| Lateral inhibition (no shape) | Dense negative matrix, zero diagonal |

---

## NIR Fidelity Reference

Every concept gets one of four verdicts in the lowering summary attached to
`graph.metadata["nir_lowering_summary"]["concepts"]`:

| Verdict | Meaning |
|---|---|
| `lowered_faithfully` | Concept is fully represented as executable NIR structure |
| `lowered_as_metadata` | Concept is stored in node/graph metadata; no executable NIR operator is emitted |
| `lowered_approximately` | NIR structure is emitted but relies on heuristics; semantics are not exact |
| `not_lowered` | Concept is blocked at the exportability gate (spec will be rejected) |

### Per-concept verdicts

| Concept | NIR Verdict | Details |
|---|---|---|
| `threshold_firing` | **faithfully** | → `nir.LIF.v_threshold` |
| `membrane_potential_decay` | **faithfully** | → `nir.LIF.tau` |
| `synaptic_weight` | **faithfully** | → `nir.Linear.weight`; matrix forms are exact |
| `inhibitory_connection` | **faithfully** | → negative `nir.Linear.weight` |
| `axonal_delay` | **faithfully** (when numeric) | → executable `nir.Delay` node; if no explicit delay is set, no delay node is emitted |
| `refractory_period` | metadata only | Stored in `nir.LIF.metadata["refractory_period"]` |
| `stdp_learning` | metadata only | Stored in `nir.Linear.metadata` or graph metadata |
| `timing_declaration` | metadata only | Consistency-checked; stored in `graph.metadata["timing_declarations"]` |
| `adaptive_spiking` | metadata only | Stored in `nir.LIF.metadata["adaptive_spiking_enabled"]` |
| `receptor_dynamics` | metadata only | Stored in `nir.Linear.metadata` or `graph.metadata["global_receptor_dynamics"]` |
| `background_noise` | metadata only | Stored in `nir.LIF.metadata["background_noise_value"]` |
| `population_coding_range` | metadata only | Stored in `nir.LIF.metadata["population_coding_range_degrees"]` |
| `neuromodulation` | metadata only | Schema-validated; stored in `graph.metadata["neuromodulation_rules"]` |
| `population_coding` | approximately | Population size/shape is correct; abstract encoding semantics are not emitted as NIR operators |
| `network_topology` | approximately | Population structure is correct; multi-target projections are dense Linear weights |
| `short_term_plasticity` | approximately (depression + utilization rate) / metadata only (facilitation, no utilization rate) | Depression with numeric `utilization_rate` scales `Linear.weight`; all other forms are metadata-only |
| `homeostatic_plasticity` | approximately / metadata only | When `homeostatic_target_rate_hz` is a numeric value, `v_threshold` is adjusted as `rate × tau`; otherwise metadata-only |
| `lateral_inhibition` | approximately | Shape-aware: generates local-radius inhibitory mask; shape-unaware: dense negative matrix with zero diagonal + warning |
| `spatial_connectivity` | partially / metadata only | One-to-one and binary-mask lower to exact dense weights; locality-radius and probability-based forms remain metadata-only |
| `akida_hardware` | **not_lowered** | Blocked at exportability gate |
| `akida_spatiotemporal` | **not_lowered** | Blocked at exportability gate |

---

## Inspecting Lowering Fidelity

The graph carries a full fidelity summary in its metadata:

```python
import json
from neurocnl import compile_to_nir

graph = compile_to_nir(spec)
summary = graph.metadata["nir_lowering_summary"]

# Per-concept verdicts
print(json.dumps(summary["concepts"], indent=2))

# Connection-level summary
print(json.dumps(summary["connections"], indent=2))

# Advisory warnings (approximations, missing shape info, etc.)
for key, msg in summary["warnings"].items():
    print(f"[WARNING] {msg}")
```

Example output for a spec with STDP and homeostatic plasticity:

```json
{
  "concepts": {
    "threshold_firing":      "lowered_faithfully",
    "membrane_potential_decay": "lowered_faithfully",
    "synaptic_weight":       "lowered_faithfully",
    "inhibitory_connection": "lowered_faithfully",
    "stdp_learning":         "lowered_as_metadata",
    "homeostatic_plasticity":"lowered_approximately"
  },
  "warnings": {
    "warning_0": "Connection 'sensory' -> 'motor' stores learning rules as metadata..."
  }
}
```

---

## Error Handling

All errors from `compile_to_nir()` are raised as `CompileError` and carry
structured `Diagnostic` objects:

```python
from neurocnl import compile_to_nir, CompileError

try:
    graph = compile_to_nir(spec)
except CompileError as exc:
    for d in exc.diagnostics:
        loc = f" (line {d.line})" if d.line else ""
        hint = f"\n  hint: {d.hint}" if d.hint else ""
        print(f"[{d.stage}] {d.code}: {d.message}{loc}{hint}")
```

| `d.stage` | `d.code` | Meaning |
|---|---|---|
| `"parse"` | `"parse_error"` | A CNL sentence did not match any grammar pattern |
| `"parse"` | `"empty_spec"` | Spec contained no parseable sentences |
| `"exportability"` | `"unsupported_concepts"` | Spec contains `akida_hardware` or `akida_spatiotemporal` |
| `"lowering"` | `"lowering_error"` | IR lowering raised `LoweringError` (e.g. conflicting field values) |
| `"materializer"` | `"materializer_error"` | NIR materialization failed (e.g. mismatched matrix dimensions) |
| `"write"` | `"write_error"` | Compilation succeeded but the `.nir` file could not be written |

---

## Worked Example

> **Note:** the `MUST`/`WITH` examples below are the legacy,
> biological-style grammar — a separate pipeline from the `nir_cnl`
> dialect `compile_to_nir` actually compiles today (which rejects this
> grammar with an actionable `legacy_grammar` error). The `nir_cnl`
> equivalent of the minimal example below is:
>
> ```
> Define a network named demo with timestep 0.001.
> Define an input port named input with shape (4,).
> Define a LIF neuron named input_lif with time constant 0.02, resistance 1.0,
>   leak voltage 0.0, and firing threshold 1.0.
> Define an output port named output with shape (2,).
> input connects to input_lif.
> input_lif connects to output.
> ```
>
> The optional `with timestep <seconds>` clause on the network sentence
> propagates into every `nir.LIF` node's `metadata["dt"]`, which the
> snnTorch notebook codegen (`backend/app/routers/notebook.py`) uses for
> its `beta`/`threshold` conversion. Without a declared timestep, that
> conversion falls back to a fixed `1e-4` default, which for typical
> `tau`/`threshold` values can produce an effectively unreachable firing
> threshold — declare a timestep close to your neurons' time constant to
> keep training viable.

### Minimal LIF network

```python
from neurocnl import compile_to_nir

spec = """
# Minimal feed-forward LIF network
The network MUST operate WITH timestep of 1 ms

The network MUST contain an excitatory input population of 4 neurons
The network MUST contain an excitatory output population of 2 neurons

The input MUST project to output
The connection from input to output MUST have WITH synaptic weight of 0.5

The input membrane potential MUST decay WITH time constant of 0.02 seconds
The output membrane potential MUST decay WITH time constant of 0.02 seconds
The input MUST fire ONLY IF membrane potential exceeds 1.0
The output MUST fire ONLY IF membrane potential exceeds 1.0
"""

graph = compile_to_nir(spec)
print(list(graph.nodes.keys()))
# ['input', 'weight_input_to_output_0', 'output']
```

### With axonal delay

```python
spec += "\nThe connection from input to output MUST transmit WITH delay of 5ms"
graph = compile_to_nir(spec)
print(list(graph.nodes.keys()))
# ['input', 'weight_input_to_output_0', 'delay_input_to_output_0', 'output']
```

### With STDP (metadata only, but compiles cleanly)

```python
spec += "\nThe connection from input to output MUST adapt WITH STDP learning rate of 0.01"
graph = compile_to_nir(spec)
# stdp_learning → lowered_as_metadata (no CompileError)
```

### Saving to disk

```python
graph = compile_to_nir(spec, save_to="my_network.nir")
```

### Loading back

```python
import nir

graph = nir.read("my_network.nir")
```

---

## NIR → CNL (Reverse Direction)

The `neurocnl` package also supports translating a `nir.NIRGraph` back into
readable CNL text. This path is used by the Flutter Studio's import feature
and by the `POST /api/nir/import` endpoint. See
[`docs/nir_to_cnl_translation_plan.md`](nir_to_cnl_translation_plan.md) and
`neurocnl/neurocnl/tests/test_nir_to_cnl.py` for implementation details.

The round-trip fidelity is highest for feed-forward networks whose semantics
are fully described by populations, dense weighted projections, inhibitory
sign, and explicit timing — the subset that lowers faithfully in the forward
direction.

---

## Known Gaps and Limitations

### Round-trip breakage between `/api/generate` and the parser

The `/api/generate` endpoint emits canonical CNL lines like `MUST inhibit`
and `MUST exhibit STDP` that the parser **does not accept**. This means
generated CNL cannot be fed back into the compiler without manual editing.
See `neurocnl/docs/CODE_REVIEW_CRITICAL_2026-05-14.md`.

### `/api/validate` can return `overall: true` for IR-unlowerable specs

Validation (`/api/validate`) operates on the parsed representation and the
parameter extractor, not on the full IR lowering path. A spec that passes
validation may still fail `compile_to_nir()` at the lowering stage.
Use `compile_to_nir()` directly if you need a guarantee that a spec produces
a valid NIR graph.

### `akida_hardware` and `akida_spatiotemporal` are blocked

These two concepts are parsed and lower to IR correctly, but `compile_to_nir()`
rejects them at the exportability gate. Akida deployment goes through the
Neurochip module (`POST /api/neurochip/akida/deploy`), not through the
standard NIR path. The planned `POST /akida/deploy/nir` endpoint (which would
accept a `nir.NIRGraph` and wire it to the BrainChip SDK) has not yet been
implemented.

### Facilitation-type STP is metadata-only

Only `short_term_plasticity` of subtype `depression` with a numeric
`utilization_rate` lowers approximately to a scaled weight. Facilitation, and
any depression rule without an explicit `utilization_rate`, are metadata-only.

### Locality-based and probability-based spatial connectivity are metadata-only

`spatial_connectivity` sentences using `distance-dependent probability` or
`local connections WITHIN radius` lower to IR but produce metadata-only
output from the materializer. Only `one-to-one` and explicit `binary mask`
forms generate executable NIR `Linear` weights.

---

## File Map

| File | Role |
|---|---|
| `neurocnl/compile.py` | Public `compile_to_nir()` entrypoint; stages 1–5 orchestration |
| `neurocnl/pipeline.py` | `parse_spec_text()` and full pipeline for Nengo/validation path |
| `neurocnl/cnl/cnl_parser.py` | Regex grammar; 21 concepts; `parse()` and `parse_spec_text()` |
| `neurocnl/cnl/cnl_grammar.md` | Grammar reference document (parser-first) |
| `neurocnl/ir/types.py` | `NetworkIR`, `PopulationIR`, `ConnectionIR`, etc. |
| `neurocnl/ir/lowering.py` | `lower_to_ir()`; `SUPPORTED_CONCEPTS`; per-concept lowering logic |
| `neurocnl/ir/materializer.py` | `Materializer`; `_FAITHFUL_CONCEPTS`, `_METADATA_ONLY_CONCEPTS`, `_APPROXIMATE_CONCEPTS`; fidelity summary |
| `neurocnl/ir/metadata_schema.py` | Advisory semantics schema helpers |
| `neurocnl/ir/timing_validator.py` | Timing declaration consistency checks |
| `neurocnl/export/nir_exporter.py` | `ensure_nir_exportable()`; `_NIR_CONCEPT_VERDICTS` static map; legacy Nengo-to-NIR path |
| `neurocnl/cnl_explained.md` | Broader pipeline reference (parse → validate → generate) |
| `docs/ADR-001-CNL-NIR-Direct-Translation.md` | Architectural decision record |
| `docs/support_matrix.md` | Per-backend fidelity verdicts |
