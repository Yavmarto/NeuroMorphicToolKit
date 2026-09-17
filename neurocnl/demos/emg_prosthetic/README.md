# EMG-Controlled Prosthetic Prototype

Use forearm EMG signals from the OpenBCI Ganglion to control a servo-driven prosthetic finger through a spiking neural network.

## Overview

This demo bridges biological neural signals and neuromorphic computing. EMG (electromyography) signals from the forearm are captured by the Ganglion board, spike-encoded, processed by a neurocnl-specified SNN, and translated into servo commands that flex a prosthetic finger.

## Hardware

| Component | Purpose | Estimated Cost |
|---|---|---|
| OpenBCI Ganglion | 4-channel EMG acquisition | (already owned) |
| Teensy 4.1 | SNN execution + servo control | (already owned) |
| 2× SG90 servo motors | Finger flexion/extension | ~€6 |
| EMG electrode pads | Forearm muscle sensing | ~€10 (reusable) |
| 3D-printed finger | Mechanical actuator | ~€5 (filament) |
| Electrode gel | Signal quality improvement | ~€5 |

Open-source prosthetic finger designs: [Open Bionics](https://openbionicslabs.com/), [InMoov](https://inmoov.fr/)

## Signal Flow

```
Forearm muscles
      ↓
EMG electrodes (on flexor digitorum superficialis)
      ↓
OpenBCI Ganglion (4 channels, 200 Hz, BLE)
      ↓
BrainFlow SDK (Python, streaming)
      ↓
Band-pass filter (20-450 Hz, EMG band)
      ↓
Rectification + envelope extraction
      ↓
Rate-based spike encoding
      ↓
[neurocnl SNN — sensory→motor reflex arc]
      ↓
Serial command to Teensy
      ↓
Servo PWM → Finger flexion
```

## Electrode Placement

Place electrodes on the forearm:
- **Channel 1**: Flexor digitorum superficialis (finger flexion)
- **Channel 2**: Extensor digitorum (finger extension)
- **Reference**: Bony prominence (wrist or elbow)
- **Ground**: Bony prominence (opposite side)

## CNL Spec

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.6
The sensory neuron MUST NOT fire DURING the refractory period of 0.001 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.2
```

Lower threshold (0.6) for EMG sensitivity. Shorter refractory period (1 ms) to track rapid muscle contractions. Fast time constant (10 ms) matches EMG signal dynamics.

## Software Dependencies

```bash
pip install brainflow nengo numpy scipy
```

## Quick Start

```python
from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds

# Connect to Ganglion
params = BrainFlowInputParams()
params.serial_port = "/dev/ttyUSB0"  # or BLE address
board = BoardShim(BoardIds.GANGLION_BOARD, params)
board.prepare_session()
board.start_stream()

# Read EMG data
data = board.get_board_data()
emg_channels = BoardShim.get_emg_channels(BoardIds.GANGLION_BOARD)
```

## Netherlands Relevance

The Netherlands has significant activity in rehabilitation robotics and medical devices:
- **TU Delft** — BioMechanical Engineering, prosthetics research
- **University of Twente** — Biomedical Signals and Systems group
- **Hankamp Rehab** — Rehabilitation robotics (Enschede)
- **Össur** — Prosthetics (European operations)

This demo directly maps to real industry work in the medical devices sector.
