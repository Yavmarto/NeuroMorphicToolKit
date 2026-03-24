# Neuro-Dream-Hand: add property tests for physical and hardware invariants

**Module:** Neuro-Dream-Hand
**Spec Source:** Neuro-Dream-Hand/SPEC.md#Context: What the simulation has established, Neuro-Dream-Hand/SPEC.md#4.1 Serial Bridge
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add 11 Hypothesis property tests for grip clamping, serial packets, ADC range, EMG output, fault injection bounds, crossbar conductance, and drop-test gap. Reference implementation in docs/unified-dev-pipeline/neuro-dream-hand/properties/.

## Conversion Steps
- [ ] Copy test_hitl_properties.py — TestSerialProtocolProperties, TestSensorFrameProperties, TestEMGProperties, TestFaultInjectionProperties, TestCrossbarProperties, TestDropTestProperties
- [ ] Configure Hypothesis CI profile

## Contract Targets

## Property Targets
- `Neuro-Dream-Hand/tests/properties/test_hitl_properties.py`

## Acceptance Checks
- [ ] Grip commands stay in 0.0 to 1.0 range
- [ ] Serial packet parsing is stable under randomized valid/invalid frames
- [ ] Physical metric reports never produce negative values

## Dependencies
- blocked-by: `NDH-CDD-001`
