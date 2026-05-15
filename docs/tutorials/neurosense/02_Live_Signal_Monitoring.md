# 02: Live Signal Monitoring

Once a device is connected, the `signal_monitor_screen` provides real-time observability into the data stream.

## Visualizing the Stream

### Live Signal Viewer
The `live_signal_viewer` widget adapts its display based on the data type:
- **Event-Based Vision (DVS):** Displays a 2D scatter plot or accumulation frame of ON/OFF polarity spikes.
- **Analog/Audio:** Displays a continuous rolling waveform.
- **1D Spike Trains:** Displays a raster plot of spike times across multiple channels.

### Signal Quality Bar
The `signal_quality_bar` acts as a health indicator for the connection.
- **Metrics Tracked:**
  - Bandwidth (MB/s)
  - Event Rate (Spikes per second)
  - Dropped Packets
- **Usage:** If the event rate is too high, the buffer will overflow. Users must either adjust the sensor biases (in `device_config_screen`) or apply aggressive filtering.

## Execution Flow for Agents
- **Agent Note:** Agents cannot visually interpret the `live_signal_viewer`. Instead, they should monitor the telemetry stream bound to the `signal_quality_bar`. If `dropped_packets` begins rising, the agent must programmatically adjust the bandwidth caps or notify the user of an overwhelmed system.

---
*Next:* Read `03_Spike_Encoding_and_Pipelines.md` to learn how to process analog data.
