# Session Artifact Contract

NeuroSense records flagship workflow sessions as HDF5 artifacts with canonical
schema version `1.0`.

The contract is the shared source of truth for:

- recorded-session metadata
- replay
- export
- `neurocnl` replay preparation
- `Neurobench` recording benchmarks
- `Neuro-Dream-Hand` prosthetic replay and intent-seeding inputs
- fixture-backed automated tests

Producer and owner:

- `NeuroSense` owns this artifact schema and its reusable EMG acquisition,
  filtering, encoding, recording, and replay semantics.

Current downstream consumers:

- `neurocnl`
- `Neurobench`
- `Neuro-Dream-Hand`

## Root Attributes

Required root attrs:

- `artifact_schema_version`
- `workflow_id`
- `workflow_label`
- `session_id`
- `timestamp`
- `duration_seconds`
- `device_type`
- `preset_id`
- `channels`
- `sampling_rate_hz`
- `signal_type`
- `capture_mode`
- `support_level`
- `channel_labels` as JSON list
- `hardware_provenance` as JSON object
- `encoding_config` as JSON object
- `subject_id` when provided

## Required Datasets And Groups

- `raw`: `(channels, samples)` float64
- `filtered`: `(channels, samples)` float64
- `timestamps`: `(samples,)` float64 seconds from recording start
- `markers/timestamps`: float64 marker offsets
- `markers/labels`: UTF-8 marker labels
- `spikes/batch_*`: per-batch spike groups with `method` attr and per-channel
  spike-time datasets

## Canonical Metadata Semantics

- `capture_mode`
  `live` for standard acquisition,
  `synthetic` for the validated BrainFlow synthetic path
- `support_level`
  `validated` for synthetic/fixture-backed artifact coverage,
  `experimental` for unvalidated real biosignal boards,
  `prototype` for PYNQ and Prophesee-style ingestion paths
- `hardware_provenance`
  contains enough detail to state what produced the session and what support
  level applies

## Checked-In Fixture

The canonical example artifact used by tests lives at:

`neurosense/tests/fixtures/canonical_emg_session.hdf5`

It represents the flagship forearm-EMG workflow with:

- `emg_prosthetic` preset metadata
- `flexor` and `extensor` channel labels
- `OpenBCI Cyton` recorded as the future target validation board
- `experimental` support level because no physical board has been validated yet
