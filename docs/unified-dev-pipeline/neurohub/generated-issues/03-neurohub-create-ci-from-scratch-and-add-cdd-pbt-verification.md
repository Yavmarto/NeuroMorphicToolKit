# Neurohub: create CI from scratch and add CDD-PBT verification

**Module:** Neurohub
**Spec Source:**
**Labels:** feature, cdd-pbt, migration, ci, critical

## Objective
CRITICAL: Neurohub has no CI at all. Create ci.yml from scratch with full lint + type-check + test + property test pipeline. Add Jules automation workflows.

## Conversion Steps
- [ ] Create ci.yml from the reusable CDD-PBT module CI template
- [ ] Add all standard steps: checkout, setup-python 3.11, pip install, ruff, mypy, pytest, property tests
- [ ] Add ci-failure-fix.yml and auto-merge-jules-prs.yml

## Contract Targets
- `Neurohub/.github/workflows/ci.yml`

## Property Targets

## Acceptance Checks
- [ ] Neurohub has a working CI for the first time
- [ ] All standard checks run on pull requests
- [ ] Jules automation workflows are present

## Workflow Updates
- [ ] Create Neurohub ci.yml from scratch
- [ ] Copy shared auto-merge and ci-failure-fix templates

## Dependencies
- blocked-by: `NH-CDD-002`
