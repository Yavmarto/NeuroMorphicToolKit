# Neuro-Dream-Hand: add property tests for physical and hardware invariants

**Module:** Neuro-Dream-Hand
**Spec Source:** Neuro-Dream-Hand/SPEC.md#Context: What the simulation has established, Neuro-Dream-Hand/SPEC.md#4.1 Serial Bridge
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Encode the physical and hardware invariants so agent-written HITL code cannot pass CI while breaking packet, calibration, or range assumptions.

## Conversion
- Add properties for grip-command clamping, serial packet checksums, and sensor frame parsing.
- Add properties for non-negative latency, valid force ranges, and calibration monotonicity.
- Add properties that bound quantization and hardware comparison metrics to physically meaningful ranges.

## Contract Targets
- Neuro-Dream-Hand/neurodreamhand/hardware/serial_bridge.py

## Property Targets
- Neuro-Dream-Hand/tests/properties/test_packet_properties.py
- Neuro-Dream-Hand/tests/properties/test_calibration_properties.py
- Neuro-Dream-Hand/tests/properties/test_metric_bound_properties.py

## Acceptance Checks
- Grip commands stay in the documented 0.0 to 1.0 range.
- Serial packet parsing is stable under randomized valid and invalid frames.
- Physical metric reports never produce impossible negative values.

## Dependencies
- blocked-by local issue id: NDH-CDD-001
