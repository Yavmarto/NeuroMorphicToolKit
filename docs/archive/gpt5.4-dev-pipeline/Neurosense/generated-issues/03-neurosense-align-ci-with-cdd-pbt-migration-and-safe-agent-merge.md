# Neurosense: align CI with CDD-PBT migration and safe agent merge

**Module:** Neurosense
**Spec Source:** Neurosense/.github/workflows/ci.yml, Neurosense/.github/workflows/ci-failure-fix.yml, Neurosense/.github/workflows/auto-merge-jules-prs.yml
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Update CI so contract and property validation runs on pull requests, and make the Jules automation safe and complete.

## Conversion
- Move the CI Python runtime to 3.11 or 3.12 after confirming BrainFlow compatibility.
- Add a property-test stage using the shared CDD-PBT workflow.
- Replace ci-failure-fix.yml and auto-merge-jules-prs.yml with the shared templates.

## Contract Targets
- Neurosense/.github/workflows/ci.yml
- Neurosense/.github/workflows/ci-failure-fix.yml
- Neurosense/.github/workflows/auto-merge-jules-prs.yml

## Property Targets
- Research-Spec-driven-development/gpt5.4-dev-pipeline/workflows/cdd-pbt-module-ci.yml

## Acceptance Checks
- CI protects merge with baseline and property tests.
- Agent pull requests can be auto-merged after updates and review-ready transitions.
- Failure-fix jobs include the failing log bundle URL in the Jules prompt.

## Workflow Updates
- Update Neurosense CI to a supported Python version and invoke the shared module CI template.
- Copy the shared auto-merge and ci-failure-fix templates into Neurosense/.github/workflows/.

## Dependencies
- blocked-by local issue id: NSE-CDD-002
