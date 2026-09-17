# Developer Guide: Adding a New Device Driver

NeuroSense is designed to be easily extensible to support new biosignal hardware via the `brainflow` library. This guide will show you how to add a new device driver to the toolkit.

## Overview

The `DeviceManager` service handles device discovery, connection lifecycle, and data acquisition. To support a new device, you need to update `neurosense/app/services/device_manager.py`.

## Step 1: Update Discovery Scan

Add your new device to the `board_configs` list in the `scan_devices` method of `DeviceManager`.

```python
# neurosense/app/services/device_manager.py

async def scan_devices(self) -> list[DeviceInfo]:
    # ...
    board_configs = [
        # ... existing devices ...
        {
            "board_id": BoardIds.YOUR_NEW_BOARD, # From brainflow.board_shim
            "name": "Your New Device Name",
            "type": "new_device_type",
            "channels": 8,
            "sampling_rate": 500,
        },
    ]
    # ...
```

## Step 2: Map Board Type to ID

In the `connect` method, update the `board_type_map` to include your new device's type and its corresponding `BoardIds` value.

```python
# neurosense/app/services/device_manager.py

async def connect(self, device_id: str) -> DeviceInfo:
    # ...
    board_type_map = {
        "synthetic": -1,
        "ganglion": 1,
        "cyton": 0,
        "muse2": BoardIds.MUSE_2_BOARD,
        "muses": BoardIds.MUSE_S_BOARD,
        "muse_bled": BoardIds.MUSE_2_BLED_BOARD,
        "pieeg": BoardIds.PIEEG_BOARD,
        "new_device_type": BoardIds.YOUR_NEW_BOARD,
    }
    # ...
```

## Step 3: Handle Device-Specific Parameters (Optional)

If your device requires special initialization parameters (e.g., serial port, IP address, or extra settings), update the `BrainFlowInputParams` configuration in the `connect` method.

```python
# neurosense/app/services/device_manager.py

async def connect(self, device_id: str) -> DeviceInfo:
    # ...
    params = BrainFlowInputParams()
    if device.type == "new_device_type":
        params.serial_port = device.serial_port
        # Add other device-specific params here
    # ...
```

## Step 4: Verify Integration

1. Restart the NeuroSense backend.
2. Run a scan from the frontend to ensure your device is discovered.
3. Test connection and data acquisition.
4. Run the test suite: `PYTHONPATH=neurosense pytest neurosense/tests/`

## Reference Implementations

- Muse 2 / Muse S: env-gated discovery via `NEUROSENSE_MUSE_MODEL`, native BLE
  board IDs 38/39 with BLED fallback 22, acceptance script
  `python -m neurosense.tests.validate_muse_hardware --mock`
- PiEEG: ADS1299 profile shared with Cyton (8 ch @ 250 Hz), streaming-board
  relay via `NEUROSENSE_PIEEG_STREAM_HOST`, acceptance script
  `python -m neurosense.tests.validate_pieeg_hardware --mock`

## Resources

- [BrainFlow Documentation](https://brainflow.readthedocs.io/)
- [NeuroSense Contracts](neurosense/contracts/)
