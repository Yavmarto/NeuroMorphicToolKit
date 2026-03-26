# [POC-02] Cleanup Deprecated CI Workflows

**Module**: root-infrastructure
**Phase**: POC
**Priority**: P1
**Effort**: Medium (2-3 days)
**Labels**: `root-infrastructure`, `phase:poc`, `priority:high`

## Acceptance Criteria

- [ ] Audit all 18 root-level GitHub Actions workflow files
- [ ] Identify workflows that are stale, duplicated, or superseded
- [ ] Remove or archive deprecated workflows
- [ ] Verify remaining workflows all pass on current `main` branch
- [ ] Document active workflow inventory in `docs/CI_OVERVIEW.md`
