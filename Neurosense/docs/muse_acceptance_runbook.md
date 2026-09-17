# Muse 2 / Muse S Acceptance Prep Runbook

This runbook prepares the repo for a future real Muse acceptance run. It does
not claim that Muse hardware has already been validated.

Current support label for the Muse EEG path: `experimental`

## What This Script Covers

The acceptance-prep script rehearses the EEG workflow:

`4-channel Muse EEG -> filter -> spike encoding -> record -> replay`

Checklist performed by `python -m neurosense.tests.validate_muse_hardware`:

- discover the active Muse target
- connect to Muse
- capture a short sample window
- build an EEG recording artifact
- replay that artifact
- disconnect cleanly

## Prerequisites

- Python environment with NeuroSense backend dependencies installed
- For real-board prep:
  BrainFlow with BLE support,
  Muse powered on and not connected to another app,
  and macOS Bluetooth enabled for native BLE boards
- For rehearsal without hardware:
  use `--mock`

## Configuration

Muse discovery is intentionally configuration-driven.

Muse appears for scanning when one of the following is true:

- `NEUROSENSE_MUSE_MODEL` is set to `muse2`, `muses`, or `bled`
- `--mock` is used

Optional environment variables:

- `NEUROSENSE_MUSE_MAC_ADDRESS` — pin a specific headset MAC address
- `NEUROSENSE_MUSE_PRESET` — Muse startup preset (default `p21`)

Board IDs used by NeuroSense:

| Model | Env value | BrainFlow board |
| --- | --- | --- |
| Muse 2 (native BLE) | `muse2` | `MUSE_2_BOARD` (38) |
| Muse S (native BLE) | `muses` | `MUSE_S_BOARD` (39) |
| Muse 2 BLED dongle fallback | `bled` | `MUSE_2_BLED_BOARD` (22) |

Example configuration:

```bash
export NEUROSENSE_MUSE_MODEL=muse2
export NEUROSENSE_MUSE_PRESET=p21
# optional:
export NEUROSENSE_MUSE_MAC_ADDRESS=00-11-22-33-44-55
```

## macOS BLE Notes

- Close the Muse mobile app and other BLE clients before connecting.
- Native BLE boards (`muse2`, `muses`) do not require a BLED112 dongle.
- If native BLE pairing fails, retry with `NEUROSENSE_MUSE_MODEL=bled` and the
  OpenBCI BLED dongle plugged in.

## Commands

Mock rehearsal:

```bash
python -m neurosense.tests.validate_muse_hardware --mock --recordings-dir /tmp/neurosense-muse-rehearsal
```

Real-board prep using environment configuration:

```bash
export NEUROSENSE_MUSE_MODEL=muse2
python -m neurosense.tests.validate_muse_hardware --recordings-dir /tmp/neurosense-muse-run
```

Muse S variant:

```bash
export NEUROSENSE_MUSE_MODEL=muses
python -m neurosense.tests.validate_muse_hardware --recordings-dir /tmp/neurosense-muse-run
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

## Muse-Specific Notes

- Default preset is `p21` (4 EEG channels at 256 Hz).
- Channel labels recorded in the artifact: `TP9`, `AF7`, `AF8`, `TP10`.
- Mock rehearsal still records the artifact as a Muse-targeted path, but it
  does not upgrade support level or count as real validation.

## Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| Muse target not discovered | Model env not set | Set `NEUROSENSE_MUSE_MODEL` or pass `--mock` |
| Connection failed during session prepare/start | Headset busy or BLE blocked | Close other Muse clients and retry pairing |
| Acquisition returned no usable EEG channels | Stream started but data path is empty | Recheck headset fit and BLE signal |
| Replay produced no usable chunk | Artifact write path mismatch | Re-run with a clean `--recordings-dir` |

## Acceptance Evidence

The script writes one JSON report per run:

- mock rehearsal: `muse_acceptance_mock.json`
- real-board execution: `muse_acceptance_real.json`
