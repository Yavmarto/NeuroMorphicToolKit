# Implementation Plan: NIR to CNL Semantic Translation (Bidirectional Bridge)

## 1. Executive Summary
This plan outlines the architecture and implementation steps to achieve a complete `NIR -> NetworkIR -> CNL` path inside NeuroCNL and Studio.

The key design choice is to make NIR-backed graph state the canonical model used throughout the app wherever the user is working with a network graph. The simulation viewer and canvas beside the CNL editor should therefore operate on the same underlying graph representation that powers simulation previews and export planning. CNL then becomes a human-readable semantic representation of that graph, not a second independent source of truth.

Instead of forcing a lossy 1:1 mathematical mapping, this approach treats CNL as a semantic overlay or architectural summary, while NIR remains the execution-accurate graph with exact tensors and topology.

### The canonical-state rule

- In-app graph state: canonical, NIR-backed, shared by canvas, simulation preview, and export/deploy surfaces
- CNL text: readable semantic view regenerated from the graph and reparsed back into the graph pipeline
- `.nir` artifact: exact execution structure and weights
- `.cnl` artifact: readable intent, roles, topology, and advisory semantics

### The dual-artifact model

- `model_weights.nir`: exact graph, tensor shapes, weights, and execution-facing metadata
- `model_architecture.cnl`: human-readable semantic description derived from the graph and enriched with NeuroCNL concepts where possible

---

## 2. Architecture & Mappings

The translation pipeline introduces and formalizes this path:

`NIRGraph -> NetworkIR -> CNL Text`

Inside Studio, the larger flow becomes:

`CNL Editor <-> parse/lower -> NetworkIR -> materialize -> NIR-backed graph state <-> canvas / simulation viewer`

The `NIR -> CNL` bridge is the missing reverse leg needed to keep the editor and graph surfaces synchronized without maintaining two unrelated models.

### 2.1 Mapping Rules (NIR to NetworkIR)
A dedicated importer will traverse `nir.NIRGraph` and map primitives back to NeuroCNL's semantic IR (`PopulationIR`, `ConnectionIR`, and related metadata-bearing structures). The importer should prefer honest summarization over fake exactness.

| NIR Primitive | CNL Role (IR) | Translation Logic |
| :--- | :--- | :--- |
| `nir.Input` | `sensory neuron` | Map `shape` to population `size`. |
| `nir.Output` | `motor neuron` | Map `shape` to population `size`. |
| `nir.LIF`, `nir.CubaLIF`, etc. | `interneuron` | Map tensor shape to `size`. Summarize threshold, leak, and time constants into representative parameters only when that summary is honest. |
| `nir.Linear`, `nir.Conv2d` | Topology (edges) | Preserve connectivity and footprint shape. Do not pretend the original authoring syntax is recoverable if only the compiled graph remains. |
| Unsupported or specialized primitives | advisory block / structured warning | Emit a fallback summary plus structured diagnostic metadata so the UI can tell the user what was preserved vs. approximated. |

### 2.2 Template Generation (NetworkIR to CNL Text)
Once `NetworkIR` is populated, a generator should emit valid NeuroCNL sentences that are:

- grammatically re-parseable
- semantically conservative
- explicit about approximations
- stable enough for round-trip editing in Studio

Representative templates:

- Population: `"There is a {role} population named '{name}' with a size of {size}."`
- Parameter: `"The {name} population has a nominal threshold of {threshold}."`
- Connection: `"The network topology connects '{source}' to '{target}' with a {shape} connection footprint."`
- Fallback: `"The network contains a specialized '{type}' processing block named '{name}'."`

### 2.3 Where this fits in the current implementation

Today the repo already has:

- a direct `CNL -> IR -> NIR` path
- NIR-based previews and exporters
- some graph/CNL synchronization in Studio and NeuroSim, but not a fully canonical round-trip model

What is missing is:

- a supported `NIR -> NetworkIR -> CNL` bridge
- a shared invariant that the canvas/viewer graph and CNL text are two views of the same underlying graph
- structured reverse-translation diagnostics for unsupported NIR primitives

This plan closes that gap rather than replacing the existing forward exporter.

---

## 3. Implementation Steps

### Phase 0: Establish the canonical graph invariant

Before building the importer, document and enforce that the simulation viewer/canvas next to the editor is graph-backed by NIR-derived state. This prevents the reverse translation work from becoming another sidecar serializer.

Tasks:

- audit the current Studio/NeuroSim bridge points where graph state and CNL state can drift
- identify the single graph contract that simulation preview, export preview, and canvas editing will share
- make structured diagnostics part of that shared state so approximation is visible in the UI

### Phase 1: Build the NIR importer (`neurocnl/import/nir_importer.py`)

Task:

- load a `.nir` file or in-memory `nir.NIRGraph`
- reconstruct a best-effort `NetworkIR`
- preserve reverse-translation diagnostics alongside the IR

Details:

- iterate over `graph.nodes` and classify inputs, outputs, populations, transforms, and specialized blocks
- extract shapes, dimensions, and representative neuron parameters where they are honestly derivable
- walk `graph.edges` to rebuild connection structure
- preserve execution-exact details in metadata instead of pretending they round-trip to exact original prose

### Phase 2: Build the CNL text generator (`neurocnl/generation/cnl_generator.py`)

Task:

- generate valid CNL text from `NetworkIR` plus reverse-translation diagnostics

Details:

- emit stable sentences for recognized populations, parameters, and topology
- inject explicit fallback sentences for specialized or approximate blocks
- ensure output conforms to `neurocnl/cnl/cnl_grammar.md` closely enough to be reparsed by the existing parser

### Phase 3: Pipeline and backend integration (`neurocnl/pipeline.py` and routers)

Task:

- expose reverse translation as a first-class pipeline capability

Details:

- add a function such as `generate_cnl_from_nir(nir_source) -> str`
- add a richer variant that can also return diagnostics, e.g. generated CNL plus unsupported/approximate block summaries
- update backend routes so users can upload `.nir` files or request a CNL summary of the current graph state

### Phase 4: Studio/NeuroSim integration

Task:

- make the editor, canvas, and simulation viewer consume the same graph state and use the new bridge for reverse sync

Details:

- use graph edits to trigger `NIR -> NetworkIR -> CNL` regeneration
- use CNL edits to trigger the existing parse/lower/materialize flow back into graph state
- surface reverse-translation warnings inline instead of silently dropping graph features

### Phase 5: Testing and validation (`neurocnl/tests/` and consumer surfaces)

Task:

- ensure the bridge is honest, stable, and useful for editing

Tests:

1. `CNL -> NetworkIR -> NIR -> NetworkIR -> CNL` preserves semantic intent for supported concepts
2. `NIR -> CNL -> NetworkIR` preserves topology and role summaries for supported primitives
3. Unsupported primitives produce structured diagnostics and fallback text rather than fake exact CNL
4. Studio graph/CNL synchronization uses the same canonical graph model and does not silently diverge

---

## 4. Design Constraints And Edge Cases

- Unsupported primitives must fail closed semantically. The bridge may summarize them, but it must not claim exact CNL recovery when that is impossible.
- Hierarchical subgraphs may be flattened initially unless and until CNL gains first-class subgraph grammar.
- Existing forward-export metadata should be expanded where useful so reverse translation can recover advisory semantics such as plasticity annotations more faithfully.
- Reverse translation should distinguish:
  - exact executable structure recovered from NIR
  - advisory metadata recovered from annotations
  - human-friendly summaries inferred from compiled graph shape

## 5. Deliverables

- `neurocnl/import/nir_importer.py`
- `neurocnl/generation/cnl_generator.py`
- pipeline helper(s) for `generate_cnl_from_nir(...)`
- backend route(s) for `.nir` to CNL summarization
- Studio/NeuroSim integration using the shared graph model
- regression tests for reverse translation and round-trip editing
