# ADR 0005: Quality Analysis and Replay

## Status
Accepted

## Context
Users need to verify that recorded biosignal sessions are usable before feeding them into SNN pipelines. Bad recordings (excessive noise, lost channels, clipping) waste downstream compute and produce meaningless results.

## Decision
Implement a `quality_analyzer.py` for assessing signal quality metrics (SNR, channel dropout, clipping detection) and a `replay_service.py` for re-playing recorded HDF5 sessions through the encoding pipeline. Both services operate on HDF5 artifacts via the `pipeline_bridge.py` integration layer.

## Consequences
- **Positive:** Quality analysis catches bad recordings before they enter expensive simulation pipelines; replay enables iterative encoding parameter tuning on captured data.
- **Negative:** Quality metrics are heuristic-based and may not capture all failure modes; replaying large sessions through the full pipeline is compute-intensive.
