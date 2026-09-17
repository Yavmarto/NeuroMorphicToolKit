# ADR 0006: Docker Multi-Stage Build

## Status
Accepted

## Context
Neurochip containers must be secure for deployment in shared lab environments with access to physical hardware, yet small enough for rapid iteration during development. A single-stage build would include build tools and intermediate artifacts in the final image, increasing both size and attack surface.

## Decision
Use a two-stage Dockerfile: the builder stage installs Poetry and all dependencies, the final stage copies only the virtualenv and application code. Runtime executes as a non-root `appuser` with resource limits (0.50 CPU, 512MB memory). Uvicorn serves the application in production mode.

## Consequences
- **Positive:** Non-root execution prevents container escape privilege escalation; multi-stage build reduces final image size by excluding build tools.
- **Negative:** Poetry lock file changes require full builder cache invalidation; resource limits may constrain large model compilation tasks.
