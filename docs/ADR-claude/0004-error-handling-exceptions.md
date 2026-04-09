# ADR 0004: Error Handling and Exception Design

## Status
Accepted

## Context
Each NMTK backend service defines its own exception classes and HTTP error responses. Neurochip has `akida_errors.py` and `pynq_errors.py`, Neurobench has `BenchmarkExecutionError`, `SpikeFidelityError`, and `BenchmarkTimeoutError`. There is no shared exception hierarchy or standardized error response format across services.

## Decision
Each service defines domain-specific exception classes that map to HTTP status codes via FastAPI exception handlers. Common patterns include: 404 for missing resources, 422 for validation errors (Pydantic), 429 for rate limits, and 500 for unhandled exceptions. Error responses include a `detail` field with a human-readable message. There is no shared exception base class or error response schema across services.

## Consequences
- **Positive:** Domain-specific exceptions provide clear, contextual error messages for each service's unique failure modes; Pydantic validation errors are automatically formatted by FastAPI.
- **Negative:** No shared error schema means API consumers must handle different error formats per service; unhandled exceptions return generic 500 responses with no structured diagnostics.
