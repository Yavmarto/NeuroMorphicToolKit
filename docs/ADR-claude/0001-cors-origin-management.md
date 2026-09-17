# ADR 0001: CORS Origin Management

## Status
Accepted

## Context
The NMTK monorepo runs 6+ FastAPI backend services, each serving a Flutter web frontend from a different localhost port. Cross-origin requests between the desktop launcher (native), module frontends (web), and backend APIs require CORS configuration. Each service currently configures CORS independently via environment-variable-driven `ALLOWED_ORIGINS`.

## Decision
Each FastAPI service configures its own CORS middleware using `CORSMiddleware` with origins loaded from the `ALLOWED_ORIGINS` environment variable. In development, `["*"]` is permitted for convenience. In production, origins are restricted to the specific localhost ports and any deployed domain. There is no centralized API gateway; each service is responsible for its own CORS headers.

## Consequences
- **Positive:** Per-service CORS configuration is simple and self-contained; no additional infrastructure (API gateway, reverse proxy) is required for local development.
- **Negative:** CORS policy is duplicated across 6+ services with no guarantee of consistency; adding a new frontend origin requires updating environment variables on all services independently.
