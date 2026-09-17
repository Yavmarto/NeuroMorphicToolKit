# Hardware-in-the-Loop (HITL) Testing Procedure

This document describes the procedure for verifying the NeuroSense hardware integration using simulated hardware.

Current support-level interpretation:

- `validated`: synthetic BrainFlow path plus canonical session-artifact tests
- `experimental`: real biosignal boards such as OpenBCI Cyton and Ganglion
- `prototype`: PYNQ Edge Node and Prophesee EVK integrations. Features for these devices are described truthfully relative to their current implementation state; they are not fully validated hardware-ready paths.

## Overview

Since physical biosignal hardware may not always be available during development
and CI, NeuroSense provides a `MockBoardShim` to simulate the BrainFlow
interface. This allows the recording, replay, and export contract to be tested
without claiming that a physical board has already been validated.

## Simulated Hardware Test Suite

The primary integration test suite is located at `neurosense/tests/test_hardware_integration.py`. This suite performs the following checks:

1.  **Full Pipeline Acquisition**: Verifies that data can be acquired from the simulated device, passed through the `FilterPipeline`, and then encoded by the `SpikeEncoder`.
2.  **Reconnection Handling**: Ensures that the system can cleanly disconnect and reconnect to a device without errors or resource leaks.
3.  **Error Recovery**: Simulates hardware-level failures (e.g., a `RuntimeError` during stream start) and verifies that the `DeviceManager` handles them gracefully, maintaining a consistent internal state.

## Running the Tests

To run the HITL tests, ensure you have the necessary dependencies installed:

```bash
pip install brainflow pydantic fastapi uvicorn numpy scipy websockets httpx h5py aiohttp pytest pytest-asyncio anyio nir python-multipart
```

Then, execute the tests using `pytest`:

```bash
pytest neurosense/tests/test_hardware_integration.py
```

## Mock Device Implementation

The `MockBoardShim` is implemented in `neurosense/tests/mock_device.py`. It generates synthetic EEG data consisting of sine waves with added Gaussian noise. Each channel has a distinct frequency to facilitate verification of the filtering and encoding steps.

### Customizing the Mock

You can customize the mock device's behavior by subclassing `MockBoardShim` or by modifying its methods. For example, to simulate a hardware failure, you can override the `start_stream` method to raise an exception, as shown in the `test_error_recovery_mock` test case.

## Future Work

*   **Real-board acceptance script**: Validate the flagship `OpenBCI Cyton`
    forearm-EMG path without mocks and then upgrade the support label
    accordingly.
*   **Operator runbook**: Use `docs/cyton_acceptance_runbook.md` as the single
    source of truth for the Cyton acceptance-prep workflow.
*   **Impedance Simulation**: Implement simulated impedance measurements in the mock device to test the signal quality dashboard.
