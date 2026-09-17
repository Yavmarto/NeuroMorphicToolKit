# Habituation and Sensitization

Demonstrate two fundamental forms of non-associative learning on a Teensy 4.1 using a spiking neural network.

## Overview

Habituation (decreased response to repeated stimuli) and sensitization (increased response to novel/intense stimuli) are the simplest forms of learning, studied extensively by Eric Kandel in *Aplysia* sea slugs — work that earned the 2000 Nobel Prize in Physiology or Medicine.

This demo implements both mechanisms in a spiking network: a distance sensor triggers a buzzer response that fades with repetition (habituation), and a button press causes the response to return stronger than baseline (sensitization).

## Hardware

| Component | Purpose | Estimated Cost |
|---|---|---|
| Teensy 4.1 | SNN execution | (already owned) |
| HC-SR04 ultrasonic sensor | Stimulus detection (hand wave) | ~€3 |
| Piezo buzzer | Motor response (auditory output) | ~€1 |
| LED + 220Ω resistor | Motor response (visual output) | ~€1 |
| Tactile push button | Novel stimulus injection | ~€0.50 |

**Total: ~€5–6**

This is the cheapest demo in the collection and the best starting point.

## Wiring

```
Teensy 4.1
├── Pin 2  → HC-SR04 Trigger
├── Pin 3  ← HC-SR04 Echo
├── Pin 9  → Piezo buzzer
├── Pin 10 → LED (through 220Ω resistor)
├── Pin 11 ← Push button (with 10kΩ pull-down)
├── 3.3V   → Sensor power
└── GND    → Common ground
```

## Neural Architecture

```
Ultrasonic sensor → Rate encoding → [Sensory population]
                                           ↓
                                    (depressing synapse)
                                           ↓
                                   [Interneuron population]
                                           ↓
                                    [Motor population]
                                           ↓
                                    Buzzer + LED

Push button → [Sensitization input] → Facilitates interneuron
```

**Habituation mechanism:** The sensory→interneuron synapse uses short-term synaptic depression. With each repeated activation, less neurotransmitter is available, reducing the postsynaptic response.

**Sensitization mechanism:** The button activates a modulatory pathway that temporarily increases synaptic efficacy, restoring (and overshooting) the response.

## CNL Spec

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5
The sensory neuron MUST NOT fire DURING the refractory period of 0.003 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.05 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.8
```

Lower threshold (0.5) ensures sensitivity to proximity sensor input. Slower time constant (50 ms) produces gradual responses suitable for observing habituation. Moderate weight (0.8) leaves room for depression and facilitation.

## Expected Behavior

1. **Trial 1-3**: Hand wave near sensor → strong buzzer/LED response
2. **Trial 4-7**: Same hand wave → progressively weaker response (habituation)
3. **Trial 8-10**: Barely any response (fully habituated)
4. **Press button**: Novel stimulus injection
5. **Trial 11**: Hand wave → response is now STRONGER than trial 1 (sensitization)
6. **Trial 12+**: Response begins to habituate again

## Psychology Background

| Concept | Biological Basis | Network Implementation |
|---|---|---|
| Habituation | Synaptic vesicle depletion | Short-term depression weight rule |
| Sensitization | Serotonin modulation in *Aplysia* | Facilitatory interneuron input |
| Dishabituation | Distinct from sensitization in some models | Button resets depression state |

**Reference:** Kandel, E. R. (2001). "The Molecular Biology of Memory Storage: A Dialogue Between Genes and Synapses." *Science*, 294(5544), 1030-1038.
