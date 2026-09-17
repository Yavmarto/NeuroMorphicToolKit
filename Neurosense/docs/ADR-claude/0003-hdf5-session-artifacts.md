# ADR 0003: HDF5 Session Artifacts

## Status
Accepted

## Context
Recorded biosignal sessions must preserve full provenance (device type, encoding configuration, channel labels, timestamps) in a format compatible with scientific computing tools (NumPy, SciPy, MATLAB) and suitable for large multi-channel recordings.

## Decision
Use HDF5 files with a versioned schema (`ARTIFACT_SCHEMA_VERSION = "1.0"`) via lazy-loaded h5py. Complex metadata (encoding config, device parameters) is stored as JSON-serialized HDF5 attributes. Channel labels are normalized, and capture mode is inferred from device type via `infer_capture_mode()`.

## Consequences
- **Positive:** HDF5 handles large multi-channel recordings efficiently with random access; schema versioning enables forward-compatible artifact evolution.
- **Negative:** HDF5 files are binary and not human-readable; h5py dependency adds complexity and the lazy-loading pattern obscures import errors until runtime.
