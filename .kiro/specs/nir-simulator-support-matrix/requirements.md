# Requirements Document

## Introduction

The `neurocnl` simulator pipeline routes compiled NIR graphs through two backends: `lava_sim` (Intel Lava low-level process simulator) and `snntorch_sim` (snnTorch fixed-weight inference simulator). The verdict for each NIR node type is sourced from a static table in `neurocnl/runtime/nir_support.py`. That table currently covers only six node types per backend; the remaining eleven NIR primitives silently fall through to `"unsupported"` even when the adapters can — or should be extended to — handle them.

This causes two observable failures:

1. Valid NIR graphs that contain `Affine`, `Conv2d`, `Flatten`, `IF`, or `AvgPool2d` nodes are rejected at `POST /api/simulators/run` with HTTP 422, even though the official NIR support matrix (neuroir.org/docs/supported-primitives) lists those primitives as supported by snnTorch and, in several cases, by Lava-DL as well.
2. `GET /api/simulators/capabilities` cannot report those node types as unsupported because they are absent from the table, so users see an incomplete picture before clicking Run.

This feature expands the support table to cover all 17 known NIR primitives with honest, explicit verdicts, extends both adapters to implement the primitives they claim to support, and corrects the capabilities endpoint and documentation.

**Scope boundary:** The Lava adapter used here is `lava-nc` (low-level Lava processes — `lava.proc.lif`, `lava.proc.dense`), not `lava-dl` (the higher-level deep-learning library that the official NIR community targets). Some primitives that Lava-DL natively supports are marked `"unsupported"` for `lava_sim` because `lava-nc` does not expose the necessary process types. Those decisions are recorded explicitly in the table with comments so future maintainers can promote them when Lava-DL integration is added.

---

## Glossary

- **NIR**: Neuromorphic Intermediate Representation — the portable graph format used as the CNL compilation target.
- **NIR Primitive**: One of the standardised node types defined by the NIR specification (e.g. `nir.LIF`, `nir.Affine`).
- **Support Verdict**: One of three string constants — `"exact"`, `"approximate"`, or `"unsupported"` — that classify how faithfully a backend executes a NIR primitive.
- **Support Table** (`_BACKEND_NIR_SUPPORT`): The Python dictionary in `nir_support.py` that maps `backend_name → {node_type → support_verdict}`.
- **SnnTorch_Adapter** (`SnnTorchSimulatorAdapter`): The in-process snnTorch simulator adapter in `snntorch_simulator.py`.
- **Lava_Adapter** (`LavaSimulatorAdapter`): The Lava software simulator adapter in `lava_simulator.py`.
- **Capabilities_Endpoint**: `GET /api/simulators/capabilities`, which returns per-backend `supported_nir_nodes`, `unsupported_nir_nodes`, and `approximate_semantics` lists.
- **Classifier** (`classify_nir_graph`): The function in `nir_support.py` that inspects a compiled NIR graph and returns a `SupportClassification`.
- **Support_Matrix_Doc**: `docs/support_matrix.md`, the human-readable canonical reference for backend support claims.
- **Complete_Primitive_Set**: The set of all NIR primitives that must have an explicit entry in the Support Table: `Input`, `Output`, `Linear`, `Affine`, `Conv2d`, `Flatten`, `IF`, `LIF`, `CubaLIF`, `LI`, `AvgPool2d`, `SumPool2d`, `Delay`, `Scale`, `Threshold`, `Sigmoid`, `Tanh`.

---

## Requirements

### Requirement 1: Explicit Support Verdicts for All NIR Primitives

**User Story:** As a CNL developer, I want every NIR primitive to have an explicit support verdict in the support table, so that no node type can silently fall through to an incorrect default.

#### Acceptance Criteria

1. THE Support_Table SHALL contain an explicit entry for every member of the Complete_Primitive_Set for both `lava_sim` and `snntorch_sim`.
2. WHEN the Classifier evaluates a NIR graph node whose type is a member of the Complete_Primitive_Set, THE Classifier SHALL derive the verdict from the explicit table entry rather than falling through to any default.
3. THE Support_Table SHALL assign `"exact"` to a primitive if and only if the corresponding adapter contains a working implementation that faithfully reproduces that primitive's semantics.
4. THE Support_Table SHALL assign `"approximate"` to a primitive if and only if the corresponding adapter executes the primitive with documented, known semantic limitations.
5. THE Support_Table SHALL assign `"unsupported"` to a primitive when the corresponding adapter cannot execute the primitive, with an inline code comment recording the reason.
6. IF a NIR graph contains a node type that is not a member of the Complete_Primitive_Set, THEN THE Classifier SHALL assign it a verdict of `"unsupported"` and include it in `SupportClassification.unsupported_nodes`.

---

### Requirement 2: snnTorch Adapter Handles All snnTorch-Supported Primitives

**User Story:** As a CNL developer, I want the snnTorch adapter to execute all NIR primitives that snnTorch genuinely supports, so that valid snnTorch networks are not rejected at runtime.

#### Acceptance Criteria

1. WHEN a NIR graph contains a `nir.Affine` node, THE SnnTorch_Adapter SHALL map it to a `torch.nn.Linear` layer initialised with the weight matrix and bias vector from the NIR node.
2. WHEN a NIR graph contains a `nir.Conv2d` node, THE SnnTorch_Adapter SHALL map it to a `torch.nn.Conv2d` layer using the weight, stride, and padding parameters from the NIR node.
3. WHEN a NIR graph contains a `nir.Flatten` node, THE SnnTorch_Adapter SHALL map it to a `torch.nn.Flatten` layer that reshapes the input tensor to a 1-D vector before passing it to the next layer.
4. WHEN a NIR graph contains a `nir.IF` node, THE SnnTorch_Adapter SHALL map it to a `snntorch.Lapicque` neuron configured with an effectively infinite membrane time constant and a threshold derived from the NIR node's `v_threshold`.
5. WHEN a NIR graph contains a `nir.AvgPool2d` node, THE SnnTorch_Adapter SHALL map it to a `torch.nn.AvgPool2d` layer using the kernel size and stride from the NIR node.
6. WHEN the working adapter implementations for `Affine`, `Conv2d`, `Flatten`, `IF`, and `AvgPool2d` are present in SnnTorch_Adapter, THE Support_Table SHALL record `"exact"` for `snntorch_sim` against each of those primitives.
7. WHEN any of the newly implemented node types is executed, THE SnnTorch_Adapter SHALL not emit an `"unsupported"` skip warning in `SnnTorchSimulatorResult.warnings`.

---

### Requirement 3: Lava Adapter Verdicts Reflect lava-nc Capabilities

**User Story:** As a CNL developer, I want the Lava support table entries to reflect what the lava-nc adapter actually implements (not what lava-dl supports), so that the verdicts are honest and traceable.

#### Acceptance Criteria

1. THE Support_Table SHALL record `"unsupported"` for `lava_sim` against `Affine`, `Conv2d`, `Flatten`, `IF`, `AvgPool2d`, and `SumPool2d`, because `lava-nc` low-level process types for those primitives are not available.
2. THE Support_Table entry for each `"unsupported"` lava-nc primitive SHALL include an inline code comment citing the specific reason (e.g. `# lava-nc has no Conv process; lava-dl netx is out of scope`).
3. WHEN the Lava_Adapter receives a NIR graph that contains a node type it cannot handle, THE Lava_Adapter SHALL immediately raise `LavaDispatchError` with a diagnostic message naming each unsupported node type before attempting any execution.
4. THE Support_Table SHALL retain `"exact"` verdicts for `lava_sim` against `Input`, `Output`, `LIF`, `CubaLIF`, and `Linear`.
5. THE Support_Table SHALL retain `"approximate"` for `lava_sim` against `Delay`.

---

### Requirement 4: Capabilities Endpoint Reports Complete Node Lists

**User Story:** As a Studio user, I want the capabilities endpoint to list every NIR primitive in either `supported_nir_nodes`, `approximate_semantics`, or `unsupported_nir_nodes`, so that I can see the full picture before clicking Run.

#### Acceptance Criteria

1. THE Capabilities_Endpoint SHALL return a `supported_nir_nodes` list that contains all node type names for which the Support_Table records `"exact"` for that backend.
2. THE Capabilities_Endpoint SHALL return an `unsupported_nir_nodes` list that contains all node type names for which the Support_Table records `"unsupported"` for that backend.
3. THE Capabilities_Endpoint SHALL return an `approximate_semantics` list that contains all node type names for which the Support_Table records `"approximate"` for that backend.
4. WHEN the union of `supported_nir_nodes`, `approximate_semantics`, and `unsupported_nir_nodes` from the Capabilities_Endpoint is computed for a given backend, THE result SHALL equal the Complete_Primitive_Set for that backend.
5. THE Capabilities_Endpoint SHALL derive all three lists exclusively from the Support_Table via `get_supported_node_types`, with no additional filtering or hardcoding inside the router.

---

### Requirement 5: Support Classification Correctness Across All Primitives

**User Story:** As a CNL developer, I want the classifier to produce accurate `SupportClassification` results for any combination of NIR primitives, so that preflight validation is reliable.

#### Acceptance Criteria

1. WHEN a NIR graph contains only node types with verdict `"exact"` for a given backend, THE Classifier SHALL return a `SupportClassification` with `level == "exact"` and empty `unsupported_nodes` and `approximate_nodes`.
2. WHEN a NIR graph contains at least one node type with verdict `"approximate"` and no `"unsupported"` nodes for a given backend, THE Classifier SHALL return a `SupportClassification` with `level == "approximate"`.
3. WHEN a NIR graph contains at least one node type with verdict `"unsupported"` for a given backend, THE Classifier SHALL return a `SupportClassification` with `level == "unsupported"` and a non-empty `diagnostics` list.
4. THE Classifier SHALL include every `"unsupported"` node type name encountered in the graph in `SupportClassification.unsupported_nodes`.
5. THE Classifier SHALL include every `"approximate"` node type name encountered in the graph in `SupportClassification.approximate_nodes`.
6. FOR ALL node type names in `SupportClassification.unsupported_nodes`, THE Classifier SHALL include at least one entry in `SupportClassification.diagnostics` that names that node type.

---

### Requirement 6: Test Coverage for All NIR Primitives

**User Story:** As a developer, I want automated tests to verify the support verdict for every NIR primitive and the adapter behaviour for every newly implemented node type, so that regressions are caught immediately.

#### Acceptance Criteria

1. THE test suite (`test_nir_support.py`) SHALL contain at least one test that asserts the exact support verdict (`"exact"`, `"approximate"`, or `"unsupported"`) for every member of the Complete_Primitive_Set for both `lava_sim` and `snntorch_sim`.
2. THE test suite SHALL contain at least one test that verifies the Support_Table has an explicit entry for every member of the Complete_Primitive_Set (i.e., no primitive falls through via `.get(type_name, "unsupported")`).
3. THE test suite SHALL contain tests for `SnnTorch_Adapter` that verify `nir.Affine`, `nir.Conv2d`, `nir.Flatten`, `nir.IF`, and `nir.AvgPool2d` nodes are executed without a skip warning.
4. THE test suite SHALL contain tests that verify a NIR graph using only snnTorch-supported node types (including the new types) is classified as `"exact"` or `"approximate"` rather than `"unsupported"`.
5. WHEN a test constructs a NIR graph containing an unsupported node type for `lava_sim` (e.g. `nir.Conv2d`), THE test SHALL assert that `classify_nir_graph` returns `level == "unsupported"`.

---

### Requirement 7: Documentation Updated to Reflect Corrected Support Matrix

**User Story:** As a developer reading the docs, I want `docs/support_matrix.md` to accurately reflect which NIR primitives each simulator backend supports, so that the documentation matches the code.

#### Acceptance Criteria

1. THE Support_Matrix_Doc SHALL include a dedicated section listing, for each of `lava_sim` and `snntorch_sim`, every member of the Complete_Primitive_Set with its verdict (`exact`, `approximate`, or `unsupported`).
2. THE Support_Matrix_Doc SHALL note the distinction between `lava-nc` (used by `lava_sim`) and `lava-dl` (used by the NIR community reference implementation), and explain why certain primitives are `unsupported` in `lava_sim` even though they appear in the official NIR support matrix.
3. THE Support_Matrix_Doc SHALL be updated in the same change as `nir_support.py` whenever a verdict changes, in accordance with the constraint in `neurocnl/AGENTS.md`.
