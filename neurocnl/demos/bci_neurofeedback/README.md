# BCI Neurofeedback Loop

Real-time EEG-driven neurofeedback using the OpenBCI Ganglion and a spiking neural network.

## Overview

This demo reads live EEG signals from the OpenBCI Ganglion, extracts alpha band power (8–12 Hz, associated with relaxed alertness), processes it through a neurocnl-specified SNN, and drives visual/auditory feedback in real time.

When the user is relaxed (high alpha), the feedback is calm (blue LEDs, low tone). When focused or tense (low alpha), feedback intensifies (red LEDs, higher tone). The user learns to self-regulate their brain state through this feedback loop.

## Hardware

| Component | Purpose | Estimated Cost |
|---|---|---|
| OpenBCI Ganglion | 4-channel EEG acquisition | (already owned) |
| Teensy 4.1 | SNN + feedback control (optional) | (already owned) |
| EEG electrode headband | Scalp electrode positioning | ~€15–25 |
| Neopixel LED strip (8 pixels) | Visual feedback (color gradient) | ~€8 |
| Piezo buzzer | Auditory feedback | ~€1 |
| Electrode gel (Ten20) | Improve electrode contact | ~€5 |

**Note:** This demo can run software-only (Python + screen feedback) without the Teensy. The Teensy adds physical LED/buzzer feedback.

## Signal Processing Pipeline

```
Scalp EEG (O1, O2 occipital electrodes — best for alpha)
      ↓
OpenBCI Ganglion (200 Hz sampling, BLE)
      ↓
BrainFlow SDK (Python streaming)
      ↓
Preprocessing:
  - Notch filter at 50 Hz (EU mains) or 60 Hz (US)
  - Band-pass filter: 1-40 Hz
      ↓
Feature extraction:
  - FFT on 1-second sliding window
  - Alpha band power (8-12 Hz)
  - Normalize to baseline
      ↓
Spike encoding:
  - Alpha power → firing rate (rate coding)
  - High alpha = high spike rate
      ↓
[neurocnl SNN — threshold classifier]
      ↓
Feedback output:
  - Alpha above threshold → "Relaxed" (blue, calm)
  - Alpha below threshold → "Focused" (red, alert)
```

## Electrode Placement (10-20 System)

For alpha detection, occipital electrodes are optimal:
- **O1** (left occipital) → Ganglion Channel 1
- **O2** (right occipital) → Ganglion Channel 2
- **Reference** → Earlobe (A1 or A2)
- **Ground** → Forehead (Fpz)

Alpha rhythm is strongest with eyes closed at occipital sites.

## CNL Spec

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0
```

Standard parameters — the threshold acts as the alpha power decision boundary. Adjust threshold based on individual baseline calibration.

## Software Dependencies

```bash
pip install brainflow nengo numpy scipy matplotlib
```

## Quick Start (Software-Only Mode)

```python
import time
import numpy as np
from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds
from brainflow.data_filter import DataFilter, FilterTypes, WindowOperations

# Setup
params = BrainFlowInputParams()
params.serial_port = "/dev/ttyUSB0"  # or BLE MAC address
board = BoardShim(BoardIds.GANGLION_BOARD, params)
board.prepare_session()
board.start_stream()

# Calibration (30 seconds, eyes closed)
print("Close your eyes for 30 seconds (calibration)...")
time.sleep(30)
baseline_data = board.get_board_data()
eeg_channels = BoardShim.get_eeg_channels(BoardIds.GANGLION_BOARD)
# Compute baseline alpha power...

# Real-time loop
while True:
    data = board.get_current_board_data(200)  # 1 second at 200 Hz
    for ch in eeg_channels:
        DataFilter.perform_bandpass(data[ch], 200, 8.0, 12.0, 4, FilterTypes.BUTTERWORTH, 0)
    alpha_power = np.mean(np.abs(data[eeg_channels[0]]))
    # Feed alpha_power into neurocnl pipeline as input signal...
    time.sleep(0.5)
```

## Clinical Psychology Applications

Neurofeedback is used clinically for:
- **ADHD**: Training to increase beta/SMR and decrease theta
- **Anxiety**: Training to increase alpha (relaxation)
- **Meditation**: Real-time feedback on meditative states
- **Peak performance**: Used by athletes and musicians

This demo provides a foundation that can be extended for any of these applications by changing the target frequency band and feedback mapping.

## References

- Gruzelier, J. H. (2014). "EEG-neurofeedback for optimising performance." *Neuroscience & Biobehavioral Reviews*, 44, 124-141.
- Marzbani, H., Marateb, H. R., & Mansourian, M. (2016). "Neurofeedback: A Comprehensive Review on System Design, Methodology and Clinical Applications." *Basic and Clinical Neuroscience*, 7(2), 143-158.
