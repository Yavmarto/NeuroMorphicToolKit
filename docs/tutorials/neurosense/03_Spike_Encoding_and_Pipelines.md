# 03: Spike Encoding and Pipelines

Neuromorphic architectures require discrete spikes as input. While DVS cameras produce spikes natively, many sensors (like microphones or analog IMUs) produce continuous floating-point signals. The `filter_pipeline_screen` handles this translation.

## Filter Pipelines

The **Pipeline Connector (`pipeline_connector`)** allows you to chain signal processing nodes together.
1. **Raw Input Node:** The source from the physical device.
2. **Filter Nodes:** Intermediate steps (e.g., Low-pass filter, Background Activity Filter for DVS).
3. **Encoding Node:** The final step that translates the data into the toolkit's standard Spike format.

## Spike Encoding Panel

The `spike_encoding_panel` configures the mathematics of the final encoding node.
- **Delta Modulation:** Emits a spike when the analog signal changes by a specific threshold `Δ`.
- **Rate Coding:** Converts analog amplitude into a proportional firing frequency.
- **Latency Coding:** Converts stronger signals into earlier spike times.

### Usage
- If you are feeding audio data into a CNL network, you might set up an Audio Spectrogram filter followed by a Rate Coder.
- Once the pipeline is established, the output can be routed natively into a running `CNLStudio` simulation or recorded to disk.

---
*Next:* Read `04_Recording_and_Replay.md` to learn how to capture data sessions.
