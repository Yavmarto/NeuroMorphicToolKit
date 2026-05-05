# Direct Compilation from NeuroCNL to NIR

This plan outlines the architecture and execution steps required to bypass Nengo and compile NeuroCNL's high-level semantic `NetworkIR` directly into a quantitative, tensor-based `nir.NIRGraph`.

## Key Architectural Decisions

- **STDP and Learning Rules:** We will preserve STDP and learning rules from the `LearningRuleIR` as custom metadata attached to the appropriate `nir.NIRGraph` nodes/edges. This ensures no semantic loss while keeping the primary execution graph valid for standard NIR tools.
- **Synthesized Weight Initialization:** The materializer will generate weight matrices using a default uniform distribution scaled by the connection's base `weight` value to synthesize the multidimensional structures required by NIR.

## Proposed Changes

### 1. Materialization Layer

Introduce a new step in the compiler pipeline that bridges the semantic IR and the tensor-based NIR graph.

#### [NEW] `neurocnl/neurocnl/ir/materializer.py`
- Implement a `Materializer` class that consumes `NetworkIR`.
- **Dimension Inference:** Traverse `PopulationIR` definitions to ensure all populations have a concrete `size` or `dimensions` (falling back to a default if left abstract by the user).
- **Weight Synthesis:** Generate `numpy.ndarray` matrices for `ConnectionIR` instances.
  - `polarity="excitatory"` -> Generate positive weight arrays.
  - `polarity="inhibitory"` -> Generate negative weight arrays.
- **Node Materialization:** Map `PopulationIR` constraints (threshold, refractory period) to `nir.LIF` parameter arrays, expanding scalar constants into vectors that match the population size.
- **Metadata Preservation:** Attach `LearningRuleIR` definitions (e.g. STDP parameters) into the `metadata` dictionaries of the resulting `nir.Linear` / `nir.LIF` nodes.
- **Output:** Returns a fully constructed `nir.NIRGraph`.

### 2. Updating Exporters and Pipeline

Refactor the existing NIR exporter and compiler pipeline to use the materialization layer instead of extracting values from an intermediate Nengo network.

#### [MODIFY] `neurocnl/neurocnl/export/nir_exporter.py`
- Deprecate or bypass the Nengo-dependent extraction logic (e.g., `_extract_weight` and Nengo graph traversal).
- Update the `export_to_nir` function signature to accept a `NetworkIR` instead of `nengo.Network`.
- Route the `NetworkIR` through the new `Materializer` to generate and save the `nir.NIRGraph`.

#### [MODIFY] `neurocnl/neurocnl/pipeline.py`
- Update the compiler routing logic. When the target backend is `nir` (or a backend inheriting from NIR), route the `NetworkIR` directly to `export_to_nir` without invoking the `nengo_generator.py` phase.

### 3. Explicit I/O Concept Expansion

NIR strictly requires `nir.Input` and `nir.Output` nodes for graph entry and exit points. We must ensure CNL explicitly defines these boundaries.

#### [MODIFY] `neurocnl/neurocnl/ir/types.py`
- Add explicit support for `role="input"` and `role="output"` attributes to differentiate external stimuli and readouts from standard hidden populations.

#### [MODIFY] `neurocnl/neurocnl/ir/lowering.py`
- Update the lowering logic so that sentences describing external stimulus (e.g., "An input population of 10 neurons projects to...") accurately set the `role="input"` attribute in the IR, ensuring the Materializer converts them to `nir.Input` nodes rather than `nir.LIF` nodes.

## Verification Plan

### Automated Tests
- **Materializer Unit Tests** (`tests/ir/test_materializer.py`): Verify that the materializer correctly generates `numpy` weight matrices of the correct shapes (`[target_dim, source_dim]`) and correct signs based on connection polarity, and that STDP rules are properly serialized into node metadata.
- **Pipeline Integration Tests** (`tests/export/test_nir_integration.py`): Verify that a full CNL script is parsed, lowered, materialized, and written to a valid `.nir` file successfully without instantiating any Nengo objects.
