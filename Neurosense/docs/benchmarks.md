# NeuroSense Benchmark Baselines

This document records the current benchmark baseline for the flagship
workflow:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

## Command

```bash
python -m neurosense.scripts.benchmark_pipeline --json
```

Measured on 2026-04-14 against:

- artifact: `neurosense/tests/fixtures/canonical_emg_session.hdf5`
- benchmark iterations: `5`
- replay chunk size: `50`
- environment: local NeuroSense `venv` in this checkout

## Current Baseline

| Metric | Measured value |
| --- | --- |
| artifact load average | `1.291 ms` |
| filter average | `0.140 ms` |
| encode average | `0.071 ms` |
| replay wall time | `1.113 ms` |
| replay throughput | `134750.671 samples/s` |
| channels | `2` |
| sampling rate | `200 Hz` |
| support level | `experimental` |

## Interpretation

- These numbers are fixture-backed software baselines, not real-board latency
  claims.
- The replay throughput measurement disables pacing so it can act as a stable
  regression benchmark for chunk emission rather than a wall-clock hardware
  claim.
- The artifact remains labeled `experimental` because no physical Cyton run has
  been accepted yet.

## Regression Thresholds

Treat the current baseline as the reference for local regression checks.

- artifact load should remain under `10 ms` for the canonical fixture
- filter should remain under `5 ms`
- encode should remain under `5 ms`
- replay throughput should remain above `10000 samples/s`
