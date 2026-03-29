# [POC-05] Apply Uniform mypy Strict Mode and Ensure Governance Files

**Module**: root-infrastructure (cross-cutting umbrella)
**Phase**: POC
**Priority**: P2
**Effort**: Medium (2 days)
**Labels**: `root`, `phase:poc`, `priority:medium`, `code-quality`, `governance`
**Source**: 29-Mar-2026 Status Audit

## Problem

Two gaps remain for uniform code quality:

1. **mypy strict**: Present in `pyproject.toml` for neurocnl, Neuro-Dream-Hand, Neurosense, Neurohub, Neurosim. Missing entirely from Neurochip and Neurobench.
2. **AGENTS.md + GUARDRAILS.md**: Missing from all modules except neurocnl and Neuro-Dream-Hand (per CDD pipeline requirements). Five per-module issues track the individual file creation.

## Acceptance Criteria

### mypy Strict
- [ ] `[tool.mypy]` section with `strict = true` added to Neurochip `pyproject.toml`
- [ ] `[tool.mypy]` section with `strict = true` added to Neurobench `pyproject.toml`
- [ ] `mypy --strict` passes for each module individually (may require type stub additions)
- [ ] Document any `type: ignore` suppressions with justification comments

### Governance Files (umbrella tracker)
- [ ] AGENTS.md exists in all 7 submodule roots (neurocnl, Neuro-Dream-Hand, Neurochip, Neurobench, Neurosense, Neurohub, Neurosim)
- [ ] GUARDRAILS.md exists in all 7 submodule roots
- [ ] Each file contains module-specific content, not boilerplate
- [ ] Per-module issues closed: NDH-003, Neurobench-002, Neurosense-002, Neurohub-003, Neurosim-003
