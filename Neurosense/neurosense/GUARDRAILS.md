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
- **Stream Buffer Limits:** Internal memory buffers for streaming data must enforce strict size limits (e.g., max 10 seconds of data) to prevent memory leaks and out-of-memory errors during long-running sessions.
- **Max Sampling Rate:** To maintain system stability and encoding fidelity, the maximum supported sampling rate must be strictly enforced (e.g., 40,000 Hz). Exceeding this rate will trigger a domain constraint violation.
- **Encoding Precision Bounds:** Signal encodings (e.g., rate coding, temporal coding) must be strictly bounded. Invalid or divergent inputs must not produce invalid spikes.
- **Device Connection Timeouts:** Hardware connections must implement explicit timeouts. If a device fails to respond during the connection phase within the timeout window, the connection attempt must be aborted to prevent thread blocking.

## 4. Compliance & Verification
- **CI/CD Requirements:** All PRs must pass Ruff (linting), Mypy (types), and Pytest (unit/integration).
- **PBT Coverage:** New encoding or filtering logic must include Hypothesis-based property tests.
- **Documentation:** Any change to the encoding pipeline must be reflected in `neurosense_spec.md`.
