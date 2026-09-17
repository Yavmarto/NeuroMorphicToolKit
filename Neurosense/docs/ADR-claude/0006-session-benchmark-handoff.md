# ADR 0006: Session Benchmark Handoff

## Status
Accepted

## Context
Recorded biosignal sessions in Neurosense need to be evaluated for encoding quality and performance metrics via Neurobench's benchmarking pipeline. The handoff between the two services requires a contract for what session data and metadata must be present.

## Decision
Neurosense exports session recordings as HDF5 artifacts with standardized metadata (device type, encoding config, channel labels, capture mode, support level) and optionally converts encoding configurations to NIR graphs via the `nir_service.py`. Neurobench can consume these artifacts by referencing the session's encoding metrics (spike rate, latency, fidelity) as benchmark inputs. The `export.py` router in Neurosense provides download endpoints for HDF5 artifacts and NIR graphs.

## Consequences
- **Positive:** HDF5 artifacts serve as a self-contained handoff package with full provenance metadata; NIR graph export enables hardware-agnostic representation for downstream benchmarking.
- **Negative:** The handoff is file-based rather than API-driven, requiring manual transfer or shared filesystem access; no validation that Neurobench can parse the specific HDF5 schema version produced by Neurosense.
