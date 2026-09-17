# NeuroSense To Toolkit Handoff

This guide documents the current canonical artifact handoff from NeuroSense
into `neurocnl`, `Neurobench`, and `Neuro-Dream-Hand`.

## Shared Input

All downstream consumers use the canonical NeuroSense HDF5 artifact described in
[session_artifact_contract.md](session_artifact_contract.md).

Recommended starting artifact:

`neurosense/tests/fixtures/canonical_emg_session.hdf5`

## NeuroCNL Replay Prep

`neurocnl` exposes a replay-preparation endpoint that turns a canonical
NeuroSense recording into EMG frame previews plus spike/provenance metadata.

Example:

```bash
curl -sS \
  -X POST http://127.0.0.1:8000/api/prosthetic/neurosense/replay \
  -H 'Content-Type: application/json' \
  -d '{
    "artifact_path": "/absolute/path/to/canonical_emg_session.hdf5",
    "preview_frames": 3
  }'
```

What it proves today:

- the artifact is readable by `neurocnl`
- schema version `1.0` is enforced
- EMG frames can be prepared for replay-oriented workflows without ad hoc
  conversion
- spike/provenance metadata survives the handoff

## Neurobench Recording Benchmark

`Neurobench` now includes the builtin benchmark
`neurosense_replay_contract`.

Example:

```bash
curl -sS \
  -X POST http://127.0.0.1:8000/api/neurobench/run \
  -H 'Content-Type: application/json' \
  -d '{
    "benchmark_id": "neurosense_replay_contract",
    "network_path": "unused-for-recording-benchmark.cnl",
    "params": {
      "artifact_path": "/absolute/path/to/canonical_emg_session.hdf5"
    }
  }'
```

What it measures today:

- artifact ingest latency
- presence of spike batches and spike events
- duration, channel count, and provenance metadata needed for replay benchmarks

## Neuro-Dream-Hand Prosthetic Input

`Neuro-Dream-Hand` consumes the same canonical artifact as a downstream
prosthetic-domain input, not as a second owner of generic EMG acquisition or
encoding semantics.

What it proves today:

- prosthetic workflows can point at a canonical NeuroSense artifact instead of a
  module-local EMG schema
- support-level and provenance metadata survive into the prosthetic consumer
- the consumer-versus-owner split stays explicit in contract tests

## Current Scope

- This handoff is currently file-based.
- `neurocnl` replay prep is truthful preparation for downstream workflows, not a
  claim that continuous artifact-driven simulation is fully validated.
- `Neurobench` recording support currently benchmarks the artifact contract and
  ingest path first; it does not yet replace richer downstream evaluation flows.
- `Neuro-Dream-Hand` keeps prosthetic-specific HITL control and intent mapping,
  but the generic biosignal artifact contract remains owned by `NeuroSense`.
