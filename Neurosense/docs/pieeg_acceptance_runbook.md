# PiEEG Acceptance Prep Runbook

This runbook prepares the repo for a future real PiEEG acceptance run. It does
not claim that PiEEG hardware has already been validated.

Current support label for the PiEEG path: `experimental`

## Shared ADS1299 Profile

PiEEG reuses the same acquisition profile as OpenBCI Cyton in NeuroSense:

- 8 channels
- 250 Hz sampling rate
- impedance check uses the same BrainFlow channel-map path as Cyton

## What This Script Covers

The acceptance-prep script rehearses the flagship EMG workflow over the PiEEG
ADS1299 path:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

Checklist performed by `python -m neurosense.tests.validate_pieeg_hardware`:

- discover the active PiEEG target
- connect to PiEEG (or streaming-board relay)
- capture a short sample window
- build a flagship EMG recording artifact
- replay that artifact
- disconnect cleanly

## Prerequisites

- Python environment with NeuroSense backend dependencies installed
- For real-board prep on Raspberry Pi:
  BrainFlow built with `--build-periphery=ON` on the Pi itself
- For macOS dev-host relay:
  PiEEG board running on the Pi with a streaming-board publisher
- For rehearsal without hardware:
  use `--mock`

## Pi-Side Setup

On the Raspberry Pi with the PiEEG shield:

1. Build BrainFlow from source with periphery support:

```bash
python3 tools/build.py --build-periphery=ON
```

2. Start the PiEEG board and publish to a multicast stream:

```python
from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds

params = BrainFlowInputParams()
board = BoardShim(BoardIds.PIEEG_BOARD, params)
board.prepare_session()
board.start_stream()
board.add_streamer("streaming_board://225.1.1.1:6677", 0)
```

Leave this process running while the macOS host consumes the stream.

## macOS Host Relay Configuration

NeuroSense on the macOS host connects to BrainFlow's `STREAMING_BOARD` when
`NEUROSENSE_PIEEG_STREAM_HOST` is set.

Example configuration:

```bash
export NEUROSENSE_PIEEG_STREAM_HOST=225.1.1.1
export NEUROSENSE_PIEEG_STREAM_PORT=6677
```

PiEEG is only exposed for scanning when the stream host is configured or when
`--mock` is used.

## Commands

Mock rehearsal:

```bash
python -m neurosense.tests.validate_pieeg_hardware --mock --recordings-dir /tmp/neurosense-pieeg-rehearsal
```

Real-board prep using the streaming relay:

```bash
export NEUROSENSE_PIEEG_STREAM_HOST=225.1.1.1
python -m neurosense.tests.validate_pieeg_hardware --recordings-dir /tmp/neurosense-pieeg-run
```

Explicit stream-host override:

```bash
python -m neurosense.tests.validate_pieeg_hardware --stream-host 225.1.1.1 --recordings-dir /tmp/neurosense-pieeg-run
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

## Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| PiEEG target not discovered | Stream host not configured | Set `NEUROSENSE_PIEEG_STREAM_HOST` or pass `--mock` |
| Connection failed during session prepare/start | Pi stream not publishing | Verify `add_streamer` is running on the Pi |
| Acquisition returned no usable channels | Multicast blocked | Confirm host and Pi share the same network segment |
| Replay produced no usable chunk | Artifact write path mismatch | Re-run with a clean `--recordings-dir` |

## Acceptance Evidence

The script writes one JSON report per run:

- mock rehearsal: `pieeg_acceptance_mock.json`
- real-board execution: `pieeg_acceptance_real.json`
