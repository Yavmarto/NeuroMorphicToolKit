# OpenBCI Cyton Acceptance Prep Runbook

This runbook prepares the repo for a future real `OpenBCI Cyton` acceptance
run. It does not claim that Cyton has already been validated on hardware.

Current support label for the Cyton flagship path: `experimental`

## What This Script Covers

The acceptance-prep script rehearses the flagship workflow:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

Checklist performed by `python -m neurosense.tests.validate_hardware`:

- discover the active Cyton target
- connect to Cyton
- capture a short sample window
- build a flagship EMG recording artifact
- replay that artifact
- disconnect cleanly

## Prerequisites

- Python environment with NeuroSense backend dependencies installed
- For real-board prep:
  BrainFlow available,
  a Cyton serial port known,
  and no competing process already holding the board
- For rehearsal without hardware:
  use `--mock`

## Configuration

Real-board discovery is intentionally narrow.

Cyton is only exposed for scanning when one of the following is true:

- `NEUROSENSE_CYTON_SERIAL_PORT` is set
- `--serial-port` is passed to the validation script
- `--mock` is used

Example serial-port environment setup:

```bash
export NEUROSENSE_CYTON_SERIAL_PORT=/dev/cu.usbserial-DM0258P6
```

## Commands

Mock rehearsal:

```bash
python -m neurosense.tests.validate_hardware --mock --recordings-dir /tmp/neurosense-cyton-rehearsal
```

Real-board prep using environment configuration:

```bash
export NEUROSENSE_CYTON_SERIAL_PORT=/dev/cu.usbserial-DM0258P6
python -m neurosense.tests.validate_hardware --recordings-dir /tmp/neurosense-cyton-run
```

Real-board prep using an explicit override:

```bash
python -m neurosense.tests.validate_hardware --serial-port /dev/cu.usbserial-DM0258P6 --recordings-dir /tmp/neurosense-cyton-run
```

## Expected Output

The script prints a pass/fail checklist for:

- discover target
- connect
- capture samples
- record artifact
- replay artifact
- disconnect

On success it also prints the generated artifact path.
Each run also writes machine-readable evidence JSON into the recordings
directory unless `--evidence-path` overrides it.

## Cyton-Specific Notes

- The script records the flagship artifact with:
  `preset_id=emg_prosthetic`,
  `signal_type=emg`,
  channel labels `flexor` and `extensor`
- The rehearsal filter inside the script uses a Cyton-compatible
  `20-100 Hz` passband with a `50 Hz` notch so acceptance prep stays
  consistent with a `250 Hz` acquisition path
- Mock rehearsal still records the artifact as a Cyton-targeted path, but it
  does not upgrade support level or count as real validation

## Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| Cyton target not discovered | Serial port not configured | Set `NEUROSENSE_CYTON_SERIAL_PORT` or pass `--serial-port` |
| Connection failed during session prepare/start | Wrong serial port or board busy | Verify the port and close other OpenBCI/BrainFlow clients |
| Acquisition returned no usable EMG channels | Stream started but data path is empty | Recheck board state, channel wiring, and serial target |
| Replay produced no usable chunk | Artifact write path mismatch | Re-run with a clean `--recordings-dir` and inspect the generated HDF5 |

## Acceptance Evidence

The script writes one JSON report per run:

- mock rehearsal: `cyton_acceptance_mock.json`
- real-board execution: `cyton_acceptance_real.json`

This evidence captures:

- whether the run used mocks
- the serial-port override used for the run
- pass/fail status for each checklist step
- the generated artifact path when recording succeeded
