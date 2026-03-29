# Neurochip: update CI, failure-fix, and auto-merge for CDD-PBT migration

**Module:** Neurochip
**Spec Source:** Neurochip/.github/workflows/ci.yml, Neurochip/.github/workflows/ci-failure-fix.yml, Neurochip/.github/workflows/auto-merge-jules-prs.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Make the module runnable by Jules end to end: issue pickup, contract/property CI, fix attempts on failure, and automatic merge when checks pass.

## Conversion
- Extend CI with the CDD-PBT validation stage.
- Replace ci-failure-fix.yml and auto-merge-jules-prs.yml with the shared templates.
- Keep feature-builder and bug-fixer wired to labels so generated issues can be consumed immediately.

## Contract Targets
- Neurochip/.github/workflows/ci.yml
- Neurochip/.github/workflows/ci-failure-fix.yml
- Neurochip/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- CI runs baseline and property tests on pull requests.
- Jules receives enough failure context to patch CI issues without manual log scraping.
- Auto-merge activates for jules/* pull requests after checks turn green.

## Workflow Updates
- Copy the shared auto-merge and ci-failure-fix templates into Neurochip/.github/workflows/.
- Invoke the shared CDD-PBT workflow from Neurochip CI.

## Dependencies
- blocked-by local issue id: NC-CDD-002
