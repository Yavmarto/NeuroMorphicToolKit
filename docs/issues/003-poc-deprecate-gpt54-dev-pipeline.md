# [POC-03] Deprecate gpt5.4-dev-pipeline in Favor of unified-dev-pipeline

**Module**: root-infrastructure
**Phase**: POC
**Priority**: P1
**Effort**: Small (~0.5 day)
**Labels**: `root`, `phase:poc`, `priority:high`, `cleanup`
**Source**: 29-Mar-2026 Status Audit (Task Fragmentation Findings)

## Problem

`docs/gpt5.4-dev-pipeline/` (7 modules, 21 generated-issues files) duplicates the work captured in `docs/unified-dev-pipeline/` (7 modules, 21 generated-issues files, plus README and `.issue-state.json` files). This duplication creates confusion about which pipeline output is canonical and increases the risk of stale task tracking.

## Acceptance Criteria

- [ ] Add `DEPRECATED.md` notice to `docs/gpt5.4-dev-pipeline/` explaining it is superseded by `docs/unified-dev-pipeline/`
- [ ] Verify all unique content from gpt5.4-dev-pipeline exists in unified-dev-pipeline
- [ ] Remove any CI workflow references to `gpt5.4-dev-pipeline` path
- [ ] Move `docs/gpt5.4-dev-pipeline/` to `docs/archive/gpt5.4-dev-pipeline/`
- [ ] Update any cross-references in other documentation
