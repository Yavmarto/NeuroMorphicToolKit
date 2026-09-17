# Classical Conditioning (Pavlovian Learning)

A spiking neural network learns to associate a neutral stimulus (tone) with a reflexive response, implementing Pavlov's conditioning experiment on neuromorphic hardware.

## Overview

Before conditioning, only a light flash triggers the servo motor. After repeated pairing of tone + flash, the tone alone triggers the response. This is classical conditioning — implemented in a spiking neural network on a Teensy 4.1 with STDP as the learning mechanism.

## Hardware

| Component | Purpose | Estimated Cost |
|---|---|---|
| Teensy 4.1 | SNN execution | (already owned) |
| Piezo buzzer | Conditioned stimulus (CS, tone) | ~€1 |
| LED (bright, white) | Unconditioned stimulus (US, flash) | ~€1 |
| LDR (light-dependent resistor) | "Eye" sensor to detect flash | ~€1 |
| SG90 servo motor | Conditioned/unconditioned response | ~€3 |
| Push button × 2 | Manual CS/US trigger | ~€1 |

**Total: ~€7–8**

## Wiring

```
Teensy 4.1
├── Pin A0 ← LDR (analog, voltage divider with 10kΩ)
├── Pin A1 ← Microphone/buzzer feedback (optional)
├── Pin 5  → Piezo buzzer (CS delivery)
├── Pin 6  → LED (US delivery)
├── Pin 9  → Servo motor (CR/UR output)
├── Pin 11 ← Button 1: Deliver CS (tone)
├── Pin 12 ← Button 2: Deliver US (flash)
└── GND    → Common ground
```

## Neural Architecture

```
                    [Auditory sensory]  ←  Buzzer tone
                           ↓
                    (initially weak, w=0.1)
                           ↓
[Visual sensory]  → [Motor neuron]  → Servo motor
       ↑                   ↑
  LED flash          (strong, w=1.5)

During pairing: STDP strengthens Auditory→Motor connection
because auditory pre-synaptic spikes consistently precede
motor post-synaptic spikes (caused by visual input).
```

## CNL Spec

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.7
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.5
```

This spec defines the base network. The initial auditory→motor weight starts low (0.5) and grows through STDP during paired presentation.

## Training Protocol

### Phase 1 — Baseline (5 trials)
- Present tone alone → Record: no servo response
- Present flash alone → Record: servo moves (unconditioned response)

### Phase 2 — Conditioning (20-30 trials)
- Present tone, then flash 50 ms later (forward pairing)
- STDP window: pre-before-post = potentiation
- The auditory→motor weight increases each trial

### Phase 3 — Test (5 trials)
- Present tone alone → Servo should now move (conditioned response)
- Record response magnitude and compare to baseline

### Phase 4 — Extinction (optional, 10+ trials)
- Present tone alone repeatedly without flash
- Response should gradually decrease (extinction)

## Psychology Background

| Term | In This Demo |
|---|---|
| Unconditioned Stimulus (US) | LED flash |
| Unconditioned Response (UR) | Servo movement to flash |
| Conditioned Stimulus (CS) | Buzzer tone |
| Conditioned Response (CR) | Servo movement to tone (after learning) |
| Acquisition | STDP weight increase during pairing |
| Extinction | STDP weight decrease without reinforcement |

**Reference:** Pavlov, I. P. (1927). *Conditioned Reflexes*. Oxford University Press.

## Why This Demo Stands Out

This is a uniquely compelling portfolio piece because:
1. It implements a foundational psychology experiment using neuromorphic principles
2. The learning (STDP) is biologically plausible — not backpropagation
3. It runs on real hardware with observable physical behavior
4. It bridges the user's psychology background with neuromorphic engineering
5. The phases (acquisition → extinction) directly map to textbook psychology
