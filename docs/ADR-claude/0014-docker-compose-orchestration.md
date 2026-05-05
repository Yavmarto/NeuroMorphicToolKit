# ADR 0014: Docker Compose Orchestration

## Status
Accepted

## Context
Running the full NMTK suite requires coordinating 6+ backend services, a PostgreSQL database (for Neurohub), a monitoring stack (Prometheus, Loki, Grafana), and proper network isolation. Manual startup of all services is impractical.

## Decision
Use Docker Compose with three isolated networks (`frontend-net`, `backend-net`, `monitoring-net`) and service profiles (`full`, `physics`, `monitoring`) for selective stack composition. Services declare health checks via HTTP `/health` endpoints with 10-second intervals. Neurohub depends on all other services being healthy before starting. Named volumes (`neurohub-data`, `neurobench-data`, `neurochip-data`, `neurosense-recordings`) persist data across container restarts. A `docker-compose.dev.yml` override enables hot-reload with bind mounts, and `docker-compose.prod.yml` applies security hardening.

## Consequences
- **Positive:** Network isolation prevents frontend-to-monitoring cross-talk; service profiles allow running minimal subsets (e.g., just neurocnl + Neurosim for CNL development).
- **Negative:** Three compose files (base, dev, prod) must be kept in sync; health-check-based dependency ordering adds startup latency as services wait for upstreams.

## Amendment — Consolidation Phase 2 (2026)
The six-service Docker Compose layout described above is superseded after
Phase 5 of the consolidation plan. The new layout has one `suite_api`
service plus optional worker profiles (`hardware`, `jobs`, `physics`).
See ADR 0018 and the implementation plan at
`docs/implementation-plan-consolidation.md`.
