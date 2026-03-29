# [POC-01] Validate Root docker-compose.yml Full-Stack Orchestration

**Module**: root-infrastructure
**Phase**: POC
**Priority**: P0
**Effort**: Medium (2 days)
**Labels**: `root`, `phase:poc`, `priority:critical`, `infrastructure`
**Source**: 29-Mar-2026 Status Audit

## Problem

The root `docker-compose.yml` defines 7 services (neurocnl:8000, neurosim:8001, neurochip:8002, neurobench:8003, neurosense:8004, neurohub:8005, neurocnl-physics:8006) with healthchecks, `unless-stopped` restart policy, and `nmtk-network`. Additionally, `docker-compose.dev.yml` and `docker-compose.prod.yml` variants exist. None have been validated end-to-end — this is the single most critical POC blocker.

## Acceptance Criteria

- [ ] `docker-compose up` starts all 7 defined services
- [ ] All health checks pass within 60 seconds of startup
- [ ] Each service responds on its assigned port (8000-8006)
- [ ] Inter-service communication verified (e.g., Neurosim → neurocnl pipeline call)
- [ ] `docker-compose.dev.yml` overlay applies correctly (volume mounts for hot-reload)
- [ ] `docker-compose.prod.yml` overlay applies correctly (optimized builds, no debug)
- [ ] `docker-compose down` performs clean shutdown — no orphan containers, networks, or volumes
- [ ] Document any service startup ordering dependencies
- [ ] Memory usage under 8GB total for all 7 services (reasonable for demo machines)
