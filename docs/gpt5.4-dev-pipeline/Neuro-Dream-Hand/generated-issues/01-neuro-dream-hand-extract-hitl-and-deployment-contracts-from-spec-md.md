# Neuro-Dream-Hand: extract HITL and deployment contracts from SPEC.md

**Module:** Neuro-Dream-Hand
**Spec Source:** Neuro-Dream-Hand/SPEC.md#4.1 Serial Bridge, Neuro-Dream-Hand/SPEC.md#4.2 Force/Tactile Sensor Characterization, Neuro-Dream-Hand/SPEC.md#4.3 EMG Ingestion
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Convert the Hardware-in-the-Loop packet formats, calibration artifacts, EMG ingestion frames, and deployment result payloads into explicit contracts.

## Conversion
- Create contract models for serial command frames, sensor frames, calibration outputs, EMG stream frames, and experiment result manifests.
- Validate command and sensor payload sizes, checksums, and value ranges before using them.
- Route experiment output files through typed manifests.

## Contract Targets
- Neuro-Dream-Hand/neurodreamhand/hardware/contracts.py
- Neuro-Dream-Hand/neurodreamhand/experiments/contracts.py
- Neuro-Dream-Hand/tests/contracts/test_hardware_contracts.py

## Property Targets
- Neuro-Dream-Hand/tests/properties/test_serial_contract_properties.py
- Neuro-Dream-Hand/tests/properties/test_experiment_contract_properties.py

## Acceptance Checks
- Serial frame contracts enforce packet length, sentinels, and numeric bounds.
- Calibration manifests preserve slope and offset metadata.
- Experiment result manifests cannot omit baseline comparison fields.
