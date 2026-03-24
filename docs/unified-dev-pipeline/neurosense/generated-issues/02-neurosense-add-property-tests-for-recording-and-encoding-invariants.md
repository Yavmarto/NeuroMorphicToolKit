# Neurosense: add property tests for recording and encoding invariants

**Module:** Neurosense
**Spec Source:** Neurosense/neurosense_spec.md#NSE-S1, Neurosense/neurosense_spec.md#NSE-S2
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add Hypothesis property tests verifying that all generated device+recording+encoding configurations satisfy domain invariants — no aliasing below Nyquist, buffer never exceeds memory limit, encoding preserves spike timing order.

## Conversion Steps
- [ ] Add properties for sampling rate vs. signal bandwidth (Nyquist)
- [ ] Add properties for buffer size vs. available memory
- [ ] Add properties for spike ordering preservation through encoding pipeline

## Contract Targets

## Property Targets
- `Neurosense/neurosense/tests/properties/test_encoding_properties.py`
- `Neurosense/neurosense/tests/properties/test_device_properties.py`

## Acceptance Checks
- [ ] 200+ examples generated per property in CI
- [ ] No aliasing violations detected
- [ ] Spike order always preserved through round-trip

## Dependencies
- blocked-by: `NSE-CDD-001`
