# Add Pre-commit / Analysis Enforcement

**Priority:** Medium  
**Labels:** `chore`, `quality`  
**Source:** v2 Style Guide Audit (2026-03-19)

## Description

Add enforcement for Dart analysis rules. Ensure `flutter analyze` passes with zero warnings/errors as part of development workflow.

## Acceptance Criteria

- [ ] Document required `flutter analyze` step in CONTRIBUTING guide or README
- [ ] Ensure `analysis_options.yaml` uses `flutter_lints` recommended ruleset
- [ ] Add a CI workflow that runs `flutter analyze` on PRs
- [ ] All existing code passes `flutter analyze` with zero warnings
