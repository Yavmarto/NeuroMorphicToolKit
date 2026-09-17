# ADR 0006: Unified Pipeline Orchestration

## Status
Accepted

## Context
The CLI, REST API, and other NMTK modules all need to run the same CNL processing flow (parse, validate, generate, simulate). Duplicating this flow across entry points would cause drift and inconsistency.

## Decision
Implement a single `pipeline.py` orchestrator that sequences: parse, lower_to_ir, validate (Layer 1 + Layer 2), plan_backend_support, generate (Nengo network), simulate, generate_assertions, and produce a `PipelineResult` dataclass. Both the CLI (`run_simulation.py`) and the FastAPI backend call this same pipeline. A `to_contract()` method converts the result to Pydantic for API serialization. Errors are accumulated rather than fail-fast to provide comprehensive diagnostics.

## Consequences
- **Positive:** Single pipeline entry point guarantees consistent behavior across CLI and API; error accumulation provides comprehensive diagnostics in a single run.
- **Negative:** Pipeline orchestration is a single point of failure; accumulating all errors adds processing overhead compared to fail-fast for obviously broken specifications.
