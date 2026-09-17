# Gripper Reflex Training

A robotic gripper that learns to prevent objects from slipping through STDP-based reflex training.

## Overview

This demo implements a sensory-motor reflex arc on a Teensy 4.1 that controls a servo-driven gripper. A force-sensitive resistor detects grip pressure, and the spiking neural network adjusts grip strength to prevent slipping.

The key insight: this is the same reflex arc that neurocnl already models, deployed to physical hardware with a real feedback loop.

## Hardware

| Component | Purpose | Estimated Cost |
|---|---|---|
| Teensy 4.1 | SNN execution at 600 MHz | (already owned) |
| SG90 or MG996R servo | Gripper actuation | ~€5 |
| FSR 402 force sensor | Grip pressure measurement | ~€8 |
| 3D-printed gripper | Mechanical gripper jaws | ~€5 (filament) |
| Small test objects | Training targets (varying weight) | — |

## Wiring

```
Teensy 4.1
├── Pin A0 ← FSR 402 (analog read, voltage divider with 10kΩ)
├── Pin 9  → Servo signal (PWM)
├── 3.3V   → FSR + Servo power
└── GND    → Common ground
```

## Neural Architecture

```
FSR (force) → Rate encoding → [Sensory ensemble, 50 LIF neurons]
                                          ↓
                                  (synaptic weight 1.5)
                                          ↓
                               [Motor ensemble, 50 LIF neurons]
                                          ↓
                                  Servo PWM command
```

## CNL Spec

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
```

The threshold (0.8) is set slightly below the standard 1.0 to make the grip sensitive to small force changes. The time constant (0.01s) is faster than default to enable quick reflexive responses.

## Training Protocol

1. **Baseline**: Present an object, record the default grip force
2. **Slip trials**: Gradually increase object weight until the gripper fails to hold
3. **STDP adaptation**: When a slip is detected (force drops below threshold), the teaching signal strengthens the sensory→motor connection
4. **Validation**: After N trials, the network should grip heavier objects without explicit reprogramming

## Running in Simulation First

Before deploying to hardware, validate the spec in software:

```bash
# From repository root
python examples/04_full_pipeline.py demos/gripper_reflex/gripper_reflex.cnl
```

## Teensy Deployment

Once the spec validates in simulation:

1. Export network parameters (thresholds, weights, time constants) to a C header
2. Flash the Teensy with the SNN firmware that includes the exported parameters
3. Connect FSR and servo
4. Run training protocol with physical objects
