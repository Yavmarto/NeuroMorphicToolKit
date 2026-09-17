# Jules Roadmap

*Advice for the next steps of the Neuromorphic Spec Translation Layer library and affordable hardware demo portfolio.*

---

## Background

- **User profile:** Master's in psychology and AI, mobile development experience.
- **Available hardware:** Teensy 4.1, Gripper, OpenBCI Ganglion.
- **Goal:** Build a portfolio to get a job at a neuromorphic computing company in the Netherlands.

---

## Part 1 — Library Extensions

The current library translates a Controlled Natural Language (CNL) spec through a 3-layer pipeline (physical invariants → behavioral spec → validation assertions) into Nengo simulations. The following extensions would make it significantly more capable and more relevant to real neuromorphic research.

### 1. Learning Rules (STDP)

Add Spike-Timing Dependent Plasticity to the CNL grammar and the Nengo generator.

- **Why:** STDP is the canonical unsupervised learning rule in neuromorphic computing. Every serious SNN framework supports it. Adding it lets specs describe *how* a network learns, not just how it fires.
- **What to add:**
  - New CNL sentence patterns, e.g. `A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms.`
  - Layer 1 invariants for weight bounds (weights must remain in a physiologically plausible range).
  - Nengo generator extension to emit `nengo.Connection` with a learning rule.
- **Complexity:** Medium. Nengo has built-in `nengo.PES` and supports custom learning rules. The CNL grammar extension is the hard part.

### 2. Axonal Delays

Add synaptic/axonal transmission delays to the spec and simulator.

- **Why:** Delays are a first-class feature in biological networks and in Loihi. Omitting them means the spec cannot describe coincidence detection, polychronization, or any timing-sensitive circuit.
- **What to add:**
  - New CNL pattern, e.g. `A synapse MUST have a transmission delay of 5ms.`
  - Layer 1 invariant: delay must be ≥ 0 and ≤ some maximum biological bound.
  - Nengo generator: `nengo.Connection(..., synapse=nengo.Lowpass(delay))`.
- **Complexity:** Low-to-medium. Nengo supports delays directly.

### 3. Loihi Backend Support

Extend the pipeline so that validated CNL specs compile to Intel Loihi hardware via NengoLoihi.

- **Why:** This closes the full pipeline promised by the architecture. A spec that runs only in Nengo simulation is useful; one that compiles to Loihi hardware is a job application.
- **What to add:**
  - A `--backend loihi` flag on the pipeline runner.
  - NengoLoihi-specific constraints in Layer 1 (e.g., Loihi has integer synaptic weights; the spec must be quantization-aware).
  - A Layer 3 assertion that confirms compiled output fits within Loihi chip resource limits.
- **Complexity:** High. Requires access to Loihi hardware or the Intel cloud emulator. Start with the NengoLoihi emulator (no hardware required).

---

## Part 2 — Hardware Demo Ideas

All demos use existing hardware (Teensy 4.1, Gripper, OpenBCI Ganglion) and are designed to be affordable, reproducible, and portfolio-ready. Demos are ordered from most reliable to most complex.

### Demo 1 — EMG-Controlled Adaptive Gripper ⭐ *Start here*

**Hardware:** Teensy 4.1 + Gripper + surface EMG electrodes (cheap, OpenBCI Ganglion can read these)
**Signal:** Muscle activity (EMG) — one of the most reliable biosignals to capture with consumer hardware.

**What it does:** An SNN on the Teensy reads forearm EMG, classifies grip intent (open/close/hold), and drives the gripper with spiking motor commands. The network adapts grip force to resist slip using STDP.

**Why it matters for employers:** Adaptive prosthetics and human-machine interfaces are a core use case for neuromorphic chips (BrainChip Akida, Intel Loihi). This demo is directly relevant.

**CNL spec excerpt:**
```
A motor neuron MUST emit a spike IF EMG amplitude exceeds threshold.
A synapse MUST strengthen IF grip slip is detected within 100ms of motor spike.
A gripper MUST NOT increase force IF grip force exceeds 80% of maximum.
```

---

### Demo 2 — Tactile Slip Reflex

**Hardware:** Teensy 4.1 + Gripper + FSR (force-sensitive resistor, ~€5)
**Signal:** Contact force / slip event — extremely reliable with FSR sensors.

**What it does:** A 3-neuron SNN implements a biological slip reflex: FSR detects slip, interneuron gates the response, motor neuron fires to tighten grip. Latency is measured and compared to biological reflex arc latency (~50ms).

**Why it matters:** Demonstrates that a CNL spec can encode a biologically grounded reflex arc — the library's own first use case — on real hardware. The latency comparison is a concrete, measurable result.

---

### Demo 3 — EEG Attention Monitor

**Hardware:** OpenBCI Ganglion
**Signal:** Alpha band power (8–12 Hz) — the most stable, reproducible EEG signal from consumer headsets.

**What it does:** An SNN classifies attention state (focused vs. relaxed) from EEG alpha power in real time. Uses rate coding: high alpha → relaxed population fires, low alpha → focused population fires.

**Why it matters:** Neurotechnology and BCI are active areas for neuromorphic hardware in the Netherlands (Imec, Radboud University). This demo connects your psychology/AI background directly to hardware.

**CNL spec excerpt:**
```
An attention neuron MUST emit a spike IF alpha band power falls below resting baseline.
A relaxation neuron MUST emit a spike IF alpha band power exceeds resting baseline by 20%.
```

---

### Demo 4 — Neuromorphic Audio Wake-Word Detection

**Hardware:** Teensy 4.1 + MEMS microphone (e.g., SPH0645, ~€5)
**Signal:** Audio — cochlear-inspired spike encoding (onset detection).

**What it does:** A small SNN detects a specific wake word (e.g., "go") using spike-encoded audio features. The network uses temporal coincidence detection (requires axonal delays — ties directly to Library Extension 2).

**Why it matters:** On-device keyword spotting is one of the most commercially advanced neuromorphic applications. This demo shows the full pipeline: CNL spec → Nengo → deployed on Teensy, doing useful work at low power.

**Complexity:** Highest of the four demos. Spike-encoding audio reliably is the hard part. Use a published cochlear model (e.g., Brian2's `brian_hears`) to generate the spike trains.

---

## Recommended Sequence

| Step | Action |
|------|--------|
| 1 | Build Demo 1 (EMG Gripper). It uses the most reliable signal and directly showcases the adaptive SNN concept. |
| 2 | Add STDP learning rule to the library (Library Extension 1). Demo 1 now runs on the extended library. |
| 3 | Build Demo 2 (Slip Reflex). Uses the same hardware, adds a measurable biological comparison. |
| 4 | Add axonal delays to the library (Library Extension 2). |
| 5 | Build Demo 3 (EEG Attention). Brings in the OpenBCI Ganglion. |
| 6 | Add Loihi backend support (Library Extension 3) — or build Demo 4 in parallel if Loihi access is unavailable. |

---

## Why This Portfolio Works for the Netherlands

The neuromorphic computing ecosystem in the Netherlands is concentrated around:
- **Imec** (Eindhoven/Leuven) — hardware research, BCI chips.
- **Radboud University / Donders Institute** (Nijmegen) — computational neuroscience, neuromorphic models.
- **Neurable / BrainChip partners** — applied BCI.

A portfolio that combines:
1. A formal spec translation layer (demonstrating software engineering rigor),
2. Adaptive SNN demos on real hardware (demonstrating applied neuromorphic skill), and
3. EEG/EMG signal processing (directly leveraging the psychology + AI background),

...targets all three of these employer profiles simultaneously.
