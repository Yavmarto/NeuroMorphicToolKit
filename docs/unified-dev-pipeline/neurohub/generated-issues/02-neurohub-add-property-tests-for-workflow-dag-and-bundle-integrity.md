# Neurohub: add property tests for workflow DAG and bundle integrity

**Module:** Neurohub
**Spec Source:** Neurohub/neurohub_spec.md#NH-S1, Neurohub/neurohub_spec.md#NH-S2
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add Hypothesis property tests verifying workflow DAG topological ordering, bundle checksum consistency, and project module reference integrity.

## Conversion Steps
- [ ] Add properties for DAG validity: no generated workflow has cycles
- [ ] Add properties for bundle integrity: checksum matches re-computed hash
- [ ] Add properties for project references: all module IDs resolve to known modules

## Contract Targets

## Property Targets
- `Neurohub/neurohub/tests/properties/test_workflow_properties.py`
- `Neurohub/neurohub/tests/properties/test_bundle_properties.py`

## Acceptance Checks
- [ ] 200+ examples generated per property in CI
- [ ] No cyclic workflows accepted
- [ ] Bundle checksums never mismatch

## Dependencies
- blocked-by: `NH-CDD-001`
