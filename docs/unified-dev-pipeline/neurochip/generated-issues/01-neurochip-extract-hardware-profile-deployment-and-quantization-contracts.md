# Neurochip: extract hardware profile, deployment, and quantization contracts

**Module:** Neurochip
**Spec Source:** Neurochip/neurochip_spec.md#NC-D1, Neurochip/neurochip_spec.md#NC-D2, Neurochip/neurochip_spec.md#NC-D3
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Create Pydantic contracts for hardware profiles (core count, memory, clock), deployment manifests (target device, firmware version, checksum), and quantization configs (bit-width, scaling factors). Enforce chip-specific limits at the type boundary.

## Conversion Steps
- [ ] Create HardwareProfile contract: core count 1-128, memory 1KB-16MB, clock 1MHz-1GHz
- [ ] Create DeploymentManifest contract: target device enum, firmware semver, checksum SHA-256
- [ ] Create QuantizationConfig contract: bit-width 1-16, scaling factor > 0, rounding mode

## Contract Targets
- `Neurochip/neurochip/contracts/hardware_contracts.py`
- `Neurochip/neurochip/contracts/deployment_contracts.py`
- `Neurochip/neurochip/contracts/quantization_contracts.py`

## Property Targets

## Acceptance Checks
- [ ] Hardware profile contracts reject core counts outside 1-128
- [ ] Deployment contracts reject invalid firmware versions
- [ ] Quantization contracts enforce bit-width 1-16
