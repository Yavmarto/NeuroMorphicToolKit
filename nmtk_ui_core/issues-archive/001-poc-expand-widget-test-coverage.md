# [POC-01] Expand Widget and Model Test Coverage to 60%+

**Module**: nmtk_ui_core
**Phase**: POC
**Priority**: P1
**Effort**: Small (~1 day)
**Labels**: `nmtk_ui_core`, `phase:poc`, `priority:high`, `testing`
**Source**: 29-Mar-2026 Status Audit
**Cross-ref**: `nmtk/neuro_toolkit/issues/002-poc-fix-nmtk-ui-core-placeholder-test.md`

## Problem

5 test files exist (70-144 lines each) but coverage is insufficient for a shared UI library used by 6+ frontends. All 6 reusable widgets need dedicated test files with meaningful assertions. The placeholder test identified in the nmtk tracker (`002-poc-fix-nmtk-ui-core-placeholder-test.md`) should be resolved as part of this work.

## Acceptance Criteria

- [ ] All 6 shared widgets have dedicated test files with meaningful assertions (render, tap, state)
- [ ] All models have unit tests for serialization/deserialization
- [ ] Theme unit tests cover color schemes, text styles, and spacing tokens
- [ ] `flutter test --coverage` reports >= 60% line coverage
- [ ] No placeholder or empty test files remain
- [ ] Close in tandem with nmtk issue `002-poc-fix-nmtk-ui-core-placeholder-test.md`
