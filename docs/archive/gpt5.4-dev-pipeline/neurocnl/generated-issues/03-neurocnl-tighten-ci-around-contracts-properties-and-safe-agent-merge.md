# neurocnl: tighten CI around contracts, properties, and safe agent merge

**Module:** neurocnl
**Spec Source:** neurocnl/pyproject.toml, neurocnl/.github/workflows/ci.yml, neurocnl/.github/workflows/ci-failure-fix.yml, neurocnl/.github/workflows/auto-merge-jules-prs.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Make the compiler repo enforce the new contract/property layer with stronger typing and better automation around agent pull requests.

## Conversion
- Raise mypy strictness for the contract modules and property test helpers.
- Add a property-test stage to CI.
- Replace ci-failure-fix.yml and auto-merge-jules-prs.yml with the shared templates.

## Contract Targets
- neurocnl/pyproject.toml
- neurocnl/.github/workflows/ci.yml
- neurocnl/.github/workflows/ci-failure-fix.yml
- neurocnl/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- Contract and property suites run on pull requests.
- Failure-fix prompts include failing-log context.
- Agent pull requests can auto-merge after synchronize and ready-for-review transitions.

## Workflow Updates
- Copy the shared auto-merge and ci-failure-fix templates into neurocnl/.github/workflows/.
- Invoke the shared CDD-PBT workflow from neurocnl CI.

## Dependencies
- blocked-by local issue id: CNL-CDD-002
