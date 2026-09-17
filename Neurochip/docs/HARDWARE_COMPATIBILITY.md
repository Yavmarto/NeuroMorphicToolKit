# Hardware Compatibility Matrix

## Verified Devices

| Device | Status | Flash Reliable | Serial Verified | Notes |
|---|---|---|---|---|
| Teensy 4.1 | Verified | Yes (1000+ cycles) | Yes | Primary embedded target. Supports LIF and AdaptiveLIF neurons. |
| SynSense Speck 2 | Simulated | N/A | Yes (via Samna) | Support for Sinabs/Samna integration in progress. |
| Intel Loihi 2 | Planned | N/A | N/A | Firmware generation template available. |

## Software Requirements

- PlatformIO Core (for compilation and flashing)
- PySerial (for port detection and communication)
- Python 3.11+

## Setup Instructions

1. **Install PlatformIO Core**:
   ```bash
   pip install platformio
   ```

2. **Linux Permissions (udev rules)**:
   To access Teensy via serial without root, install the udev rules:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/platformio/platformio-core/develop/platformio/assets/system/99-platformio-udev.rules | sudo tee /etc/udev/rules.d/99-platformio-udev.rules
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```

3. **User Groups**:
   Ensure your user is in the `dialout` group:
   ```bash
   sudo usermod -a -G dialout $USER
   ```
   (Logout and login for changes to take effect).

## Reliability Testing

The Teensy 4.1 target has been stress-tested with 1000 consecutive flash cycles using the `neurochip/scripts/stress_test_flash.py` utility.
- **Success Rate**: 100%
- **Average Flash Time**: ~12s (Real) / ~1s (Simulated)
- **Serial Reliability**: 100% detection of boot header.
