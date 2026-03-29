# Neurosim: extract canvas, project, and CNL-sync contracts from the spec

**Module:** Neurosim
**Spec Source:** Neurosim/neurosim_spec.md#NS-D1, Neurosim/neurosim_spec.md#NS-D2, Neurosim/neurosim_spec.md#NS-D5, Neurosim/neurosim_spec.md#NS-S3, Neurosim/neurosim_spec.md#NS-C1
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Convert canvas nodes, edges, projects, sweep configs, and CNL synchronization payloads into explicit contracts.

## Conversion
- Create contract models for node types, connections, parameter panels, project files, and sync payloads.
- Validate connection weights, delays, and allowed layer references before backend simulation calls.
- Make .neurosim project files parse through a single shared contract layer.

## Contract Targets
- Neurosim/neurosim/app/contracts/canvas_contracts.py
- Neurosim/neurosim/app/contracts/project_contracts.py
- Neurosim/neurosim/tests/contracts/test_canvas_contracts.py

## Property Targets
- Neurosim/neurosim/tests/properties/test_canvas_roundtrip_properties.py
- Neurosim/neurosim/tests/properties/test_sync_contract_properties.py

## Acceptance Checks
- Canvas JSON round-trips through contracts without topology loss.
- Invalid connection payloads fail fast with clear reasons.
- CNL sync payloads cannot omit required network metadata.
