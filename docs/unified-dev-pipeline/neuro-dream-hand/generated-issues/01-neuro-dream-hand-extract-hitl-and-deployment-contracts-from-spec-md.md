# Neuro-Dream-Hand: extract HITL and deployment contracts from SPEC.md

**Module:** Neuro-Dream-Hand
**Spec Source:** Neuro-Dream-Hand/SPEC.md#4.1 Serial Bridge, Neuro-Dream-Hand/SPEC.md#4.2 Force/Tactile Sensor Characterization, Neuro-Dream-Hand/SPEC.md#4.3 EMG Ingestion, Neuro-Dream-Hand/SPEC.md#5.1 Fault Injection
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Create Pydantic v2 contracts for serial protocol, EMG stream, sensor frames, fault injection, crossbar export, and drop-test validation. Reference implementation in docs/unified-dev-pipeline/neuro-dream-hand/contracts/.

## Conversion Steps
- [ ] Copy hardware_contracts.py — SerialBridgeContract, SensorFrameContract, EMGStreamContract, EMGSpikeOutputContract, HITLLatencyContract, FaultInjectionContract, CrossbarExportContract, DropTestContract
- [ ] Validate command and sensor payload sizes, checksums, and value ranges before use
- [ ] Route experiment output files through typed manifests

## Contract Targets
- `Neuro-Dream-Hand/neurodreamhand/hardware/contracts.py`
- `Neuro-Dream-Hand/neurodreamhand/experiments/contracts.py`

## Property Targets

## Acceptance Checks
- [ ] Out-of-range grip (>1.0, <0.0) raises ValidationError
- [ ] ADC values > 4095 raise ValidationError
- [ ] Fault fractions > 30% raise ValidationError
- [ ] Serial frame contracts enforce packet length, sentinels, and bounds
