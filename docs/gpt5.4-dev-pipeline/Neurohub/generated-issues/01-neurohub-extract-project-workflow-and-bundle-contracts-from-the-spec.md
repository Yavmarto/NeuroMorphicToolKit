# Neurohub: extract project, workflow, and bundle contracts from the spec

**Module:** Neurohub
**Spec Source:** Neurohub/neurohub_spec.md#NH-P1, Neurohub/neurohub_spec.md#NH-P2, Neurohub/neurohub_spec.md#NH-A2, Neurohub/neurohub_spec.md#NH-W1, Neurohub/neurohub_spec.md#NH-H2
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Convert cross-app project metadata, workflow templates, health configuration, and bundle import/export formats into explicit contracts.

## Conversion
- Create contract models for projects, milestones, bundle manifests, workflow steps, and suite configuration entries.
- Require step success criteria and failure actions in workflow definitions.
- Validate bundle manifests before import or export starts.

## Contract Targets
- Neurohub/neurohub/app/contracts/project_contracts.py
- Neurohub/neurohub/app/contracts/workflow_contracts.py
- Neurohub/neurohub/app/contracts/bundle_contracts.py
- Neurohub/neurohub/tests/contracts/test_project_contracts.py

## Property Targets
- Neurohub/neurohub/tests/properties/test_project_roundtrip_properties.py
- Neurohub/neurohub/tests/properties/test_workflow_contract_properties.py

## Acceptance Checks
- Workflow definitions reject missing success criteria or invalid failure actions.
- Bundle manifests preserve project metadata across export/import round trips.
- Health configuration accepts only known suite services.
