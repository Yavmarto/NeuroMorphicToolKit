# ADR 0002: Contract-Driven Development

## Status
Accepted

## Context
Hardware deployment pipelines are error-prone with many handoff points between services (quantization, estimation, export, flash). Data contracts must be machine-verifiable to prevent silent failures. Without strict validation, mismatched fields or invalid values can propagate through the pipeline undetected until they reach physical hardware.

## Decision
Define 8 contract modules as Pydantic BaseModel classes in `neurochip/contracts/` (deployment, hardware, fault, estimation, quantization, Teensy, Akida, PYNQ). All inter-service data flows through validated contracts with field-level constraints (SemVer validation, SHA-256 checksums, enum-restricted target devices).

## Consequences
- **Positive:** Type errors and invalid data are caught at service boundaries before reaching hardware; contracts serve as living documentation.
- **Negative:** Contract updates require coordination across all consuming services; Pydantic overhead on hot paths.
