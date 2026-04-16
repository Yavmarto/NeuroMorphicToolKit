# Thesis Analysis — Claude's Read of the Codebase

_Written: 2026-04-16. Based on direct inspection of this repository._

---

## What this codebase actually is

The NeuroMorphicToolKit (NMTK) is a monorepo containing two distinct things that are easy to conflate:

1. **A research project** — the Neuro-Dream-Hand module, which is a genuine thesis contribution about adaptive neuromorphic control for a prosthetic hand
2. **A platform built around it** — a Flutter macOS launcher, Python FastAPI backends, Docker orchestration, shared UI libraries, and a family of supporting tools (NeuroCNL, Neurosense, Neurochip, Neurobench, Neurohub)

These are not the same thesis. The platform is impressive engineering work, but it is not a research contribution in Applied AI. The Neuro-Dream-Hand module, by contrast, is exactly that.

---

## The actual thesis: Neuro-Dream-Hand

`Neuro-Dream-Hand/` is a self-contained neuromorphic prosthetic control framework. Its README calls it the "Dreaming Prosthetic" thesis project. Here is what has been built and empirically validated:

### What is simulation-validated (phases 1–3, complete)

| Result | Evidence in code |
|--------|-----------------|
| >95% slip survival under random force perturbations | Drop-test benchmarks, seeded RNG, pytest |
| PES online learning converges in <5 s of interaction | OCL sweep experiments |
| Sleep/wake consolidation reduces stopping distance over 30 simulated days | Multi-day factorial experiments |
| Weight quantization to 4-bit INT degrades control stability in a measurable, sweep-able way | Quantization analysis, HDF5 crossbar export |
| Fault injection (dead neurons, stuck-at, additive noise) is characterized | Three injection modes, seeded RNG, tested |
| Energy profiling at pJ/SOP granularity | CPU-estimated (Nengo runtime, not on-chip) |

These are real simulation results with reproducible code. They constitute a defensible empirical contribution.

### What is code-complete but not physically validated (phases 4–5)

| Component | Status |
|-----------|--------|
| Serial bridge to Teensy 4.0 actuator | Mocked serial port, no real hardware run |
| FSR/load cell sensor ingestion | Calibration script ready, no real hardware |
| EMG ingestion via OpenBCI Ganglion + BrainFlow | Mocked BrainFlow, no real board |
| EMG-to-spike encoder (bandpass → envelope → normalize) | Tested synthetically, not with real EMG |
| Loihi 2 deployment via nengo-loihi | Code complete, requires Intel SDK + hardware access |

These cannot be claimed as validated results. They are forward scope for hardware phases. The README is honest about this with an explicit disclaimer.

### What the energy efficiency claim really means

> "Energy efficiency claims of neuromorphic hardware (Joules-per-spike) are not physically realized. The quantization analysis models what weight resolution a chip would require, but does not measure actual on-chip power."

This is stated plainly in the README. CPU-estimated pJ/SOP is a proxy metric. Any thesis claim about energy efficiency must be framed as a modelled estimate, not a measured result.

---

## Why this is thesis-worthy (for Applied AI at JKU)

The Neuro-Dream-Hand hits the right marks for a Master's thesis:

**Novel contribution, not replication.** Online Continual Learning (OCL) using PES in a closed-loop SNN control system is not a standard benchmark exercise. Combining slip detection, reflex control, and sleep consolidation in one coherent system is a meaningful design.

**Applied and empirical.** The simulation results are reproducible (seeded RNG, pytest coverage, multi-day experiments). There is a concrete evaluation protocol.

**Grounded in real hardware plans.** Even if hardware phases aren't physically done, having code-complete phases with mock-validated interfaces shows forward engineering rigour. The sim-to-real question can be framed as open scope rather than a gap.

**End-to-end pipeline.** The thesis can trace a path: NeuroCNL (interpretable specification) → Neurosense (EMG signal → spike encoding) → Neuro-Dream-Hand (SNN control + OCL) → Neurochip (quantized deployment) → Neurobench (evaluation). This pipeline exists as tested integration code, not just architecture diagrams.

---

## Recommended framing

**Title:**

> Interpretable Spiking Neural Network Control with Online Continual Learning for Neuromorphic Prosthetic Hands

Or, if the EMG pipeline is physically validated before submission:

> From EMG to Adaptive Grip: An End-to-End Neuromorphic Prosthetic Pipeline with Controlled Natural Language Specification and Online Continual Learning

**Research question (simulation-only scope, safe to defend):**

> Can a biologically constrained SNN controller using PES online learning maintain stable grasp under perturbation in physics simulation, and what are the quantization and energy efficiency implications for deployment to neuromorphic hardware?

**Research question (if hardware phases complete before submission):**

> How does the sim-to-real gap affect an SNN prosthetic controller validated in MuJoCo when deployed to a Teensy 4.0 testbed with real EMG and tactile input?

---

## The supporting modules and their thesis role

### neurocnl — interpretability layer

NeuroCNL is the specification front-end. It parses Controlled Natural Language (CNL) sentences like "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0" into validated Nengo networks. The three-layer invariant architecture (physical → behavioral → auto-generated tests) is a genuine contribution to interpretable neuromorphic design.

**Thesis role:** Motivate interpretability — you can read and audit the SNN specification, unlike a weight matrix. If you wrote the Neuro-Dream-Hand CNL specs using this module, that is a concrete claim about interpretable design. If not, this is a supporting tool worth mentioning, not a core contribution.

### Neurosense — biosignal encoding

Neurosense handles the EMG → spike encoding pipeline. The canonical workflow (2-channel forearm, bandpass filter, envelope extraction, normalization, threshold) is validated synthetically and recorded to HDF5. Real OpenBCI Cyton/Ganglion hardware is marked `experimental`.

**Thesis role:** If you have access to an EMG device and can run the encoding pipeline on real data before submission, this becomes a validated chapter on signal encoding strategy. If not, frame it as the encoding module used in the pipeline, with synthetic validation.

### Neurochip — deployment and quantization

Neurochip owns PYNQ Z2 / Teensy / Loihi 2 deployment. The quantization contracts (4–8 bit INT, Loihi 2/Akida-compatible weight export) are where the Neuro-Dream-Hand quantization analysis connects to real deployment targets.

**Thesis role:** Even without physical hardware, the quantization sweep from the Neuro-Dream-Hand (4-bit degradation analysis, crossbar HDF5 export) feeds into what Neurochip would deploy. This can be presented as a validated hardware preparation step.

### Neurobench — evaluation

Neurobench provides standardised benchmarking: task success rate, stopping distance, adaptation speed, spike rates, pJ/SOP estimates, robustness under faults.

**Thesis role:** Use Neurobench's metrics as your evaluation framework. This is cleaner than inventing ad-hoc metrics. It also makes the thesis reproducible — someone else can re-run your benchmark suite.

### What to leave out

- The Flutter launcher (`nmtk/`) — zero research contribution
- Neurohub — 0% complete, explicitly out of scope
- Docker orchestration, CI/CD, launcher doctor — engineering, not research
- Neurosim's graph canvas — a UI, not a contribution

---

## Fidelity map — what you can and cannot claim

| Claim | Status | How to frame it |
|-------|--------|-----------------|
| SNN achieves >95% slip survival in MuJoCo simulation | **Validated** | State as result with metrics |
| PES online learning adapts within 5 s of perturbation | **Validated** | State as result with metrics |
| Sleep/wake consolidation improves over 30 simulated days | **Validated** | State as result with metrics |
| 4-bit quantization degrades stability by X% | **Validated** (simulation) | State as simulation result |
| Energy efficiency on Loihi 2 is Y pJ/inference | **Modelled only** | "CPU-estimated proxy" — not a hardware result |
| Sim-to-real gap with Teensy 4.0 hardware | **Not validated** | "Future work / hardware phase in progress" |
| Real EMG input from OpenBCI Ganglion | **Not validated** | "Synthetic validation only; hardware phase pending" |
| Deployment to physical Loihi 2 chip | **Not validated** | "Code complete, requires SDK/hardware access" |

---

## Proposed thesis structure

```
Chapter 1 — Introduction
  - Neuromorphic prosthetics: the problem
  - Why SNNs over conventional control
  - Thesis scope: simulation-validated pipeline, hardware preparation
  - Overview of NMTK as experimental platform

Chapter 2 — Background
  - Spiking Neural Networks: LIF neurons, PES learning rule
  - Continual learning and catastrophic forgetting in SNNs
  - Neuromorphic hardware targets (Loihi 2, Akida, SpiNNaker2)
  - Prior work: SNN prosthetic control, STDP-based adaptation

Chapter 3 — System Design
  - Controlled Natural Language as specification layer (neurocnl)
  - EMG-to-spike encoding pipeline (Neurosense)
  - SNN control architecture: reflex arc, OCL, sleep consolidation (Neuro-Dream-Hand)
  - Quantization and deployment preparation (Neurochip)
  - Evaluation framework (Neurobench)

Chapter 4 — Simulation Experiments
  - Experimental setup: MuJoCo hand, object parameters, perturbation protocol
  - Baseline performance (no learning)
  - Online learning results: slip survival, adaptation speed
  - Sleep consolidation: 30-day experiment
  - Ablation: learning rate, neuron count, error scale
  - Quantization sweep: 4-bit vs 8-bit INT degradation

Chapter 5 — Hardware Preparation
  - Quantization analysis and crossbar export
  - Serial bridge design (Teensy 4.0)
  - EMG encoding validation (synthetic)
  - Fault injection characterisation
  - (If hardware available: real Teensy/EMG results here)

Chapter 6 — Discussion
  - What simulation validates
  - What requires hardware to evaluate
  - Interpretability trade-off: CNL specification vs. weight matrix
  - Sim-to-real gap: open questions

Chapter 7 — Conclusion
  - Summary of simulation contributions
  - Hardware roadmap
  - Open problems in neuromorphic prosthetic control
```

---

## What to avoid

**Do not claim energy efficiency without hardware.** CPU-estimated pJ/SOP is not a neuromorphic result. Either remove it or qualify it as a modelled baseline.

**Do not present hardware phase results as complete.** The code is there; the hardware isn't. Chapters on Teensy/EMG/Loihi should be either in a "future work" section or, if hardware is available before submission, explicitly marked as completed in that section.

**Do not make the thesis about NMTK as a platform.** Nobody at JKU needs a thesis about Flutter launchers and Docker Compose. The platform is the vehicle; Neuro-Dream-Hand is the contribution.

**Do not overstate CNL's role if you didn't use it empirically.** NeuroCNL is an excellent tool. If the Neuro-Dream-Hand specs were written using CNL syntax and validated through its three-layer invariant checker, that is a concrete interpretability claim. If the module wasn't actually used to drive the experiments, mention it as a supporting tool without overclaiming.

---

## Alternative directions if hardware remains inaccessible

If no physical hardware is available before submission, the thesis is still defensible as a simulation study, but needs to frame itself differently:

**Option A — Simulation study on OCL stability**
Focus entirely on the continual learning question: under what perturbation regimes does PES online learning remain stable? What are the hyperparameter sensitivities? How does weight quantization interact with learning stability? This is a clean, fully simulation-supported thesis.

**Option B — CNL as interpretable SNN design interface**
Focus on NeuroCNL: can Controlled Natural Language specifications produce networks that are measurably more interpretable (auditable, reproducible, constraint-verifiable) than hand-coded Nengo networks? Build a small experiment comparing CNL-specified vs. manually-specified versions of the same controller.

**Option C — Encoding strategy comparison**
Focus on Neurosense: compare multiple EMG-to-spike encoding strategies (rate coding, temporal coding, population coding) on the Neuro-Dream-Hand control task using synthetic EMG signals. Measure downstream control quality.

None of these alternatives are as strong as the full Neuro-Dream-Hand narrative with hardware validation, but all are defensible without physical hardware.

---

## Bottom line

The Neuro-Dream-Hand module is a real thesis. The simulation results are solid, reproducible, and novel. The supporting pipeline (CNL spec → EMG encoding → SNN control → quantized deployment → benchmarking) is an end-to-end applied AI system. The gap is hardware validation, which is honestly documented in the codebase itself.

Write the thesis around the simulation contributions. Frame the hardware phases as completed engineering preparation pending hardware access. Do not pad it with the Flutter launcher.

The strongest single sentence pitch:

> "This thesis demonstrates that a biologically constrained SNN using online PES learning can achieve stable, adaptive prosthetic grip under perturbation in physics simulation, and characterizes the quantization and encoding requirements for deployment to neuromorphic hardware."
