# Neurohub: add property tests for orchestration invariants

**Module:** Neurohub
**Spec Source:** Neurohub/neurohub_spec.md#NH-W1, Neurohub/neurohub_spec.md#NH-W2, Neurohub/neurohub_spec.md#NH-W3, Neurohub/neurohub_spec.md#NH-H1
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Use property tests to enforce orchestration behavior, especially for pipeline stop conditions, cross-app links, and bundle integrity.

## Conversion
- Add properties ensuring workflow steps execute in topological order and stop on configured hard failures.
- Add properties for bundle round trips and cross-app asset link preservation.
- Add properties constraining suite health states and response-time fields.

## Contract Targets
- Neurohub/neurohub/app/contracts/health_contracts.py

## Property Targets
- Neurohub/neurohub/tests/properties/test_workflow_execution_properties.py
- Neurohub/neurohub/tests/properties/test_bundle_roundtrip_properties.py
- Neurohub/neurohub/tests/properties/test_health_state_properties.py

## Acceptance Checks
- A pipeline cannot report success if a hard-fail step is skipped after an error.
- Bundle import and export preserve linked asset references.
- Health entries stay within the online/offline/degraded state set.

## Dependencies
- blocked-by local issue id: NH-CDD-001
