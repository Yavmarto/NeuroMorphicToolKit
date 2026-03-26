# Fix Unified Pipeline README (Misleading Directory Tree)

**Priority:** P1-High
**Effort:** 1 hour
**Labels:** documentation, cdd-pbt
**Scope:** docs/unified-dev-pipeline/

## Problem

The unified pipeline README.md describes a directory tree with `contracts/` and `properties/` Python files as if they already exist. In reality, these are *targets to be created* — the actual structure uses `generated-issues/` with markdown work orders. The Module Migration State table also shows percentages that imply existing code.

This is misleading for anyone reviewing the pipeline and creates confusion about what's done vs. planned.

## Acceptance Criteria

- [ ] README directory tree shows `generated-issues/` instead of `contracts/` and `properties/`
- [ ] Module Migration State table clarifies that percentages refer to pipeline setup, not contract code delivery
- [ ] Clear statement that contract/property code is the OUTPUT of the pipeline, not a pre-existing input
- [ ] AGENTS.md/GUARDRAILS.md status accurately reflects that only neurocnl and neuro-dream-hand have them

## Notes

Identified in 24march-opus.md analysis.
