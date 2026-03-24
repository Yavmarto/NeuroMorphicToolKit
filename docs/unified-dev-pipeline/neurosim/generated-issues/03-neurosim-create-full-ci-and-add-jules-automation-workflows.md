# Neurosim: create full CI and add Jules automation workflows

**Module:** Neurosim
**Spec Source:** Neurosim/.github/workflows/ci.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Expand the minimal ci.yml to run lint, mypy, tests, and properties. Add the missing Jules automation workflows.

## Conversion Steps
- [ ] Expand ci.yml to full validation (ruff, mypy, pytest, property tests)
- [ ] Add ci-failure-fix.yml with structured log handoff
- [ ] Add auto-merge-jules-prs.yml with protected-file awareness

## Contract Targets
- `Neurosim/.github/workflows/ci.yml`

## Property Targets

## Acceptance Checks
- [ ] CI runs baseline and property tests on pull requests
- [ ] Jules receives enough failure context to patch issues
- [ ] Auto-merge activates for jules/* PRs after checks pass

## Workflow Updates
- [ ] Expand Neurosim ci.yml to full validation
- [ ] Copy shared auto-merge and ci-failure-fix templates

## Dependencies
- blocked-by: `NS-CDD-002`
