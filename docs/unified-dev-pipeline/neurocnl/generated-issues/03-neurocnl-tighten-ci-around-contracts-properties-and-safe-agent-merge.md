# neurocnl: tighten CI around contracts, properties, and safe agent merge

**Module:** neurocnl
**Spec Source:** neurocnl/pyproject.toml, neurocnl/.github/workflows/ci.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Wire contract/property validation into CI, replace old automation templates with protected-file-aware auto-merge and structured-log failure-fix.

## Conversion Steps
- [ ] Add property-test stage to CI
- [ ] Raise mypy strictness for contract modules
- [ ] Replace ci-failure-fix.yml and auto-merge-jules-prs.yml with shared templates

## Contract Targets
- `neurocnl/.github/workflows/ci.yml`
- `neurocnl/.github/workflows/ci-failure-fix.yml`
- `neurocnl/.github/workflows/auto-merge-jules-prs.yml`

## Property Targets

## Acceptance Checks
- [ ] Contract and property suites run on pull requests
- [ ] Failure-fix prompts include failing-log context
- [ ] Agent PRs can auto-merge after synchronize and ready-for-review transitions
- [ ] PRs touching contracts/ or properties/ require human review

## Workflow Updates
- [ ] Copy shared auto-merge and ci-failure-fix templates
- [ ] Invoke shared CDD-PBT workflow from neurocnl CI

## Dependencies
- blocked-by: `CNL-CDD-002`
