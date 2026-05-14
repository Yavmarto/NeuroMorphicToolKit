# Ranking of Hardware and Simulation Targets by Implementation Complexity

This document ranks the various neuromorphic backends mentioned in the NeuroMorphicToolKit architecture from **easiest to hardest** to implement. This ranking is based on the inherent technical complexity of building the backend execution layer (API wrapping, compiler passes, and hardware constraints), rather than current development progress.

---

## Tier 1: Pure Software Simulators (Easiest)
These targets run on standard von Neumann hardware (CPUs/GPUs). Integrating them is primarily a software engineering task (API wrapping, Python integration) without the physical constraints of custom silicon.

### 1. Lava CPU
*   **Difficulty:** ⭐
*   **Reasoning:** Pure software implementation on standard CPUs. No strict hardware limits on memory, node count, or routing topology. Supports high-precision floating point, making 1:1 translation from NIR trivial.

### 2. snnTorch / Norse (PyTorch/GPU)
*   **Difficulty:** ⭐⭐
*   **Reasoning:** leverages the standard PyTorch ecosystem. Complexity involves managing the PyTorch execution context, GPU memory management, and implementing surrogate gradient logic for training loops.

---

## Tier 2: Edge Accelerators & Digital ASICs (Moderate)
These are physical hardware devices that are fully digital and synchronous, supported by mature SDKs that abstract low-level hardware details.

### 3. BrainChip Akida
*   **Difficulty:** ⭐⭐⭐
*   **Reasoning:** Requires mapping arbitrary weights to strict 1-bit to 4-bit/8-bit quantization limits. Needs a translation layer to map the NIR graph into Akida's layer-based structure (MetaTF).

### 4. SynSense Xylo / Speck
*   **Difficulty:** ⭐⭐⭐⭐
*   **Reasoning:** Extremely low-power digital SNN chips with severe constraints on memory, time-step quantization, and neuron parameter ranges. Requires aggressive pruning and quantization in the compiler pass.

---

## Tier 3: Large-Scale Asynchronous Digital Neuromorphic (Hard)
These targets involve non-von Neumann architectures and asynchronous communication, requiring the backend compiler to manage complex on-chip routing.

### 5. SpiNNaker 2
*   **Difficulty:** ⭐⭐⭐⭐⭐
*   **Reasoning:** Requires mapping graphs across thousands of ARM cores, building complex routing tables, handling packet loss, and managing a real-time OS on-chip.

### 6. Intel Loihi 2
*   **Difficulty:** ⭐⭐⭐⭐⭐⭐
*   **Reasoning:** Purely asynchronous architecture. Requires explicit neurocore mapping, handling asynchronous spike delivery race conditions, and potentially compiling custom microcode for learning rules.

---

## Tier 4: Analog & Mixed-Signal Neuromorphic (Hardest)
These targets operate using physical physics (voltages/currents), introducing noise, stochasticity, and manufacturing variance.

### 7. BrainScaleS-2
*   **Difficulty:** ⭐⭐⭐⭐⭐⭐⭐
*   **Reasoning:** 
    *   **Mismatch:** Requires complex calibration for physical silicon variance.
    *   **Time Scaling:** Operates 1,000x-10,000x faster than real-time; time constants must be converted to analog biases.
    *   **Stochasticity:** Outputs are inherently noisy, making bit-accurate validation impossible.