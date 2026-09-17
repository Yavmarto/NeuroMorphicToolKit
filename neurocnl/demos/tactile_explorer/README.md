# Tactile Exploration Robot

A small wheeled robot that navigates using whisker-like tactile sensors, inspired by rat somatosensory cortex processing.

## Overview

Rats navigate in complete darkness using whiskers. Each whisker maps to a specific cortical column in the barrel cortex, creating a somatotopic map. This demo implements a simplified version: flex sensors act as whiskers, and the SNN processes contact patterns to drive differential steering.

## Hardware

| Component | Purpose | Estimated Cost |
|---|---|---|
| Teensy 4.1 | SNN execution | (already owned) |
| 2× N20 DC motors + wheels | Differential drive | ~€8 |
| L298N motor driver | Motor power control | ~€5 |
| 4× flex sensors | Whiskers (left-front, right-front, left-side, right-side) | ~€12 |
| Robot chassis | Platform (3D-print, cardboard, or kit) | ~€5 |
| 9V battery pack or USB power bank | Power supply | ~€3 |
| 4× 10kΩ resistors | Voltage dividers for flex sensors | ~€1 |

**Total: ~€30–35**

## Wiring

```
Teensy 4.1
├── Pin A0 ← Flex sensor: Left-front whisker
├── Pin A1 ← Flex sensor: Right-front whisker
├── Pin A2 ← Flex sensor: Left-side whisker
├── Pin A3 ← Flex sensor: Right-side whisker
├── Pin 3  → L298N IN1 (left motor forward)
├── Pin 4  → L298N IN2 (left motor reverse)
├── Pin 5  → L298N IN3 (right motor forward)
├── Pin 6  → L298N IN4 (right motor reverse)
├── Pin 7  → L298N ENA (left motor PWM speed)
├── Pin 8  → L298N ENB (right motor PWM speed)
├── Vin    → L298N 5V (logic power)
└── GND    → Common ground
```

## Neural Architecture

```
Whisker sensors (4 channels)
          ↓
Delta modulation encoding (spike on bend change)
          ↓
[Sensory population — 4 groups, somatotopic mapping]
  ├── Left-front sensory group
  ├── Right-front sensory group
  ├── Left-side sensory group
  └── Right-side sensory group
          ↓
[Motor population — 2 groups]
  ├── Left motor group  ← Contralateral: driven by RIGHT whiskers
  └── Right motor group ← Contralateral: driven by LEFT whiskers
          ↓
Differential motor drive
  - Right whisker contact → Left motor speeds up → Turn left (away from right obstacle)
  - Left whisker contact  → Right motor speeds up → Turn right (away from left obstacle)
  - Front whiskers contact → Both motors reverse → Back up
```

## CNL Spec

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.4
The sensory neuron MUST NOT fire DURING the refractory period of 0.001 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.005 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 2.0
```

Low threshold (0.4) for high sensitivity to whisker bends. Very fast time constant (5 ms) for rapid obstacle avoidance. High synaptic weight (2.0) for strong motor responses — the robot needs to react quickly.

## Behavior

1. **Open space**: No whisker contact → both motors run at base speed → drive forward
2. **Right obstacle**: Right whiskers bend → right sensory fires → left motor speeds up → turn left
3. **Left obstacle**: Left whiskers bend → left sensory fires → right motor speeds up → turn right
4. **Dead end**: Front whiskers bend → both sensory groups fire → both motors reverse → back up, then turn
5. **Narrow corridor**: Alternating left/right contacts → oscillating correction → follows the corridor

## Biology Background

| Rat Barrel Cortex | This Demo |
|---|---|
| Each whisker maps to one cortical barrel | Each flex sensor maps to one sensory group |
| Contralateral processing | Right whisker → left motor (and vice versa) |
| Lateral inhibition sharpens spatial contrast | Inhibitory connections between sensory groups |
| Whisking frequency ~8 Hz | Sampling at analogous rate |

## Extensions

- **Map building**: Log whisker contact patterns to build a spatial map of the environment
- **STDP adaptation**: Learn optimal turning angles from experience
- **Multiple sensor modalities**: Add ultrasonic sensor for long-range detection, whiskers for close-range
