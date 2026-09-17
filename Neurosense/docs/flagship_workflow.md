# Flagship Workflow

NeuroSense currently treats the following as its credibility target:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

Everything in the module should be described relative to this path first.

## Workflow Definition

- Signal type: `emg`
- Preset: `emg_prosthetic`
- Channel labels: `flexor`, `extensor`
- Preferred future physical target: `OpenBCI Cyton`
- Current validated artifact path: canonical HDF5 recording fixture and
  synthetic-path recording/replay tests
- Primary outputs:
  raw analog samples,
  filtered samples,
  timestamps,
  spike batches,
  event markers,
  encoding metadata,
  hardware provenance

## Support Statement

- `OpenBCI Cyton` is the default real-board target for this workflow, but it is
  still `experimental` until a real acceptance script passes on hardware.
- Synthetic BrainFlow acquisition plus fixture-backed replay/export coverage is
  the only `validated` path in this slice.
- Other BrainFlow board families remain `experimental`.

## Success Metrics

These are the workflow success criteria for the credibility pass, not measured
performance claims yet:

- Sampling rate target: `250 Hz` for the first Cyton-backed EMG path
- Latency budget target: `< 50 ms` acquisition-to-display and
  `< 100 ms` replay-to-downstream handoff, to be measured in the later
  benchmarking slice
- Data integrity:
  raw, filtered, and timestamp datasets stay shape-aligned;
  timestamps are monotonic;
  channel labels and preset metadata are preserved in the artifact
- Replay correctness:
  replay reads the same canonical HDF5 contract used for live recording;
  markers remain addressable;
  artifact metadata is preserved for export and downstream reuse

## Downstream Consumers

- Current downstream consumers: session listing, replay, and export
- Planned downstream consumers: NeuroCNL replay input routing and Neurobench
  replay-based evaluation
