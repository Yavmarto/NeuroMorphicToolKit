# Neurobench: wire contract CI, issue pickup, and safe auto-merge

**Module:** Neurobench
**Spec Source:** Neurobench/.github/workflows/ci.yml, Neurobench/.github/workflows/ci-failure-fix.yml, Neurobench/.github/workflows/auto-merge-jules-prs.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Update the existing workflow suite so generated migration issues can be picked up by Jules, validated by contract/property CI, and auto-merged once required checks pass.

## Conversion
- Add a contract/property stage to CI using the reusable CDD-PBT template.
- Replace the current failure-fix workflow so it passes structured log URLs into Jules.
- Replace the auto-merge workflow so it also reacts to synchronize and ready_for_review events.

## Contract Targets
- Neurobench/.github/workflows/ci.yml
- Neurobench/.github/workflows/ci-failure-fix.yml
- Neurobench/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- Jules-opened PRs from jules/* automatically receive auto-merge when checks are green.
- CI failures create enough context for an automated fix attempt.
- Generated migration issues can be labeled feature and processed by the existing issue runner.

## Workflow Updates
- Copy the shared auto-merge and ci-failure-fix templates into Neurobench/.github/workflows/.
- Call the shared CDD-PBT workflow from Neurobench CI.

## Dependencies
- blocked-by local issue id: NB-CDD-002
