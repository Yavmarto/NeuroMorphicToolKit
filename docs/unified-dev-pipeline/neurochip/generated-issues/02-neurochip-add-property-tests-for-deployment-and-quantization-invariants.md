# Neurochip: add property tests for deployment and quantization invariants

**Module:** Neurochip
**Spec Source:** Neurochip/neurochip_spec.md#NC-S1, Neurochip/neurochip_spec.md#NC-S2
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add Hypothesis property tests verifying deployment integrity and quantization precision loss bounds.

## Conversion Steps
- [ ] Add properties for deployment manifest completeness and checksum validity
- [ ] Add properties for quantization: precision loss below threshold for any valid config
- [ ] Add properties for hardware profile: memory fits all allocated neurons

## Contract Targets

## Property Targets
- `Neurochip/neurochip/tests/properties/test_deployment_properties.py`
- `Neurochip/neurochip/tests/properties/test_quantization_properties.py`

## Acceptance Checks
- [ ] 200+ examples generated per property in CI
- [ ] No deployment missing required fields
- [ ] Quantization precision loss within documented bounds

## Dependencies
- blocked-by: `NC-CDD-001`
