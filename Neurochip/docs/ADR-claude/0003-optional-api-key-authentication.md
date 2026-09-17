# ADR 0003: Optional API Key Authentication

## Status
Accepted

## Context
Neurochip is used in both local development (no auth needed) and shared lab environments where unauthorized access could damage expensive hardware. A flexible authentication mechanism is needed that does not impede developer workflow while still protecting shared resources.

## Decision
Implement toggle-based API key authentication controlled by the `NEUROCHIP_AUTH_ENABLED` environment variable. When enabled, all endpoints require an `X-API-Key` header validated via FastAPI dependency injection. When disabled, requests pass through without authentication.

## Consequences
- **Positive:** Zero friction in development; simple to enable in shared environments without changing application code.
- **Negative:** API key auth lacks user identity and audit trails; no token rotation or expiry mechanism compared to JWT.
