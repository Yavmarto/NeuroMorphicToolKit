# Neurosim: add missing Jules workflows and full contract CI

**Module:** Neurosim
**Spec Source:** Neurosim/.github/workflows/ci.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Bring Neurosim up to the same operational baseline as the other modules so migration issues can be picked up, fixed, and merged automatically.

## Conversion
- Extend ci.yml with lint, mypy, unit tests, and property tests.
- Add feature-builder.yml, bug-fixer.yml, ci-failure-fix.yml, unblocked-issues.yml, and auto-merge-jules-prs.yml.
- Use the shared templates so failure repair and auto-merge behave consistently with the other modules.

## Contract Targets
- Neurosim/.github/workflows/ci.yml
- Neurosim/.github/workflows/feature-builder.yml
- Neurosim/.github/workflows/bug-fixer.yml
- Neurosim/.github/workflows/ci-failure-fix.yml
- Neurosim/.github/workflows/unblocked-issues.yml
- Neurosim/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- Neurosim has the same core issue-driven automation surface as the mature modules.
- CI failures can trigger a Jules repair attempt.
- Agent PRs can auto-merge after all checks pass.

## Workflow Updates
- Create the missing workflows using the patterns already used by Neurobench and the shared templates in this folder.
- Invoke the shared CDD-PBT workflow from Neurosim CI.

## Dependencies
- blocked-by local issue id: NS-CDD-002
