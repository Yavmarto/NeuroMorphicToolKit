# [POC-02] Migrate print() Calls to Structured Logging Across All Modules

**Module**: root-infrastructure (cross-cutting)
**Phase**: POC
**Priority**: P1
**Effort**: Large (3-4 days)
**Labels**: `root`, `phase:poc`, `priority:high`, `code-quality`
**Source**: 29-Mar-2026 Status Audit

## Problem

~7,202 `print()` calls exist in non-test Python source files across the monorepo. The `CODING_STYLE_GUIDE.md` requires `logging.getLogger(__name__)` but this has not been enforced. Ruff rule T201 flagged 236 violations in production-critical code. Breakdown by module: neurocnl (335), Neuro-Dream-Hand (218), Neurosense (59), Neurochip (11), Neurosim (6), Neurohub (3), Neurobench (1).

This is the umbrella issue; `Neuro-Dream-Hand/issues/001` handles the NDH-specific portion.

## Acceptance Criteria

- [ ] Each module uses `logging.getLogger(__name__)` pattern consistently
- [ ] Logging configured in each module's entry point (`main.py`, `__init__.py`, CLI entry)
- [ ] Log format includes timestamp, module name, and severity level
- [ ] `grep -rn "print(" --include="*.py" | grep -v test | grep -v venv | grep -v build` returns 0 matches in backend services
- [ ] Research library (Neuro-Dream-Hand) may retain `print()` in interactive/notebook contexts with explicit `# noqa: T201` annotations
- [ ] Ruff T201 rule passes across all modules (0 violations or explicitly suppressed)
- [ ] All tests pass after migration
