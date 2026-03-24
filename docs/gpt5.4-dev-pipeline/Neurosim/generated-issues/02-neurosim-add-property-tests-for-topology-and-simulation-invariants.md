# Neurosim: add property tests for topology and simulation invariants

**Module:** Neurosim
**Spec Source:** Neurosim/neurosim_spec.md#NS-D3, Neurosim/neurosim_spec.md#NS-S1, Neurosim/neurosim_spec.md#NS-S2, Neurosim/neurosim_spec.md#NS-E1
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Encode the visual editor and simulation invariants so invalid graphs and impossible parameter states cannot pass CI.

## Conversion
- Add properties for parameter bounds, sweep ranges, and graph consistency.
- Add properties for canvas-to-CNL and CNL-to-canvas round trips.
- Add export properties ensuring the canonical CNL export stays stable across conversions.

## Contract Targets
- Neurosim/neurosim/app/contracts/export_contracts.py

## Property Targets
- Neurosim/neurosim/tests/properties/test_parameter_bounds.py
- Neurosim/neurosim/tests/properties/test_cnl_roundtrip_properties.py
- Neurosim/neurosim/tests/properties/test_export_properties.py

## Acceptance Checks
- Parameter sweeps reject invalid ranges and step counts.
- Graph round trips preserve directed-edge semantics.
- Export paths cannot silently drop project metadata.

## Dependencies
- blocked-by local issue id: NS-CDD-001
