# Add Root-Level Pre-Commit Hooks

**Priority:** P2-Medium
**Effort:** 0.5 day
**Labels:** code-quality, tooling
**Scope:** Cross-cutting (root level)

## Problem

neurocnl and Neurohub have per-module `.pre-commit-config.yaml` files, but there is no root-level enforcement. With 350+ Ruff issues in the codebase, pre-commit hooks aren't being run reliably. This means quality regressions slip through.

## Acceptance Criteria

- [ ] Root `.pre-commit-config.yaml` exists with ruff, mypy, and flutter analyze hooks
- [ ] Hooks scoped to relevant paths (Python hooks on `**/backend/**`, Dart hooks on `**/frontend/**`)
- [ ] `pre-commit run --all-files` passes (or only shows pre-existing issues)
- [ ] New commits are automatically checked

## Notes

Maps to POC-100-TASKS.md T4-5.
