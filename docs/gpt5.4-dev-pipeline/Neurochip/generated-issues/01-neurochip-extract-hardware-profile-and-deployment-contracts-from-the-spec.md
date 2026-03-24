# Neurochip: extract hardware profile and deployment contracts from the spec

**Module:** Neurochip
**Spec Source:** Neurochip/neurochip_spec.md#NC-T1, Neurochip/neurochip_spec.md#NC-C1, Neurochip/neurochip_spec.md#NC-FW1, Neurochip/neurochip_spec.md#NC-FW3, Neurochip/neurochip_spec.md#NC-P1
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Turn target galleries, compatibility reports, quantization requests, firmware bundles, and power estimates into explicit contract models instead of ad-hoc dictionaries.

## Conversion
- Create contract models for hardware profiles, compatibility reports, quantization jobs, firmware generation requests, and Loihi export packages.
- Normalize target capability fields such as neuron capacity, bit width, memory, and I/O count.
- Validate deployment artifact manifests before any compilation step starts.

## Contract Targets
- Neurochip/neurochip/app/contracts/hardware_contracts.py
- Neurochip/neurochip/app/contracts/deployment_contracts.py
- Neurochip/neurochip/tests/contracts/test_hardware_contracts.py

## Property Targets
- Neurochip/neurochip/tests/properties/test_hardware_profile_properties.py
- Neurochip/neurochip/tests/properties/test_deployment_contract_properties.py

## Acceptance Checks
- Hardware profiles reject invalid capacity, bit-width, memory, and I/O values.
- Firmware package contracts require the documented output files.
- Compatibility report payloads remain stable across serialization.
