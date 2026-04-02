# [POC-03] Add Template Catalog and Generated-Project Smoke Tests

**Module**: neurocli
**Phase**: POC
**Priority**: P1
**Effort**: Medium (2 days)
**Labels**: `neurocli`, `phase:poc`, `priority:high`, `testing`, `templates`
**Source**: 02-Apr-2026 folder review

## Problem

Even after the CLI package and `neuro new` command exist, the module will remain fragile unless template outputs are versioned, intentional, and tested. The core value of the CLI depends on generated projects being usable immediately rather than producing incomplete boilerplate.

## Acceptance Criteria

- [ ] Add a template catalog for at least 3 supported starter combinations
- [ ] Version the templates inside the repository rather than generating ad hoc files inline
- [ ] Add smoke tests that generate projects in a temporary directory
- [ ] Verify generated files are non-empty and structurally valid
- [ ] Verify the generated project contains its expected dependency/config files
- [ ] Verify CLI output tells the user what to run next after scaffolding
- [ ] Document how to add a new template family in the future
