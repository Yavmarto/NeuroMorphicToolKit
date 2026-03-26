# Validate Root docker-compose.yml Startup

**Priority:** High — Blocks full-stack demo
**Effort:** 2-4 hours
**Source:** POC-100-TASKS.md T1-5

## Problem

The root `docker-compose.yml` has not been tested end-to-end. Build contexts, healthchecks, profiles, and inter-service dependencies are unvalidated.

## Acceptance Criteria

- [ ] `docker-compose up --build` succeeds for default profile (neurocnl, neurosim, neurochip)
- [ ] `docker-compose --profile full up --build` starts all 7 services
- [ ] `docker-compose --profile physics up --build` starts neurocnl-physics variant
- [ ] All services pass healthchecks
- [ ] `scripts/validate_docker_compose.sh` passes (if exists)

## Archived Predecessors

- `issues-archive/22mar1_validate_root_docker_compose_yml_startup.md`
- `issues-archive/001-validate-root-docker-compose.md`
