# Neurochip: add property tests for hardware and quantization invariants

**Module:** Neurochip
**Spec Source:** Neurochip/neurochip_spec.md#NC-Q1, Neurochip/neurochip_spec.md#NC-Q2, Neurochip/neurochip_spec.md#NC-F1, Neurochip/neurochip_spec.md#NC-P1
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Encode hardware and physics-related invariants so deployment code cannot pass CI while violating capacity, quantization, or power bounds.

## Conversion
- Add properties for positive capacity, non-negative latency and power estimates, and allowed quantization bit-widths.
- Add robustness properties to ensure increasing fault rates do not yield impossible improvements without an explicit model explanation.
- Add deployment artifact completeness properties for Teensy and Loihi exports.

## Contract Targets
- Neurochip/neurochip/app/contracts/quantization_contracts.py

## Property Targets
- Neurochip/neurochip/tests/properties/test_quantization_properties.py
- Neurochip/neurochip/tests/properties/test_fault_tolerance_properties.py
- Neurochip/neurochip/tests/properties/test_power_latency_properties.py

## Acceptance Checks
- Bit-width requests are limited to supported discrete values.
- Power and latency estimates are never negative.
- Generated deployment packages cannot omit required manifest files.

## Dependencies
- blocked-by local issue id: NC-CDD-001
