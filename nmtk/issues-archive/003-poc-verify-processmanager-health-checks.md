# [POC-03] Verify ProcessManager Health Checks

**Module**: nmtk-launcher
**Phase**: POC
**Priority**: P1
**Effort**: Small (~1 day)
**Labels**: `nmtk-launcher`, `phase:poc`, `priority:high`

## Acceptance Criteria

- [ ] ProcessManager correctly starts/stops all 7 submodule backend processes
- [ ] Health checks poll each module's `/health` endpoint
- [ ] Unhealthy modules are reported in launcher UI with actionable error
- [ ] Module restart on health check failure (with backoff)
- [ ] Test with 1, 3, and 7 modules simultaneously
