# ADR 0002: Structured Logging and Request Tracing

## Status
Accepted

## Context
With 6+ backend services communicating via HTTP, debugging cross-service issues requires correlated log entries. The codebase currently uses three different logging approaches: custom JSON formatter in Neurohub, structlog with context variables in neurocnl, and basic RequestIDLoggingMiddleware in Neurosim and others.

## Decision
Each service implements request ID injection via middleware that generates a UUID per request and attaches it to all log entries for that request's lifecycle. Neurohub uses a custom `JSONFormatter` for structured output, neurocnl uses `structlog` with bound context variables, and other services use a simpler `RequestIDLoggingMiddleware` with Python's built-in logging. Cross-service request ID propagation is not yet implemented.

## Consequences
- **Positive:** Per-request tracing within each service enables efficient debugging; structured JSON output in Neurohub is ready for log aggregation via Loki.
- **Negative:** Three different logging implementations create inconsistent log formats across services; lack of cross-service request ID propagation means distributed traces cannot be correlated.
