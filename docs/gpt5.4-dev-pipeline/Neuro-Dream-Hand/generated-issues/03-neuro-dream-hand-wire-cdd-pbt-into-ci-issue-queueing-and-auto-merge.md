# Neuro-Dream-Hand: wire CDD-PBT into CI, issue queueing, and auto-merge

**Module:** Neuro-Dream-Hand
**Spec Source:** Neuro-Dream-Hand/.github/workflows/ci.yml, Neuro-Dream-Hand/.github/workflows/integration.yml, Neuro-Dream-Hand/.github/workflows/queue-issue-to-jules.yml, Neuro-Dream-Hand/.github/workflows/ci-failure-fix.yml, Neuro-Dream-Hand/.github/workflows/auto-merge-jules-prs.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Keep the advanced queueing workflow but add contract/property enforcement and modernize the Jules failure-fix and auto-merge stages.

## Conversion
- Add a property-test stage to CI and integration workflows.
- Preserve queue-issue-to-jules.yml but ensure generated migration issues are compatible with it.
- Replace ci-failure-fix.yml and auto-merge-jules-prs.yml with the shared templates.

## Contract Targets
- Neuro-Dream-Hand/.github/workflows/ci.yml
- Neuro-Dream-Hand/.github/workflows/integration.yml
- Neuro-Dream-Hand/.github/workflows/ci-failure-fix.yml
- Neuro-Dream-Hand/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- Baseline, integration, and property tests all run before merge.
- Jules repair attempts include the workflow log bundle URL.
- Auto-merge triggers after PR updates, not only on creation.

## Workflow Updates
- Copy the shared auto-merge and ci-failure-fix templates into Neuro-Dream-Hand/.github/workflows/.
- Add CDD-PBT validation as a required status check next to the existing integration workflow.

## Dependencies
- blocked-by local issue id: NDH-CDD-002
