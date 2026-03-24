# Neurohub: extract project, workflow, and bundle contracts from the spec

**Module:** Neurohub
**Spec Source:** Neurohub/neurohub_spec.md#NH-D1, Neurohub/neurohub_spec.md#NH-D2, Neurohub/neurohub_spec.md#NH-D3
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Create Pydantic contracts for project entities (name, owner, module list), workflow definitions (DAG of steps, execution order), and export bundles (format, contents checksum). Enforce referential integrity between projects and their contained modules.

## Conversion Steps
- [ ] Create ProjectConfig contract: name non-empty, owner valid, module refs exist
- [ ] Create WorkflowDefinition contract: DAG validity, no cycles, all step refs resolve
- [ ] Create ExportBundle contract: format enum, contents list, SHA-256 checksum

## Contract Targets
- `Neurohub/neurohub/contracts/project_contracts.py`
- `Neurohub/neurohub/contracts/workflow_contracts.py`
- `Neurohub/neurohub/contracts/bundle_contracts.py`

## Property Targets

## Acceptance Checks
- [ ] Project contracts reject empty names
- [ ] Workflow contracts reject cyclic step graphs
- [ ] Bundle contracts enforce valid checksums
