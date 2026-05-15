# 01: Device Configuration

Before any data can be processed, Neurosense must connect to a sensor. The `device_config_screen` manages this setup.

## Connection Flow

1. **Device Selector (`device_selector`):**
   - This widget lists all discovered physical sensors (e.g., USB-connected iniVation DVS cameras) and active virtual streams (e.g., a MuJoCo environment broadcasting telemetry).
   - Select the desired device to initiate a connection.
2. **Preset Selector (`preset_selector`):**
   - Many sensors require complex configuration (bias voltages, frame rates, bandwidth limits). The Preset Selector allows users to quickly load known-good configurations (e.g., "High-Speed Motion", "Indoor Lighting").
3. **Support Level Badge (`support_level_badge`):**
   - Indicates how natively the sensor is supported by NMTK (e.g., `Tier 1: Native DVS`, `Tier 3: Generic Analog`).
4. **Capability Notice (`capability_notice`):**
   - Displays hardware limitations (e.g., "This device does not support hardware timestamping, falling back to software timestamps.").

## Agent Workflows
- **Agent Note:** When setting up an automated test, an agent should query the device registry, select the mock/virtual sensor, and assert that the `SupportLevel` and `Capabilities` meet the test's requirements before opening the data stream.

---
*Next:* Read `02_Live_Signal_Monitoring.md` to learn how to verify the incoming data.
