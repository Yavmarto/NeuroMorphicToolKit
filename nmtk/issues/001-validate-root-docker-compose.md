# Validate Root docker-compose Startup

**Priority:** Tier 1 — Blocks Demo Quality
**Estimated Effort:** 2–4 hours
**Source:** v4 Audit Report (2026-03-20)

## Problem

The root `docker-compose.yml` with 7 services, healthchecks, and profiles has been added but is untested. Build contexts, healthcheck endpoints, inter-service networking, and profile groupings (core/physics/full) need validation.

## Acceptance Criteria

- [ ] `docker-compose --profile core up` builds and starts core services successfully
- [ ] `docker-compose --profile physics up` builds and starts physics-related services
- [ ] `docker-compose --profile full up` builds and starts all 7 services
- [ ] All healthchecks pass and report healthy status
- [ ] Services can communicate over the shared Docker network
- [ ] `.env` port configuration is respected by all services
- [ ] Document any fixes required during validation
