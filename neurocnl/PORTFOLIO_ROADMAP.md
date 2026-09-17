# Portfolio Roadmap

A prioritized build order for someone with a psychology master's, an AI master's in progress, 7 years of mobile development experience, a Teensy 4.1, and an OpenBCI Ganglion — targeting neuromorphic computing companies in the Netherlands.

The items below combine library development work and hardware demos into a single timeline, ordered by portfolio impact. Each milestone produces something demonstrable: working code, a live hardware demo, or both.

---

## Priority 1 — Gripper Reflex on Teensy *(in progress)*

**What:** Deploy the existing neurocnl reflex arc to the Teensy 4.1 with a force sensor and servo gripper.

**Why it's first:** This is the fastest path from "I have a software library" to "I have a physical neuromorphic system." Every neuromorphic computing company wants to see that you can bridge simulation and hardware. The reflex arc already works end-to-end in Nengo — putting it on a microcontroller proves you can close that gap.

**Portfolio signal:** Embedded SNN development, real-time sensory-motor control, closed-loop feedback.

**Depends on:** Nothing — the current library already generates the network. You need a `teensy_exporter.py` to emit network parameters as a C header, plus Teensy firmware to run the LIF update loop.

**Library work required:**
- [ ] `teensy_exporter.py` — Export validated Nengo network parameters (thresholds, weights, time constants) to a C struct/header file
- [ ] Teensy LIF firmware template — C implementation of the LIF neuron update loop that loads exported parameters

**Hardware:** Teensy 4.1 + SG90 servo + FSR 402 force sensor (~€15)

**Demo:** [`demos/gripper_reflex/`](demos/gripper_reflex/)

---

## Priority 2 — STDP Learning Rules in CNL

**What:** Add spike-timing dependent plasticity to the CNL grammar so networks can learn, not just react.

**Why it's second:** This is the single biggest capability gap and it unlocks every adaptive demo below. Without STDP, the gripper can grip but cannot *learn* to grip better. With it, every subsequent demo becomes a story about learning — which is what makes neuromorphic computing interesting.

**Portfolio signal:** You understand what makes spiking networks different from conventional NNs. STDP is the native learning rule of neuromorphic hardware (Loihi, SpiNNaker, BrainScaleS all support it natively). This is the first thing a neuromorphic company will look for.

**Library work required:**
- [ ] New CNL patterns for STDP (learning rate, pre-before-post potentiation, post-before-pre depression)
- [ ] New parser regexes in `cnl_parser.py`
- [ ] New Layer 1 invariants (learning rate bounds, weight bounds)
- [ ] Nengo mapping to `nengo.PES` / `nengo.BCM` / `nengo.Oja` learning rules
- [ ] New Layer 3 assertion templates for weight change verification
- [ ] Update Teensy exporter to include STDP parameters

---

## Priority 3 — Classical Conditioning Demo

**What:** A Pavlovian learning experiment on the Teensy — a neutral stimulus (tone) becomes associated with a reflexive response (servo movement) through repeated pairing.

**Why it's third:** This is the strongest single portfolio piece because it directly maps a foundational psychology experiment to neuromorphic hardware using STDP. It tells a complete story: "I took a concept from my psychology degree, expressed it in a formal spec language, compiled it to a spiking neural network, and ran it on real hardware — and you can watch the learning happen in real time."

**Portfolio signal:** Psychology-to-engineering pipeline, biologically plausible learning, spec-driven development, observable before/during/after conditioning phases. This is the demo you show in interviews.

**Depends on:** Priority 2 (STDP learning rules).

**Hardware:** Teensy 4.1 + piezo buzzer + LED + LDR + SG90 servo (~€8)

**Demo:** [`demos/classical_conditioning/`](demos/classical_conditioning/)

---

## Priority 4 — Spike Encoding Utilities

**What:** A `spike_encoding.py` module with rate coding, temporal coding, and delta modulation functions for converting analog sensor signals to spike trains.

**Why it's fourth:** Every hardware demo needs to convert sensor readings to spikes. Right now Nengo handles this implicitly through ensemble encoders, but hardware deployment needs explicit encoding. Building this as a reusable module means every subsequent demo can import it instead of reimplementing the conversion.

**Portfolio signal:** Shows you understand the analog-to-spike interface — a practical engineering problem that every neuromorphic system must solve. Companies building real neuromorphic products deal with this daily.

**Library work required:**
- [ ] `spike_encoding.py` — `rate_encode()`, `temporal_encode()`, `delta_encode()` functions
- [ ] Unit tests for each encoding strategy
- [ ] Integration with Nengo input nodes and Teensy analog reads
- [ ] Documentation with examples showing each encoding method

---

## Priority 5 — EMG Prosthetic with OpenBCI Ganglion

**What:** Read forearm EMG signals from the Ganglion, spike-encode them, process through the neurocnl SNN, and drive a servo-controlled prosthetic finger.

**Why it's fifth:** This uses both pieces of hardware you own (Ganglion + Teensy), demonstrates real biosignal integration, and maps directly to the Netherlands medical devices and rehabilitation robotics sector (TU Delft Biomedical Engineering, University of Twente BSS group, companies like Hankamp Rehab).

**Portfolio signal:** Brain-computer interface, EMG-to-spike encoding, real-time biosignal processing, assistive technology application. This is the demo most relevant to Dutch industry.

**Depends on:** Priority 4 (spike encoding for the EMG→spike conversion).

**Library work required:**
- [ ] `brainflow_adapter.py` — Wraps BrainFlow SDK to stream from Ganglion, applies bandpass filtering, and outputs spike-encoded streams
- [ ] EMG-specific preprocessing (rectification, envelope extraction, 20–450 Hz bandpass)
- [ ] Serial bridge between Python (BrainFlow) and Teensy (SNN execution)

**Hardware:** OpenBCI Ganglion + Teensy 4.1 + 2× SG90 servos + EMG electrode pads (~€20)

**Demo:** [`demos/emg_prosthetic/`](demos/emg_prosthetic/)

---

## Priority 6 — Habituation and Sensitization Demo

**What:** A distance sensor triggers a buzzer/LED response that fades with repetition (habituation) and returns stronger after a novel stimulus (sensitization).

**Why it's sixth:** This is the cheapest (~€5) and simplest demo to build, and it demonstrates a different learning mechanism (short-term synaptic depression/facilitation rather than STDP). It is a good quick win to have in the portfolio alongside the more complex demos, and it shows breadth of neuroscience knowledge.

**Portfolio signal:** Non-associative learning, synaptic depression/facilitation, multi-population networks, direct link to Kandel's Nobel Prize work in *Aplysia*.

**Depends on:** Priority 2 (learning rules for synaptic depression).

**Library work required:**
- [ ] Multi-population network support in `nengo_generator.py` (sensory → interneuron → motor)
- [ ] Synaptic depression/facilitation parameters in CNL grammar

**Hardware:** Teensy 4.1 + HC-SR04 ultrasonic sensor + piezo buzzer + LED + push button (~€5)

**Demo:** [`demos/habituation/`](demos/habituation/)

---

## Priority 7 — Visualization Tools

**What:** Matplotlib-based spike raster plots, membrane voltage traces, network topology diagrams, and weight evolution plots.

**Why it's seventh:** Every demo above generates data that needs to be visualized for debugging, presentation, and documentation. Raster plots and voltage traces are the standard visual language of computational neuroscience — having clean visualizations in your portfolio makes every other demo look more professional.

**Portfolio signal:** Professional presentation, computational neuroscience fluency, ability to communicate technical results visually.

**Library work required:**
- [ ] `visualization.py` — `plot_raster()`, `plot_voltage()`, `plot_topology()`, `plot_weights()`
- [ ] Export to PNG and HTML (for embedding in READMEs and portfolio site)
- [ ] Integration with Nengo probe data

---

## Priority 8 — BCI Neurofeedback Loop

**What:** Real-time EEG alpha-band classification using the Ganglion, with visual/auditory feedback driven by the SNN.

**Why it's eighth:** This is a strong demo but it's more signal processing and less neuromorphic computing. It uses the Ganglion well and has clear clinical psychology applications (ADHD, anxiety, meditation training), but the SNN component is relatively simple (threshold classification). Build it after the more neuromorphically demanding demos.

**Portfolio signal:** EEG processing, BCI pipeline, clinical psychology application, real-time feedback loop.

**Depends on:** Priority 5 (BrainFlow adapter).

**Hardware:** OpenBCI Ganglion + EEG headband + Neopixel LED strip + buzzer (~€25)

**Demo:** [`demos/bci_neurofeedback/`](demos/bci_neurofeedback/)

---

## Priority 9 — Multi-Population Network Topology

**What:** Extend the CNL grammar and generator to support arbitrary population graphs — interneurons, inhibitory connections, recurrent paths — instead of the hard-coded sensory→motor arc.

**Why it's ninth:** By this point you will have hit the limits of the two-population architecture multiple times (habituation needs interneurons, the tactile explorer needs lateral inhibition). Generalizing the topology is a natural refactoring that makes the library genuinely useful for complex circuits.

**Portfolio signal:** Software architecture, graph-based network construction, scalable design.

**Library work required:**
- [ ] CNL patterns for population definition, inhibitory connections, projection targets
- [ ] Refactor `nengo_generator.py` to build from a population graph rather than hard-coded ensembles
- [ ] Update Layer 1 invariants for inhibitory weight constraints (Dale's law)

---

## Priority 10 — Tactile Exploration Robot

**What:** A small wheeled robot with whisker-like flex sensors that navigates using a spiking somatotopic map, inspired by rat barrel cortex.

**Why it's tenth:** This is the most complex and expensive demo. It requires multi-population networks (Priority 9), lateral inhibition, and delta-modulation spike encoding. It is impressive but depends on the most library features. Build it last as the capstone portfolio piece.

**Portfolio signal:** Autonomous agent, somatosensory processing, biologically inspired robotics, lateral inhibition, spatial cognition.

**Depends on:** Priority 4 (spike encoding), Priority 9 (multi-population networks).

**Hardware:** Teensy 4.1 + 2× N20 motors + L298N driver + 4× flex sensors + chassis (~€35)

**Demo:** [`demos/tactile_explorer/`](demos/tactile_explorer/)

---

## Priority 11 — Export Formats

**What:** Support exporting compiled networks to NeuroML, NengoLoihi, Lava, and SpiNNaker formats.

**Why it's last:** Export formats are important for interoperability but they don't produce visible demos. Build them when you need them — NeuroML when publishing a paper, NengoLoihi when you get access to Loihi hardware. The C header export (Priority 1) is the only export format that matters early.

**Library work required:**
- [ ] NeuroML exporter (academic publishing, standard interchange)
- [ ] NengoLoihi compilation path (Intel Loihi hardware)
- [ ] Lava exporter (Intel's open-source neuromorphic framework)
- [ ] SpiNNaker exporter (University of Manchester platform)

---

## Summary

| Priority | Milestone | Type | Cost | Key Portfolio Signal |
|---|---|---|---|---|
| 1 | Gripper reflex on Teensy | Hardware demo | ~€15 | Simulation→hardware bridge |
| 2 | STDP learning rules | Library feature | — | Core neuromorphic competency |
| 3 | Classical conditioning | Hardware demo | ~€8 | Psychology↔neuromorphic showcase |
| 4 | Spike encoding utilities | Library feature | — | Analog-to-spike engineering |
| 5 | EMG prosthetic | Hardware demo | ~€20 | BCI + Dutch medical sector |
| 6 | Habituation/sensitization | Hardware demo | ~€5 | Breadth of learning mechanisms |
| 7 | Visualization tools | Library feature | — | Professional presentation |
| 8 | BCI neurofeedback | Hardware demo | ~€25 | Clinical psychology application |
| 9 | Multi-population topology | Library feature | — | Scalable architecture |
| 10 | Tactile explorer robot | Hardware demo | ~€35 | Capstone: autonomous agent |
| 11 | Export formats | Library feature | — | Hardware interoperability |

**Total hardware cost for all demos:** ~€108 (excluding Teensy and Ganglion, which you already own).

**Minimum viable portfolio (Priorities 1–3):** ~€23 and demonstrates the full pipeline from psychology theory through formal spec to physical neuromorphic hardware with learning.
