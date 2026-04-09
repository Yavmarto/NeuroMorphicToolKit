# Neurobench: add CDD-PBT verification and Jules workflows

**Module:** Neurobench
**Spec Source:**
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Add property tests to the Poetry-based CI, add ci-failure-fix and auto-merge workflows, wire Flutter frontend CI into the contract gate.

## Conversion Steps
- [ ] Add property test step to CI using poetry run pytest
- [ ] Wire Flutter frontend CI to fail if backend contracts break
- [ ] Add ci-failure-fix.yml and auto-merge-jules-prs.yml

## Contract Targets
- `Neurobench/.github/workflows/ci.yml`

## Property Targets

## Acceptance Checks
- [ ] CI runs all property tests via poetry
- [ ] Flutter builds are gated on backend contract verification
- [ ] Jules receives failure logs with contract context

## Workflow Updates
- [ ] Add property test step to Neurobench ci.yml
- [ ] Gate Flutter frontend on backend contracts-passed job
- [ ] Copy shared auto-merge and ci-failure-fix templates

## Dependencies
- blocked-by: `NB-CDD-002`
