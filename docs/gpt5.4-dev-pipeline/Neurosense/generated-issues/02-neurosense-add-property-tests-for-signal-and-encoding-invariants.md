# Neurosense: add property tests for signal and encoding invariants

**Module:** Neurosense
**Spec Source:** Neurosense/neurosense_spec.md#NSe-SA2, Neurosense/neurosense_spec.md#NSe-SE2, Neurosense/neurosense_spec.md#NSe-R2, Neurosense/neurosense_spec.md#NSe-PI1
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Use Hypothesis to enforce time-domain, metadata, and pipeline invariants for biosignal acquisition and spike encoding.

## Conversion
- Add properties ensuring spike timestamps stay within session bounds and remain ordered.
- Add properties ensuring replay preserves event order and segment boundaries.
- Add properties for valid filter ranges and stable metadata propagation across exports.

## Contract Targets
- Neurosense/neurosense/app/contracts/export_contracts.py

## Property Targets
- Neurosense/neurosense/tests/properties/test_spike_time_properties.py
- Neurosense/neurosense/tests/properties/test_replay_properties.py
- Neurosense/neurosense/tests/properties/test_export_roundtrip_properties.py

## Acceptance Checks
- Spike timestamps cannot fall outside the acquisition or replay window.
- Exported metadata remains intact across import and export round trips.
- Filter configuration properties reject inverted frequency bands.

## Dependencies
- blocked-by local issue id: NSE-CDD-001
