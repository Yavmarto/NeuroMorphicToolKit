# 04: Recording and Replay

Reproducibility is critical for neuromorphic research. Neurosense allows you to record live streams directly to disk and replay them later as if the physical sensor was still attached.

## Sessions Screen

The `sessions_screen` manages data capture and playback.

### 1. Recording
- **Recording Controls (`recording_controls`):** Features standard Record/Stop mechanics.
- **Metadata:** When starting a recording, you can attach tags (e.g., "Walking", "Left turn") to the session.
- **Output:** Saves the stream to a `.aedat4` or optimized `.h5` file, preserving the precise timestamps required for Spiking Neural Networks.

### 2. Replay
- **Replay Controls (`replay_controls`):** Allows you to select a saved session file and hit Play.
- **Replay Status Summary (`replay_status_summary`):** Shows the current playback position, total duration, and playback speed (e.g., 1.0x real-time or faster).
- **Exporting:** Use the `export_dialog` to slice a recording or export it to a standard CSV/NumPy format for external analysis.

## Agent Workflows
- **Agent Note:** To run a repeatable `Neurobench` benchmark on a physical network, the agent must first configure a Neurosense `Replay` session as the active data source, ensuring the network receives the exact same input spike train on every run.
