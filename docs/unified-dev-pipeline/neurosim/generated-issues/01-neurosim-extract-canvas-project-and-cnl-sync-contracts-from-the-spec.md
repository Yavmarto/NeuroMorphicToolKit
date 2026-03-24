# Neurosim: extract canvas, project, and CNL-sync contracts from the spec

**Module:** Neurosim
**Spec Source:** Neurosim/neurosim_spec.md#NS-D1, Neurosim/neurosim_spec.md#NS-D2, Neurosim/neurosim_spec.md#NS-S3, Neurosim/neurosim_spec.md#NS-C1
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Convert canvas nodes, edges, projects, sweep configs, and CNL synchronization payloads into explicit Pydantic contracts. Reference: docs/unified-dev-pipeline/neurosim/contracts/design_contracts.py.

## Conversion Steps
- [ ] Create contract models for node types, connections, parameter panels, project files, and sync payloads
- [ ] Enforce preview <=500ms simulation time, sweep max 20 steps, canvas graph validity
- [ ] Validate export format constraints before any compilation

## Contract Targets
- `Neurosim/neurosim/contracts/design_contracts.py`

## Property Targets

## Acceptance Checks
- [ ] Preview contracts reject simulations exceeding 500ms
- [ ] Sweep contracts reject step counts above 20
- [ ] Canvas graph contracts reject dangling connections
