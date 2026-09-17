# CNL Vocabulary Expansion Plan

This document outlines a realistic, biologically accurate, and technically feasible plan for expanding the Controlled Natural Language (CNL) vocabulary in `neurocnl`.

The current CNL supports fundamental Leaky Integrate-and-Fire (LIF) dynamics, standard synaptic weights, basic learning (STDP), and population topology. To increase the biological fidelity and computational power of the models described by the CNL, we propose adding the following concepts. Each expansion is chosen because it reflects a crucial biological mechanism and can be mapped directly to our compilation target, Nengo.

---

## 1. Adaptive Spiking (Spike-Frequency Adaptation)

**Biological Justification:**
Real biological neurons rarely maintain a constant firing rate given a constant stimulus. Due to slow ion channel dynamics (such as calcium-activated potassium channels), their firing threshold effectively increases or their membrane potential hyperpolarizes after repeated spiking. This prevents runaway excitation and allows networks to encode the derivative of stimuli (change) rather than just absolute magnitude.

**Nengo Mapping:**
Nengo natively supports adaptation via the `nengo.AdaptiveLIF()` neuron type, which introduces an adaptation time constant (`tau_n`) and an adaptation increment (`inc_n`).

**CNL Examples:**
- `The sensory neuron MUST exhibit firing adaptation WITH time constant of 0.2 seconds`
- `The motor neuron MUST NOT exhibit firing adaptation`

**Implementation Steps:**
- Add `adaptive_spiking` concept to parser with regex matching "exhibit firing adaptation".
- Map condition to `tau_n` extraction.
- In Nengo generator, conditionally swap `nengo.LIF()` for `nengo.AdaptiveLIF(tau_n=...)` when this property is present for a given subject.

---

## 2. Receptor-Specific Synaptic Dynamics (AMPA, NMDA, GABA)

**Biological Justification:**
Currently, the CNL treats synapses as having a generic "transmission delay" or weight. In reality, synaptic transmission is governed by specific neurotransmitter receptors with drastically different temporal dynamics. For example, AMPA receptors are fast-acting excitatory (~5ms), NMDA receptors are slow excitatory (~100ms) and voltage-dependent, while GABA receptors provide fast (GABA_A) or slow (GABA_B) inhibition. Defining these explicitly allows for complex temporal integration in networks.

**Nengo Mapping:**
These map to the `synapse` parameter in `nengo.Connection()`. Instead of a simple `nengo.Lowpass` with an arbitrary delay, we apply standard time constants based on the receptor type (e.g., `nengo.Alpha(0.005)` for AMPA, `nengo.Alpha(0.1)` for NMDA).

**CNL Examples:**
- `The connection from sensory to motor MUST use NMDA receptor dynamics WITH time constant of 0.1 seconds`
- `A synapse MUST transmit WITH AMPA receptor dynamics`

**Implementation Steps:**
- Add `receptor_dynamics` concept recognizing "AMPA", "NMDA", "GABA_A", "GABA_B".
- Map to standard default time constants if not explicitly provided.
- Apply to `synapse` filter in Nengo `Connection` generation.

---

## 3. Short-Term Plasticity (STP: Facilitation and Depression)

**Biological Justification:**
Unlike long-term learning (STDP) which changes weights permanently, short-term plasticity refers to transient changes in synaptic efficacy over tens to hundreds of milliseconds. High-frequency spiking can deplete neurotransmitter vesicles (Depression) or lead to residual calcium build-up increasing release probability (Facilitation). STP is critical for working memory, temporal filtering, and dynamic gain control.

**Nengo Mapping:**
While Nengo's core `Connection` doesn't have an STP parameter out-of-the-box, it can be implemented via a custom synaptic filter or learning rule that modifies the effective transform dynamically based on presynaptic spike history.

**CNL Examples:**
- `A synapse MUST exhibit short-term depression WITH recovery time of 0.1 seconds`
- `The connection from sensory to motor MUST exhibit short-term facilitation`

**Implementation Steps:**
- Add `short_term_plasticity` concept.
- Define a custom Nengo learning rule or synapse object `STP()` in the backend to handle the short-term state variables.
- Enforce invariant: recovery time > 0.

---

## 4. Background Synaptic Noise (Stochasticity)

**Biological Justification:**
In vivo, cortical neurons are subjected to constant, asynchronous bombardment from thousands of synapses, keeping the membrane potential in a fluctuating "high-conductance" state near threshold. This noise is not a nuisance; it is mathematically essential for linearizing the population response (dithering) and enabling probabilistic sampling/inference.

**Nengo Mapping:**
Nengo supports injecting noise directly into ensembles via the `noise` parameter on `nengo.Ensemble`, using processes like `nengo.processes.WhiteNoise()` or `nengo.processes.BrownNoise()`.

**CNL Examples:**
- `The motor population MUST receive background noise WITH variance of 0.1`
- `The sensory neuron MUST operate WITH white noise of 0.05 amplitude`

**Implementation Steps:**
- Add `background_noise` concept to parser.
- Extract noise type and amplitude/variance.
- Apply to the `noise` argument of the corresponding `nengo.Ensemble`.

---

## 5. Distance-Dependent / Spatial Connectivity

**Biological Justification:**
Biological networks are physically embedded in 3D space. The probability of a connection existing, and the axonal delay of that connection, scale heavily with the physical distance between the pre- and post-synaptic neurons. Adding spatial connectivity allows for the generation of biologically realistic topologies (like visual cortex hypercolumns or grid cells) without manually specifying every weight.

**Nengo Mapping:**
Nengo supports this via custom sparse `transform` matrices. We would calculate pairwise distances between neurons (if assigned spatial coordinates) and generate a weight matrix where non-zero entries decay exponentially with distance.

**CNL Examples:**
- `The visual population MUST connect to motor population WITH distance-dependent probability`
- `The sensory population MUST form local connections WITHIN radius of 5`

**Implementation Steps:**
- Add `spatial_connectivity` concept.
- Requires augmenting population declarations to implicitly or explicitly have spatial dimensions/coordinates.
- In generator, build the connection matrix algorithmically based on the radius condition before passing to `nengo.Connection`.

---

## Summary of Execution Requirements

To implement any of these concepts, we will need to update:
1. `neurocnl/cnl/cnl_grammar.md`: Document the new sentences.
2. `neurocnl/cnl/cnl_parser.py`: Add compiled regex patterns for the new concepts.
3. `neurocnl/layers/layer1_invariants.py`: Add physics checks (e.g., `tau_n > 0`, `noise_variance >= 0`).
4. `neurocnl/contracts/neuron_params.py`: Add the extracted parameters to Pydantic contracts.
5. `neurocnl/generation/nengo_generator.py`: Map the validated parameters to Nengo API calls.
