# [POC-04] Achieve Zero Ruff Lint Violations Across All Modules

**Module**: root-infrastructure (cross-cutting)
**Phase**: POC
**Priority**: P1
**Effort**: Large (3-5 days)
**Labels**: `root`, `phase:poc`, `priority:high`, `code-quality`
**Source**: 29-Mar-2026 Status Audit

## Problem

1,336 ruff lint violations exist across the monorepo (625 auto-fixable). Breakdown: Neuro-Dream-Hand (714), Neurohub (109), neurocnl (76), Neurobench (58), Neurochip (56), scripts (3), Neurosense (1), Neurosim (1), tests (1). The top violation categories are T201 (print, 236), I001 (unsorted imports, 205), F401 (unused imports, 146), W293 (whitespace, 133), F821 (undefined name, 59).

This is the umbrella issue; `Neuro-Dream-Hand/issues/001` handles the largest single contributor (714 violations).

## Acceptance Criteria

- [ ] Run `ruff check --fix .` for auto-fixable subset (I001, F401, W293, UP035, etc.) — ~625 fixes
- [ ] Manually resolve remaining ~711 violations per module
- [ ] `ruff check .` exits with 0 violations across entire monorepo
- [ ] Update `Neuro-Dream-Hand/pyproject.toml` from deprecated top-level ruff config to `[tool.ruff.lint]`
- [ ] Add `ruff check` to CI pre-commit hooks to prevent regression
- [ ] All tests pass after fixes
