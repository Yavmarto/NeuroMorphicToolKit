# Neurosense: extract device, recording, and encoding contracts from the spec

**Module:** Neurosense
**Spec Source:** Neurosense/neurosense_spec.md#NSe-DM1, Neurosense/neurosense_spec.md#NSe-SA1, Neurosense/neurosense_spec.md#NSe-SE1, Neurosense/neurosense_spec.md#NSe-R1, Neurosense/neurosense_spec.md#NSe-PI2
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Convert device descriptors, acquisition presets, recording sessions, export payloads, and encoding configuration into explicit contract models.

## Conversion
- Create contract models for detected devices, electrode presets, stream settings, encoding presets, session recordings, and export payloads.
- Validate user-supplied filter and encoding parameters before streaming begins.
- Normalize metadata fields required for replay and cross-tool export.

## Contract Targets
- Neurosense/neurosense/app/contracts/device_contracts.py
- Neurosense/neurosense/app/contracts/encoding_contracts.py
- Neurosense/neurosense/app/contracts/recording_contracts.py
- Neurosense/neurosense/tests/contracts/test_encoding_contracts.py

## Property Targets
- Neurosense/neurosense/tests/properties/test_encoding_contract_properties.py
- Neurosense/neurosense/tests/properties/test_recording_contract_properties.py

## Acceptance Checks
- Contracts reject impossible sample rates, filter ranges, and device metadata.
- Recorded-session manifests contain the metadata needed for replay and export.
- Encoding preset serialization is stable across round trips.
