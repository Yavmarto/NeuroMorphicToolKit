# ADR 0003: Intermediate Representation

## Status
Accepted

## Context
The gap between parsed CNL sentences (text-level) and executable code (Nengo/Lava/etc.) requires a normalized, backend-agnostic intermediate form that preserves semantic intent while abstracting away syntactic variation.

## Decision
Define a `NetworkIR` dataclass containing `PopulationIR`, `ConnectionIR`, `TimingDeclarationIR`, and `BackendHintIR` nodes. The `lower_to_ir()` function converts parsed sentences to IR, normalizing identifiers via `normalize_identifier()` and tracking source provenance via `SourceProvenance` for error tracing back to original CNL lines.

## Consequences
- **Positive:** Backend-agnostic IR enables a single parse to target multiple hardware backends; source provenance enables precise error messages referencing original CNL text.
- **Negative:** Custom IR adds a translation layer that must be kept in sync with both the parser and code generators; IR design choices constrain what future backends can express.
