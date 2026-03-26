# Validate Root docker-compose.yml (All 7 Services)

**Priority:** P1-High
**Effort:** 2-4 hours
**Labels:** docker, infrastructure, integration
**Scope:** Cross-cutting (root level)

## Problem

The root `docker-compose.yml` has never been tested end-to-end. Build contexts, healthchecks, profiles, and inter-service dependencies are unvalidated. Individual Dockerfiles were fixed on March 24, but the orchestrated startup has not been verified.

## Acceptance Criteria

- [ ] `docker-compose up --build` starts all 7 services without errors
- [ ] Default profile (neurocnl, neurosim, neurochip) starts and all healthchecks pass
- [ ] `--profile full` starts all 7 services and all healthchecks pass
- [ ] `--profile physics` starts neurocnl-physics variant
- [ ] `scripts/validate_docker_compose.sh` passes (if exists)
- [ ] `scripts/demo_smoke_test.sh` passes (if exists)
- [ ] Each service responds on its expected port (8000-8005)

## Notes

Maps to POC-100-TASKS.md T1-5. Individual Docker fixes (T1-1 through T1-4) were completed on March 24.
