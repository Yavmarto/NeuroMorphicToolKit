# Hardware Demos

Hands-on neuromorphic projects using neurocnl as the specification layer. Each demo pairs a CNL behavioral spec with affordable hardware to demonstrate spec-driven spiking neural network development.

## Your Hardware

| Board | Role | Key Specs |
|---|---|---|
| **Teensy 4.1** | Real-time SNN execution | 600 MHz ARM Cortex-M7, 1 MB RAM, GPIO, analog inputs |
| **OpenBCI Ganglion** | Biosignal acquisition | 4 channels, 200 Hz, EEG/EMG/ECG, BLE, BrainFlow SDK |

---

## Demo 1 — Gripper Reflex Training *(in progress)*

**Concept:** A robotic gripper learns to prevent objects from slipping by training its reflexive grip strength through STDP.

**Psychology connection:** Classical reflex arc + operant conditioning. The slip signal acts as the "teaching signal" that strengthens the grip reflex over repeated trials.

**Hardware:**
- Teensy 4.1
- Servo motor (SG90 or MG996R, ~€5)
- Force-sensitive resistor (FSR 402, ~€8)
- 3D-printed or laser-cut gripper mechanism
- Small objects of varying weight for training

**How it works:**

```
Force sensor → Spike encoder (rate coding) → [neurocnl SNN on Teensy]
                                                     ↓
                                              Grip motor command
                                                     ↓
Object slipping? ← Force drops below threshold ← Feedback sensor
       ↓
  STDP weight update (strengthen grip response)
```

**CNL spec:** [`gripper_reflex/gripper_reflex.cnl`](gripper_reflex/gripper_reflex.cnl)

**What it demonstrates:**
- Spec-driven network generation
- Sensory-motor reflex arc running on embedded hardware
- STDP-based adaptation (once Phase 1 of roadmap is complete)
- Closed-loop control with physical feedback

**Estimated cost:** ~€15–25 (excluding Teensy)

---

## Demo 2 — EMG-Controlled Prosthetic Prototype

**Concept:** Use forearm EMG signals captured by the OpenBCI Ganglion to control a servo-driven prosthetic finger via a spiking neural network.

**Psychology connection:** Motor control and neural prosthetics. The SNN decodes muscle activation intent from biological signals — the same principle behind myoelectric prostheses.

**Hardware:**
- OpenBCI Ganglion (EMG acquisition)
- Teensy 4.1 (SNN execution + servo control)
- 2× servo motors (SG90, ~€3 each)
- 3D-printed finger mechanism ([open-source designs available](https://openbionicslabs.com/))
- EMG electrode pads (reusable, ~€10 for a pack)
- Jumper wires

**How it works:**

```
Forearm muscles → EMG electrodes → OpenBCI Ganglion
                                        ↓
                                   BrainFlow SDK
                                        ↓
                              Spike encoding (temporal)
                                        ↓
                           [neurocnl SNN on Teensy]
                                        ↓
                              Servo motor commands
                                        ↓
                           Prosthetic finger flexion
```

**CNL spec:** [`emg_prosthetic/emg_prosthetic.cnl`](emg_prosthetic/emg_prosthetic.cnl)

**What it demonstrates:**
- Real biosignal integration (EMG → spike trains)
- Brain-computer interface pipeline
- Spec-driven motor decoding
- Practical application (assistive technology)

**Estimated cost:** ~€20–30 (excluding Ganglion and Teensy)

**Netherlands relevance:** The Netherlands has a strong medical devices sector and rehabilitation robotics research (TU Delft, University of Twente). This demo directly maps to industry work.

---

## Demo 3 — Habituation and Sensitization

**Concept:** Demonstrate two fundamental forms of non-associative learning using a spiking network on the Teensy. A repeated stimulus causes decreased response (habituation), while a novel or strong stimulus causes increased response (sensitization).

**Psychology connection:** These are the simplest forms of learning, well-studied in organisms from *Aplysia* sea slugs (Eric Kandel's Nobel Prize work) to humans. Every psychology student learns about habituation in their first year.

**Hardware:**
- Teensy 4.1
- Ultrasonic distance sensor (HC-SR04, ~€3)
- Piezo buzzer (~€1)
- LED + resistor (~€1)
- Tactile push button for "novel stimulus" injection (~€0.50)

**How it works:**

```
Distance sensor → Spike encoder (rate) → [Sensory population]
                                               ↓
                                     [Interneuron (habituating)]
                                               ↓
                                        [Motor population]
                                               ↓
                                         Buzzer + LED

Novel stimulus (button) → [Sensitization pathway] → Disinhibit interneuron
```

When you wave your hand in front of the sensor repeatedly, the buzzer response fades (habituation). Press the button (a "surprising" stimulus), and the response comes back stronger than before (sensitization).

**CNL spec:** [`habituation/habituation.cnl`](habituation/habituation.cnl)

**What it demonstrates:**
- Non-associative learning in spiking networks
- Synaptic depression (habituation) and facilitation (sensitization)
- Multi-population network (sensory → interneuron → motor)
- Psychology-to-hardware pipeline

**Estimated cost:** ~€5–8 (excluding Teensy)

---

## Demo 4 — Classical Conditioning (Pavlovian Learning)

**Concept:** A spiking network learns to associate a neutral stimulus (tone) with a reflexive response (light flash), mimicking Pavlov's conditioning experiments.

**Psychology connection:** This is the foundational experiment in learning psychology. The SNN learns the tone→response association through spike-timing dependent plasticity, providing a neuromorphic implementation of a concept every psychology student knows.

**Hardware:**
- Teensy 4.1
- Piezo buzzer for conditioned stimulus (~€1)
- LED for unconditioned stimulus (~€1)
- Light-dependent resistor (LDR) as "eye" sensor (~€1)
- Servo motor for conditioned response (e.g., "salivation" indicator) (~€5)

**How it works:**

```
Phase 1 — Before conditioning:
  Buzzer (tone) → [Auditory sensory] → [Motor] → No response
  LED (flash)   → [Visual sensory]  → [Motor] → Servo moves (unconditioned response)

Phase 2 — During conditioning (paired presentation):
  Buzzer + LED presented together repeatedly
  STDP strengthens: [Auditory sensory] → [Motor] connection

Phase 3 — After conditioning:
  Buzzer (tone alone) → [Auditory sensory] → [Motor] → Servo moves (conditioned response!)
```

**CNL spec:** [`classical_conditioning/classical_conditioning.cnl`](classical_conditioning/classical_conditioning.cnl)

**What it demonstrates:**
- Associative learning via STDP
- Multi-sensory integration (auditory + visual)
- Before/during/after conditioning phases
- Direct mapping from psychology theory to neuromorphic hardware

**Estimated cost:** ~€8–10 (excluding Teensy)

---

## Demo 5 — BCI Neurofeedback Loop

**Concept:** Use the OpenBCI Ganglion to read EEG signals, classify brain states (e.g., focused vs. relaxed based on alpha band power), and provide real-time visual or auditory feedback through a spiking network.

**Psychology connection:** Neurofeedback is used in clinical psychology for ADHD, anxiety, and meditation training. The SNN processes EEG features and drives the feedback signal — demonstrating a complete brain-computer interface loop.

**Hardware:**
- OpenBCI Ganglion (EEG acquisition)
- Teensy 4.1 (optional, for physical feedback)
- EEG electrode headband or dry electrodes (~€15–25)
- Neopixel LED strip for visual feedback (~€8)
- Speaker/buzzer for auditory feedback (~€2)

**How it works:**

```
Scalp EEG → OpenBCI Ganglion → BrainFlow SDK (Python)
                                      ↓
                          Band-pass filter (8-12 Hz alpha)
                                      ↓
                            Spike encoding (rate)
                                      ↓
                       [neurocnl SNN — classifier]
                                      ↓
                 Alpha power high? → "Relaxed" → Blue LEDs, calm tone
                 Alpha power low?  → "Focused" → Red LEDs, alert tone
```

**CNL spec:** [`bci_neurofeedback/bci_neurofeedback.cnl`](bci_neurofeedback/bci_neurofeedback.cnl)

**What it demonstrates:**
- Real-time EEG processing with spiking networks
- Brain-computer interface (BCI) pipeline
- Clinical psychology application (neurofeedback)
- Full loop: brain → sensor → SNN → feedback → brain

**Estimated cost:** ~€25–35 (excluding Ganglion)

---

## Demo 6 — Tactile Exploration Robot

**Concept:** A small wheeled robot uses whisker-like tactile sensors to navigate obstacles, inspired by rat whisker barrel cortex processing. The SNN builds a spatial map through touch.

**Psychology connection:** Somatosensory processing, spatial cognition, and exploratory behavior. Rats use whiskers to build spatial representations — this demo implements the neural circuit in silicon.

**Hardware:**
- Teensy 4.1
- 2× DC motors with wheels (N20 motors, ~€8)
- L298N motor driver (~€5)
- 4× flex sensors or microswitches as "whiskers" (~€12)
- Small robot chassis (3D-printed or cardboard, ~€5)
- 9V battery pack (~€3)

**How it works:**

```
Whisker sensors (left, right, front-left, front-right)
                    ↓
          Spike encoding (delta modulation — spike on contact)
                    ↓
           [Sensory population — somatotopic map]
                    ↓
           [Interneuron — lateral inhibition]
                    ↓
           [Motor population — left/right drive]
                    ↓
        Differential motor drive (turn away from contact)
```

**CNL spec:** [`tactile_explorer/tactile_explorer.cnl`](tactile_explorer/tactile_explorer.cnl)

**What it demonstrates:**
- Somatotopic mapping (whisker → neuron mapping)
- Lateral inhibition for spatial processing
- Autonomous navigation using spiking networks
- Biologically inspired sensorimotor integration

**Estimated cost:** ~€30–40 (excluding Teensy)

---

## Getting Started

All demos follow the same workflow:

1. **Write the CNL spec** describing the desired neural behavior
2. **Validate** against biological invariants (legacy grammar: `neurocnl.layers.layer1_validator.validate`; `nir_cnl` grammar: `neurocnl.layers.layer1_validator.validate_nir_records`, see `examples/04_full_pipeline_poc.py`)
3. **Generate** the Nengo network (`neurocnl.converter.nengo_io.NengoIO().from_nir(...)`, see `examples/04_full_pipeline_poc.py`)
4. **Simulate** in software first (Nengo + MuJoCo where applicable)
5. **Export** network parameters to Teensy firmware
6. **Deploy** to hardware and iterate

### Software Dependencies

```bash
pip install nengo brainflow numpy matplotlib
```

For OpenBCI demos, install the [BrainFlow SDK](https://brainflow.readthedocs.io/):

```bash
pip install brainflow
```

### Common Components Shopping List

| Component | Use | Approx. Cost |
|---|---|---|
| SG90 servo motor | Gripper, conditioning response | €3 |
| FSR 402 force sensor | Grip force measurement | €8 |
| HC-SR04 ultrasonic sensor | Distance/proximity detection | €3 |
| Piezo buzzer | Auditory stimulus | €1 |
| Neopixel LED strip (8 LEDs) | Visual feedback | €8 |
| Flex sensor | Whisker/tactile input | €3 each |
| Breadboard + jumper wires | Prototyping | €5 |
| **Total starter kit** | | **~€35** |

Most components are available from local electronics shops or online retailers (e.g., Kiwi Electronics, Opencircuit.nl, or AliExpress for bulk).
