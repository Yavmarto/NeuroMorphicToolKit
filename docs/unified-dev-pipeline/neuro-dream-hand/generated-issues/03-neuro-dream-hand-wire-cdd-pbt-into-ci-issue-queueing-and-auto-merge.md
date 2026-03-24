# Neuro-Dream-Hand: wire CDD-PBT into CI, issue queueing, and auto-merge

**Module:** Neuro-Dream-Hand
**Spec Source:** Neuro-Dream-Hand/.github/workflows/ci.yml, Neuro-Dream-Hand/.github/workflows/integration.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Keep the advanced queueing workflow but add contract/property enforcement and modernize the Jules failure-fix and auto-merge stages.

## Conversion Steps
- [ ] Add a property-test stage to CI and integration workflows
- [ ] Preserve queue-issue-to-jules.yml but ensure generated migration issues are compatible
- [ ] Replace ci-failure-fix.yml and auto-merge-jules-prs.yml with shared templates

## Contract Targets
- `Neuro-Dream-Hand/.github/workflows/ci.yml`
- `Neuro-Dream-Hand/.github/workflows/ci-failure-fix.yml`
- `Neuro-Dream-Hand/.github/workflows/auto-merge-jules-prs.yml`

## Property Targets

## Acceptance Checks
- [ ] Baseline, integration, and property tests all run before merge
- [ ] Jules repair attempts include the workflow log bundle URL
- [ ] Auto-merge triggers after PR updates, not only on creation
- [ ] PRs touching contracts/ or properties/ require human review

## Workflow Updates
- [ ] Copy shared auto-merge and ci-failure-fix templates
- [ ] Add CDD-PBT validation as a required status check

## Dependencies
- blocked-by: `NDH-CDD-002`
