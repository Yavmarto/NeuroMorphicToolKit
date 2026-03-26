# Deprecate Old Automation Workflows

**Priority:** P2-Medium
**Effort:** 30 min
**Labels:** ci, cleanup
**Scope:** .github/workflows/

## Problem

Old automation workflows coexist with newer unified pipeline equivalents, causing potential conflicts:

| Old (deprecate) | New (keep) |
|---|---|
| `auto-merge-jules-prs.yml` | `auto-merge-agents.yml` |
| `ci-failure-fix.yml` | `ci-failure-fix-agent.yml` |

Both old and new are active, which could cause duplicate PR merges or conflicting fix attempts.

## Acceptance Criteria

- [ ] `auto-merge-jules-prs.yml` removed or disabled (renamed to `.disabled`)
- [ ] `ci-failure-fix.yml` removed or disabled
- [ ] Verify `auto-merge-agents.yml` and `ci-failure-fix-agent.yml` cover all the old functionality
- [ ] No workflow conflicts on next PR

## Notes

Identified in 24march-opus.md analysis.
