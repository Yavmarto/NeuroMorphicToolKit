# CNL Matrix Semantics and Phase-2 Expansion Plan

> **Date**: 2026-05-13  
> **Scope**: Keep `NetworkIR` as the semantic boundary, make low-level matrix semantics first-class in CNL, and preserve a clean future insertion point for high-level solver-backed expansion.

---

## Decision

Do **not** remove `NetworkIR`.

Instead:

1. Treat `CNL -> NetworkIR -> NIR` as the permanent compiler spine.
2. Expand CNL so users can express nearly complete low-level matrix and shape intent in natural language.
3. Keep a future pre-processor slot where a high-level solver can convert abstract math/function declarations into explicit `NetworkIR` weights before the existing NIR materializer runs.

This preserves clean separation:

- **language understanding** lives in the parser and lowering stages
- **semantic normalization** lives in IR
- **file emission** lives in the NIR materializer/exporter
- **future math expansion** can be added later without rewriting the exporter plumbing

---

## Why IR Stays

`NetworkIR` is still the right architectural boundary because it:

- normalizes natural-language variants into stable semantic objects
- keeps parser logic separate from NIR operator lowering
- gives the compiler one place to store exact matrices, masks, timing, and metadata-backed semantics
- makes fail-closed NIR support classification possible before file emission
- gives a future Phase-2 expander one target shape to emit, rather than forcing it to know NIR writer details

Direct `CNL -> NIR` is only clean for a narrow subset. Once CNL grows to cover matrix declarations, inferred shapes, structured connectivity, and future solver-backed constructs, skipping IR would only push semantic complexity into the parser and exporter.

---

## Phase 1: Matrix-Native CNL on IR

### Goal

Make low-level authoring first-class: a user should be able to describe exact weights and matrix structure in natural language, with shape inference when unambiguous, while still compiling through `NetworkIR`.

### Required language additions

Add CNL sentence families for:

- explicit dense weight matrices
- matrix shape declarations
- inferred matrix shape when source and target population sizes already determine it
- canonical structured matrices where natural language is clearer than raw literals:
  - identity
  - diagonal
  - binary mask
  - scalar broadcast
  - row/column vector expansion only when semantics are explicit

### Examples to support

- `The connection from input to hidden MUST use weight matrix [[0.1, -0.2], [0.3, 0.4]].`
- `The connection from input to hidden MUST use a 2 by 2 weight matrix [[0.1, -0.2], [0.3, 0.4]].`
- `The connection from input to hidden MUST use the identity matrix.`
- `The connection from input to hidden MUST use a diagonal matrix with values [0.5, 0.25, 0.1].`
- `The connection from input to hidden MUST use explicit binary mask [[1, 0], [0, 1]].`

Shape should be optional when the source and target population shapes make the matrix dimensions deterministic.

### Compiler behavior

- Parse matrix declarations into new structured parser output fields.
- Lower them into exact `ConnectionIR.weight` tensors.
- Keep exact dense matrices in IR, not hidden only in embedded metadata.
- Preserve embedded metadata only for semantics the human grammar still cannot express.
- Reject ambiguous matrix declarations with actionable diagnostics instead of guessing.

### Exit criteria

- Exact dense matrices can be authored in natural language and survive `CNL -> IR -> NIR`.
- Matrix dimensions are inferred when safe and required when ambiguous.
- Materializer emits exact `nir.Linear.weight` tensors with no heuristic resizing for this path.
- New regression tests prove matrix literals, inferred shape, and fail-closed ambiguity behavior.

---

## Phase 2: High-Level Expansion Slot

### Goal

Later, add a high-level authoring layer without rewriting Phase 1.

### Architecture

Insert a new semantic expansion stage:

`CNL -> parse high-level constructs -> expand to explicit NetworkIR weights -> existing NIR materializer`

This stage may use:

- Nengo
- another math/solver backend
- or an internal symbolic/matrix expander

The important rule is that the solver emits explicit `NetworkIR` populations/connections/weights and does **not** write NIR directly.

### Supported future constructs

Examples of future high-level authoring:

- function-generated weights
- convolution-style declarations
- basis-function expansions
- solver-produced encoders/decoders
- compressed or symbolic matrix descriptions

### Non-negotiable rule

Phase 2 must terminate at `NetworkIR`, not at `nir.NIRGraph`.

That keeps:

- one semantic truth model
- one lowering-verdict system
- one NIR exporter
- one round-trip document strategy

---

## Implementation Order

1. Add parser support for explicit matrix declarations and optional shape clauses.
2. Extend parser/typed output contracts for matrix payloads.
3. Lower matrix declarations into exact `ConnectionIR.weight` tensors.
4. Tighten NIR materializer tests so this path is always exact, never heuristic.
5. Add end-to-end `CNL -> IR -> NIR` regression coverage for matrix-native authoring.
6. Only after Phase 1 is stable, design the high-level expansion interface that emits `NetworkIR`.

---

## Acceptance Criteria

- Users can author explicit weight matrices in natural language CNL.
- The compiler stores those matrices directly in `NetworkIR`.
- The NIR exporter emits exact weights for those declarations.
- Shape inference is deterministic and diagnostics are explicit when it is not.
- The future high-level expansion stage can be added without changing the NIR writer contract.
- `NetworkIR` remains the sole semantic handoff between parsing/expansion and NIR lowering.
