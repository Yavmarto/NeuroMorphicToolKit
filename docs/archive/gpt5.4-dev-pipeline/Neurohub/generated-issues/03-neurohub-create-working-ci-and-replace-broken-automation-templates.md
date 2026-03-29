# Neurohub: create working CI and replace broken automation templates

**Module:** Neurohub
**Spec Source:** Neurohub/.github/workflows/ci-failure-fix.yml, Neurohub/.github/workflows/auto-merge-jules-prs.yml, Neurohub/.github/workflows/feature-builder.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Create the missing CI workflow, wire in contract/property validation, and make the existing issue-driven automation usable.

## Conversion
- Add ci.yml that installs the package, runs lint, mypy, tests, and property tests.
- Replace ci-failure-fix.yml so it monitors the new CI workflow and passes structured logs to Jules.
- Replace auto-merge-jules-prs.yml so it responds after Jules updates a pull request.

## Contract Targets
- Neurohub/.github/workflows/ci.yml
- Neurohub/.github/workflows/ci-failure-fix.yml
- Neurohub/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- Neurohub pull requests have an actual CI workflow protecting merge.
- CI failures can trigger an automated Jules repair attempt.
- Generated migration issues can be labeled feature and handled by the existing issue pickup workflow.

## Workflow Updates
- Create Neurohub/.github/workflows/ci.yml from the shared module CI template.
- Copy the shared auto-merge and ci-failure-fix templates into Neurohub/.github/workflows/.

## Dependencies
- blocked-by local issue id: NH-CDD-002
