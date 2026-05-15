# 00: Neurosense Overview

Neurosense is the module responsible for bridging physical sensors (like DVS cameras, audio microphones, or tactile arrays) into the Neuromorphic Toolkit. It handles data streaming, filtering, and spike encoding.

## Core Layout

The Neurosense UI is organized into four main functional screens:

1. **Device Config (`device_config_screen`):**
   - The entry point for discovering and connecting to physical or virtual sensor hardware.
2. **Signal Monitor (`signal_monitor_screen`):**
   - The live dashboard for viewing the incoming raw and encoded data streams in real-time.
3. **Filter Pipeline (`filter_pipeline_screen`):**
   - The routing matrix where raw analog signals are cleaned and encoded into discrete spikes.
4. **Sessions (`sessions_screen`):**
   - The data management interface for recording live streams and replaying captured datasets.

## Target Audience
- **Humans:** Use Neurosense to calibrate hardware sensors, visually verify signal quality, and record datasets for later use in `Neurobench` or `CNLStudio`.
- **AI Agents:** Agents interact with Neurosense to automate data collection or to programmatically establish the sensory input streams required by a deployed robotic model.

---
*Next:* Read `01_Device_Configuration.md` to learn how to connect sensor hardware.
