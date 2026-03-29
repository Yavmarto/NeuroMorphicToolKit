# [POC-01] Validate Root docker-compose.yml

**Module**: root-infrastructure
**Phase**: POC
**Priority**: P0
**Effort**: Small (~1 day)
**Labels**: `root-infrastructure`, `phase:poc`, `priority:critical`

## Acceptance Criteria

- [ ] All 7 services start successfully with `docker compose up`
- [ ] All healthchecks pass (each module's `/health` endpoint responds 200)
- [ ] Network `nmtk-network` allows inter-service communication
- [ ] Ports 8000–8006 are correctly assigned and non-conflicting
- [ ] `.env` file port assignments match docker-compose service definitions
