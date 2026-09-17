# GUARDRAILS.md - NeuroSense Development Guardrails

These guardrails ensure the stability and reliability of the NeuroSense toolkit.

## 1. Data Integrity Guardrails
- **No Direct Artifact Edits:** Never edit files in `dist/`, `build/`, or generated code. Edit the source and rebuild.
- **Strict Schema Validation:** All API inputs/outputs must be validated against Pydantic models in `neurosense/app/schemas/`.
- **Recording Formats:** Only HDF5 (primary) and CSV (interoperability) are supported for biosignal recordings.

## 2. Performance Guardrails
- **Real-time Constraints:** Signal processing and encoding must maintain < 100ms end-to-end latency.
- **Memory Limits:** In-memory buffers for raw data must not exceed 100MB per session. Use chunked writing for HDF5.
- **Vectorization:** Use NumPy vectorized operations for signal processing; avoid Python loops in the data path.

## 3. Safety Guardrails
- **Device Isolation:** Ensure `BrainFlow` handles are properly released on disconnect or app crash to prevent hardware lockup.
- **Impedance Checks:** Must be performed and verified "Good" before high-gain EMG/EEG acquisition.
- **Error Propagation:** All hardware-level errors must be mapped to human-readable `NeuromorphicDeviceError` types.

## 4. Compliance & Verification
- **CI/CD Requirements:** All PRs must pass Ruff (linting), Mypy (types), and Pytest (unit/integration).
- **PBT Coverage:** New encoding or filtering logic must include Hypothesis-based property tests.
- **Documentation:** Any change to the encoding pipeline must be reflected in `neurosense_spec.md`.
