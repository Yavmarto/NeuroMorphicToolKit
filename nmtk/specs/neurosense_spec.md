# NeuroSense — Biosignal Acquisition & Spike Encoding Toolkit
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroSense is a unified tool for acquiring, processing, spike-encoding, and piping biosignals (EMG, EEG, EOG, ECG) into the Neuro-space pipeline. It targets embedded engineers and chip designers who need real biological input signals for their neuromorphic systems but have no experience with biosignal acquisition, electrode placement, filtering, or neural encoding.

---

## Repository

`neuro-space/NeuroSense` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package — for spike encoding utilities and pipeline integration
- `brainflow` Python package — for device communication
- `neuro-flutter-ui` shared Flutter design system package

---

## User Stories

### Device Management

**NSe-DM1 · Auto-detect connected devices**
As a chip designer who has never used biosignal hardware,
I want the app to auto-detect my connected OpenBCI Ganglion,
so that I don't need to know serial port names or device protocols.

Acceptance criteria:
- On startup and on "Refresh", scan for supported devices via BrainFlow discovery
- Show detected devices with: name, type (Ganglion/Cyton/Muse/BITalino), serial port, connection status
- Supported devices: OpenBCI Ganglion, OpenBCI Cyton, Muse 2/S, BITalino, generic serial ADC
- "Connect" button establishes the connection; "Disconnect" cleanly releases it
- Connection errors show human-readable messages (e.g., "Ganglion not found — is Bluetooth enabled?")

**NSe-DM2 · Guided electrode setup**
As a non-specialist setting up EMG electrodes for the first time,
I want step-by-step placement instructions with diagrams,
so that I get usable signals without studying anatomy.

Acceptance criteria:
- After connecting a device and selecting a signal type (EMG/EEG/EOG), show a setup wizard
- Wizard includes: electrode placement diagram (body diagram with marked positions), step-by-step text instructions, impedance check
- Impedance check shows per-channel values with green/yellow/red indicators
- "Verify" button runs a quick signal quality check and confirms the setup is working
- Presets available: "Forearm EMG (2-channel)", "Occipital EEG (O1/O2)", "Horizontal EOG"

### Signal Acquisition & Viewing

**NSe-SA1 · Live multi-channel signal viewer**
As an engineer verifying signal quality,
I want to see real-time waveforms for all channels with configurable filters,
so that I can confirm I'm getting clean data before feeding it into my SNN.

Acceptance criteria:
- Scrolling waveform display for up to 8 channels simultaneously
- Configurable per-channel: bandpass filter (cutoff frequencies), notch filter (50 Hz or 60 Hz), gain
- Each signal type has a sensible default filter preset (e.g., EMG: 20-450 Hz bandpass + 50 Hz notch)
- Time axis configurable: 1s, 5s, 10s, 30s window
- Amplitude axis auto-scales or manual range
- Pause/resume without losing data
- Latency from acquisition to display < 50ms

**NSe-SA2 · Signal quality dashboard**
As a non-specialist troubleshooting poor signals,
I want per-channel quality indicators that tell me what's wrong,
so that I can fix electrode issues without signal processing expertise.

Acceptance criteria:
- Per-channel indicators: SNR (dB), noise floor (µV RMS), impedance (kΩ), power line interference level
- Color coding: green (good), yellow (marginal), red (unusable)
- Actionable suggestions for red channels: "High noise on Ch2 — check electrode contact" or "60 Hz interference detected — enable notch filter"
- Quality dashboard updates in real time during acquisition

### Spike Encoding

**NSe-SE1 · Real-time spike encoding with visual comparison**
As an engineer who understands digital signals but not neural encoding,
I want to see my analog biosignal converted to spikes in real time with three encoding methods side by side,
so that I can understand and choose the right encoding for my application.

Acceptance criteria:
- Three-panel view: raw filtered signal → rate-encoded spikes → temporal-encoded spikes → delta-encoded spikes
- Each panel shows the spike train as a raster and the analog signal as an overlay
- Encoding parameters are adjustable per method (e.g., rate encoding: max rate Hz; delta: threshold µV)
- Tooltip on each encoding method: one-paragraph explanation of when to use it
- Spike rate counter per channel per encoding method

**NSe-SE2 · Application presets for common use cases**
As an engineer who doesn't want to manually configure encoding,
I want to select a preset like "EMG for prosthetic control" and get a complete acquisition + encoding pipeline,
so that I can start getting spike-encoded data in under a minute.

Acceptance criteria:
- Presets available:
  - "EMG for prosthetic control" — 20-450 Hz bandpass, envelope extraction, rate encoding at 200 Hz max
  - "EEG alpha band for BCI" — 8-13 Hz bandpass, PSD, threshold encoding
  - "EOG for gaze tracking" — DC-coupled, delta modulation at 5 µV threshold
  - "Tactile sensor array" — multi-channel delta encoding, 10 µV threshold
- Selecting a preset configures: device channel mapping, filters, encoding method, encoding parameters
- Presets are editable — user can modify and save as custom presets
- Preset metadata includes: description, intended application, recommended electrode placement

### Recording & Playback

**NSe-R1 · Record sessions with event annotations**
As an engineer building a training dataset for my SNN,
I want to record biosignal sessions with timestamped event markers,
so that I can replay specific segments into my pipeline.

Acceptance criteria:
- "Record" button starts capturing raw + encoded data to disk
- Event marker button (or keyboard shortcut) inserts a timestamped annotation (e.g., "subject flexed wrist")
- Recording saves: raw analog data, filtered data, spike-encoded data, event markers, device config, filter settings
- File formats: HDF5 (primary, structured), CSV (interop)
- Recording metadata: timestamp, duration, device, preset, subject ID (optional)
- Maximum recording duration: limited only by disk space

**NSe-R2 · Replay recorded sessions into the pipeline**
As an engineer doing offline SNN development,
I want to replay a recorded session as if it were live data,
so that I can iterate on my SNN without needing a live subject every time.

Acceptance criteria:
- Load a saved HDF5 session → replay button plays it back at real-time speed (or configurable 0.5x–10x)
- Replay outputs appear in the same live viewer as real acquisition
- Replay can be piped directly to `/api/simulate` as spike-encoded input
- Seek bar allows jumping to specific timestamps or event markers
- Multiple sessions can be concatenated for longer replay sequences

### Pipeline Integration

**NSe-PI1 · Direct pipeline integration with neurocnl**
As an engineer testing my SNN with real biosignal input,
I want to route live or replayed spike-encoded data directly into the neurocnl simulation pipeline,
so that I can see my network respond to real biological signals.

Acceptance criteria:
- "Connect to Pipeline" button establishes a WebSocket connection to the neurocnl backend
- Spike-encoded data streams as input to whichever SNN is currently loaded in the Studio or NeuroSim
- Simulation results (motor output, spike raster) are displayed alongside the input signal
- Latency from biosignal acquisition to simulation output < 100ms for real-time applications
- Works with both live acquisition and session replay

**NSe-PI2 · Export spike-encoded data for offline use**
As an engineer sharing data with colleagues,
I want to export spike-encoded data in formats compatible with other tools,
so that it can be used independently of NeuroSense.

Acceptance criteria:
- Export formats: HDF5 (spike times + channel IDs), CSV (timestamp, channel, spike), Nengo input format (Python pickle), AEDAT (for compatibility with neuromorphic datasets)
- Export can be full session or a time-windowed segment
- Export includes metadata: encoding method, parameters, source signal type, sampling rate

---

## Backend Spec

### API Endpoints

All NeuroSense-specific endpoints live under `/api/neurosense/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurosense/devices` | Scan and list available biosignal devices |
| POST | `/api/neurosense/devices/{id}/connect` | Connect to a specific device |
| POST | `/api/neurosense/devices/{id}/disconnect` | Disconnect from a device |
| GET | `/api/neurosense/devices/{id}/impedance` | Run impedance check |
| GET | `/api/neurosense/presets` | List available application presets |
| GET | `/api/neurosense/presets/{id}` | Get a specific preset configuration |
| POST | `/api/neurosense/presets` | Save a custom preset |
| WS | `/api/neurosense/stream/raw` | WebSocket: stream raw analog data from device |
| WS | `/api/neurosense/stream/filtered` | WebSocket: stream filtered analog data |
| WS | `/api/neurosense/stream/spikes` | WebSocket: stream spike-encoded data |
| POST | `/api/neurosense/encode` | Encode a batch of analog data to spikes (offline) |
| POST | `/api/neurosense/recording/start` | Start recording a session |
| POST | `/api/neurosense/recording/stop` | Stop recording, return session metadata |
| POST | `/api/neurosense/recording/marker` | Insert an event marker into the active recording |
| GET | `/api/neurosense/sessions` | List recorded sessions |
| GET | `/api/neurosense/sessions/{id}` | Get session metadata |
| GET | `/api/neurosense/sessions/{id}/download` | Download session data (HDF5) |
| POST | `/api/neurosense/sessions/{id}/replay` | Start replaying a session |
| POST | `/api/neurosense/sessions/{id}/replay/stop` | Stop replay |
| GET | `/api/neurosense/quality` | Get current signal quality metrics for connected device |
| POST | `/api/neurosense/export` | Export spike-encoded data in specified format |

### Data Models

**DeviceInfo**
```python
class DeviceInfo(BaseModel):
    id: str                              # Unique device identifier
    name: str                            # e.g., "OpenBCI Ganglion"
    type: str                            # e.g., "ganglion", "cyton", "muse"
    serial_port: str | None              # e.g., "/dev/ttyACM0"
    channels: int                        # Number of analog channels
    sampling_rate_hz: int                # Native sampling rate
    connected: bool
    battery_pct: int | None              # If available
```

**AcquisitionPreset**
```python
class AcquisitionPreset(BaseModel):
    id: str                              # e.g., "emg_prosthetic"
    name: str                            # e.g., "EMG for Prosthetic Control"
    signal_type: str                     # "emg", "eeg", "eog", "ecg", "tactile"
    description: str
    electrode_placement: str             # Markdown with placement instructions
    electrode_diagram: str               # Path to diagram image
    channel_mapping: dict[int, str]      # e.g., {0: "flexor", 1: "extensor"}
    filter_config: FilterConfig
    encoding_config: EncodingConfig
    recommended_device: str              # e.g., "ganglion"
```

**FilterConfig**
```python
class FilterConfig(BaseModel):
    bandpass_low_hz: float | None        # e.g., 20.0
    bandpass_high_hz: float | None       # e.g., 450.0
    notch_hz: float | None              # e.g., 50.0
    artifact_rejection: bool = False
```

**EncodingConfig**
```python
class EncodingConfig(BaseModel):
    method: Literal["rate", "temporal", "delta"]
    rate_max_hz: float | None = None     # For rate encoding
    temporal_phase_bins: int | None = None  # For temporal encoding
    delta_threshold: float | None = None    # For delta modulation (µV)
```

**SignalQuality**
```python
class SignalQuality(BaseModel):
    channels: list[ChannelQuality]

class ChannelQuality(BaseModel):
    channel: int
    label: str                           # e.g., "flexor"
    snr_db: float
    noise_floor_uv_rms: float
    impedance_kohm: float | None
    power_line_interference_db: float
    status: Literal["good", "marginal", "unusable"]
    suggestion: str | None               # e.g., "Check electrode contact"
```

**RecordingSession**
```python
class RecordingSession(BaseModel):
    id: str
    timestamp: str                       # ISO 8601
    duration_seconds: float
    device_type: str
    preset_id: str
    channels: int
    sampling_rate_hz: int
    encoding_config: EncodingConfig
    event_markers: list[EventMarker]
    file_path: str
    file_size_bytes: int
    subject_id: str | None

class EventMarker(BaseModel):
    timestamp_seconds: float             # Offset from recording start
    label: str                           # e.g., "wrist_flexion"
```

### Service Architecture

```
NeuroSense Frontend (Flutter)
       |
       | HTTP + WebSocket
       |
NeuroSense Backend (FastAPI)
       |
       ├── brainflow (device communication, raw data acquisition)
       ├── neurocnl spike_encoding module (rate, temporal, delta encoding)
       ├── scipy.signal (filtering: bandpass, notch, artifact rejection)
       └── h5py (HDF5 session storage)
```

The backend manages device connections as server-side state. WebSocket streams push data to the frontend at the device's native sampling rate. Spike encoding runs in the backend to minimize frontend processing load.

### Streaming Architecture

```
Device (BrainFlow)
    │
    ▼
Raw Ring Buffer (numpy array, last 30s)
    │
    ├── WebSocket /stream/raw ──────────► Frontend raw viewer
    │
    ▼
Filter Pipeline (scipy.signal)
    │
    ├── WebSocket /stream/filtered ─────► Frontend filtered viewer
    │
    ▼
Spike Encoder (neurocnl spike_encoding)
    │
    ├── WebSocket /stream/spikes ───────► Frontend spike viewer
    │
    ├── Recording (HDF5 writer) ────────► Disk
    │
    └── Pipeline bridge (HTTP POST) ────► neurocnl /api/simulate
```

Each WebSocket frame contains a batch of samples (e.g., 50ms worth) to balance latency and efficiency.

---

## Frontend Spec

### Screen Layout

```
┌──────────────────────────────────────────────────────┐
│ Toolbar: [Device: Ganglion ▾] [Preset: EMG ▾] [Rec] │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌─ Signal Viewer ─────────────────────────────────┐ │
│  │ Ch1 (flexor):  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~     │ │
│  │ Ch2 (extensor): ~~~~~~~~~~~~~~~~~~~~~~~~~~~~    │ │
│  │ Ch3 (reference): ~~~~~~~~~~~~~~~~~~~~~~~~~~~~   │ │
│  │ Ch4 (ground):    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~   │ │
│  │                                    [5s window]  │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Spike Encoding ────────────────────────────────┐ │
│  │ Rate:     |.|.||.|...|.||.|.|                   │ │
│  │ Temporal: ||...|.|.||....|.||                    │ │
│  │ Delta:    |...||....|..||...|                    │ │
│  │                                                  │ │
│  │ [Encoding params]  [Select: Rate ▾]  [→ Pipeline]│ │
│  └──────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Signal Quality ────────────────────────────────┐ │
│  │ Ch1: SNR 22dB ✅  Ch2: SNR 18dB ✅             │ │
│  │ Ch3: SNR 8dB  ⚠️   Ch4: SNR 31dB ✅             │ │
│  └──────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────┤
│ Sessions: [2026-03-15 14:30 EMG] [2026-03-14 09:15] │
└──────────────────────────────────────────────────────┘
```

### Key Widgets

| Widget | Purpose |
|---|---|
| `DeviceSelector` | Dropdown with auto-detected devices + connect/disconnect |
| `PresetSelector` | Dropdown with application presets + custom preset editor |
| `ElectrodePlacementWizard` | Step-by-step setup with diagrams and impedance check |
| `LiveSignalViewer` | Multi-channel scrolling waveform display |
| `SpikeEncodingPanel` | Three-method comparison with parameter controls |
| `SignalQualityBar` | Per-channel quality indicators with suggestions |
| `RecordingControls` | Record/stop/marker buttons with duration timer |
| `SessionBrowser` | List of recorded sessions with replay controls |
| `ReplayControls` | Play/pause/seek bar with speed control (0.5x-10x) |
| `PipelineConnector` | Connect/disconnect to neurocnl simulation pipeline |
| `ExportDialog` | Format selection and segment configuration |

### Providers (Riverpod)

| Provider | State |
|---|---|
| `devicesProvider` | Available devices + connection state |
| `activeDeviceProvider` | Currently connected device |
| `presetProvider` | Active acquisition preset |
| `rawStreamProvider` | WebSocket stream of raw analog data |
| `filteredStreamProvider` | WebSocket stream of filtered data |
| `spikeStreamProvider` | WebSocket stream of spike-encoded data |
| `signalQualityProvider` | Real-time signal quality metrics |
| `recordingStateProvider` | Recording active/stopped + duration + markers |
| `sessionsProvider` | List of recorded sessions |
| `replayStateProvider` | Replay active/paused + position + speed |
| `pipelineConnectionProvider` | Pipeline connection state |

---

## File Structure

```
NeuroSense/
├── neurosense/                      # Python backend
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/
│   │   │   ├── devices.py
│   │   │   ├── presets.py
│   │   │   ├── stream.py            # WebSocket endpoints
│   │   │   ├── encoding.py
│   │   │   ├── recording.py
│   │   │   ├── sessions.py
│   │   │   ├── quality.py
│   │   │   └── export.py
│   │   ├── schemas/
│   │   │   ├── devices.py
│   │   │   ├── presets.py
│   │   │   ├── encoding.py
│   │   │   ├── quality.py
│   │   │   └── sessions.py
│   │   └── services/
│   │       ├── device_manager.py    # BrainFlow device lifecycle
│   │       ├── filter_pipeline.py   # scipy.signal filter chain
│   │       ├── spike_encoder.py     # Wraps neurocnl spike_encoding
│   │       ├── recording_service.py # HDF5 writer with event markers
│   │       ├── replay_service.py    # Session replay at configurable speed
│   │       ├── quality_analyzer.py  # SNR, impedance, noise analysis
│   │       └── pipeline_bridge.py   # Route spikes to neurocnl /api/simulate
│   ├── presets/                     # JSON acquisition presets
│   │   ├── emg_prosthetic.json
│   │   ├── eeg_alpha_bci.json
│   │   ├── eog_gaze.json
│   │   └── tactile_array.json
│   ├── electrode_diagrams/          # PNG/SVG placement diagrams
│   │   ├── forearm_emg.svg
│   │   ├── occipital_eeg.svg
│   │   └── horizontal_eog.svg
│   ├── pyproject.toml
│   └── tests/
├── frontend/                        # Flutter frontend
│   ├── lib/
│   │   ├── app.dart
│   │   ├── screens/
│   │   │   ├── acquisition_screen.dart
│   │   │   ├── setup_wizard_screen.dart
│   │   │   └── session_browser_screen.dart
│   │   ├── widgets/
│   │   │   ├── device_selector.dart
│   │   │   ├── preset_selector.dart
│   │   │   ├── live_signal_viewer.dart
│   │   │   ├── spike_encoding_panel.dart
│   │   │   ├── signal_quality_bar.dart
│   │   │   ├── recording_controls.dart
│   │   │   ├── replay_controls.dart
│   │   │   ├── pipeline_connector.dart
│   │   │   └── export_dialog.dart
│   │   ├── providers/
│   │   ├── models/
│   │   └── services/
│   │       └── api_client.dart
│   ├── pubspec.yaml
│   └── test/
├── docker-compose.yml
├── Dockerfile
└── README.md
```
