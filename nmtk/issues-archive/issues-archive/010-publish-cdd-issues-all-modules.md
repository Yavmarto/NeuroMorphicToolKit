# Publish CDD Issues for All Modules to GitHub

**Priority:** P2-Medium
**Effort:** 30 min
**Labels:** cdd-pbt, tooling
**Scope:** Cross-cutting

## Problem

CDD pipeline generated issues exist as local markdown previews in `docs/unified-dev-pipeline/*/generated-issues/` for all 7 modules (21 issues total). However, only neurocnl's issues have been published to GitHub (issues #55-57). The other 6 modules' issues (18 total) exist only as local files.

## Acceptance Criteria

- [ ] Run `publish_github_issues.py --execute` for all modules
- [ ] All 18 remaining CDD issues appear on GitHub issue tracker with correct labels
- [ ] `.issue-state.json` updated for each module to track published issues
- [ ] No duplicate issues created (script handles idempotency)

## Notes

The script already handles topological sorting and duplicate prevention via `.issue-state.json`. Just needs to be run with `--execute` flag.
