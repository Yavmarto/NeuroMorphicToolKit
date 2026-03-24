# Neurosense: upgrade CI to 3.11 and add CDD-PBT verification

**Module:** Neurosense
**Spec Source:** 
**Labels:** feature, cdd-pbt, migration, ci

## Objective
Update CI to Python 3.11, add lint + type-check + property test steps, and wire in the reusable CDD-PBT module CI template.

## Conversion Steps
- [ ] Update Python version in ci.yml from 3.10 to 3.11
- [ ] Add ruff check, mypy, and property test steps
- [ ] Add ci-failure-fix.yml and auto-merge workflows

## Contract Targets
- `Neurosense/.github/workflows/ci.yml`

## Property Targets

## Acceptance Checks
- [ ] CI passes on Python 3.11
- [ ] Lint and type errors surface in PR checks
- [ ] Property tests run as part of CI

## Workflow Updates
- [ ] Update Neurosense ci.yml Python version from 3.10 to 3.11
- [ ] Add reusable CDD-PBT job call

## Dependencies
- blocked-by: `NSE-CDD-002`
