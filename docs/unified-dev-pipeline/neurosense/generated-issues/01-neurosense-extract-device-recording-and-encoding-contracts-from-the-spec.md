# Neurosense: extract device, recording, and encoding contracts from the spec

**Module:** Neurosense
**Spec Source:** Neurosense/neurosense_spec.md#NSE-D1, Neurosense/neurosense_spec.md#NSE-D2, Neurosense/neurosense_spec.md#NSE-D3
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Create Pydantic contracts for device configurations, recording parameters, and spike encoding constraints. Validate channel counts, sampling rates, gain ranges, and encoding thresholds at the type boundary.

## Conversion Steps
- [ ] Create DeviceConfig contract: channel count 1-1024, sample rate 1kHz-40kHz, gain 0.1-1000x
- [ ] Create RecordingParams contract: duration, buffer size, file format constraints
- [ ] Create EncodingConfig contract: threshold bounds, refractory period, temporal resolution

## Contract Targets
- `Neurosense/neurosense/contracts/device_contracts.py`
- `Neurosense/neurosense/contracts/recording_contracts.py`
- `Neurosense/neurosense/contracts/encoding_contracts.py`

## Property Targets

## Acceptance Checks
- [ ] Device contracts reject channel counts outside 1-1024
- [ ] Recording contracts reject negative durations
- [ ] Encoding contracts enforce refractory period > 0
