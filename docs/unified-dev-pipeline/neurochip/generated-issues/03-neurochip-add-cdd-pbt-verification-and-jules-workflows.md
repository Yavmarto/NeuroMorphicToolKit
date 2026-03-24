# Neurochip: add CDD-PBT verification and Jules workflows

**Module:** Neurochip
**Spec Source:** 
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Add property tests to the Poetry-based CI, add ci-failure-fix and auto-merge workflows.

## Conversion Steps
- [ ] Add property test step to CI using poetry run pytest
- [ ] Add ci-failure-fix.yml with structured log handoff
- [ ] Add auto-merge-jules-prs.yml with protected-file awareness

## Contract Targets
- `Neurochip/.github/workflows/ci.yml`

## Property Targets

## Acceptance Checks
- [ ] CI runs all property tests via poetry
- [ ] Jules receives failure logs with contract context
- [ ] Auto-merge checks for protected files before merging

## Workflow Updates
- [ ] Add property test step to Neurochip ci.yml
- [ ] Copy shared auto-merge and ci-failure-fix templates

## Dependencies
- blocked-by: `NC-CDD-002`
