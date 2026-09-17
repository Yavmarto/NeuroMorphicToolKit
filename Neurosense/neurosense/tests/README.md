# NeuroSense Tests

This directory contains unit and integration tests for the NeuroSense backend.

## Running Tests

### Standard Test Suite
Run all tests using pytest:
```bash
PYTHONPATH=. pytest neurosense/tests/
```

### Integration Smoke Test
The integration smoke test validates the end-to-end signal flow from device acquisition to data export.

**Command:**
```bash
PYTHONPATH=. pytest neurosense/tests/test_smoke.py
```

**Expected Runtime:** ~5-10 seconds.

**Flow:**
1. Connects to a synthetic BrainFlow device.
2. Starts a session recording.
3. Streams raw data via WebSockets to verify ingestion.
4. Inserts a timestamped event marker.
5. Stops the recording and persists to HDF5.
6. Exports the session data to CSV and HDF5 formats.
7. Validates export payload integrity and metadata.

## Directory Structure
- `properties/`: Property-based tests using Hypothesis for contract invariants.
- `mock_device.py`: Mock BrainFlow board implementation for hardware-free testing.
- `test_smoke.py`: End-to-end integration smoke test.
