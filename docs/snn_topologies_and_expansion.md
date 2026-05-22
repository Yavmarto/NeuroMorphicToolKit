# SNN Topologies & Visual Expansion Blueprint

This document explains what is meant by **Simple Reflex Topologies** in the current **NeuroMorphicToolKit (NMTK)** implementation, details the advanced topologies required for real-world neuromorphic applications, and provides a development blueprint for expanding the visual compilation system to support arbitrary network structures.

---

## 1. Understanding Simple Reflex Topologies

In the current implementation of NMTK (specifically within the `Neurosim` canvas and `neurocnl` compilers), the pipeline is gated to support **Simple Reflex Topologies**. 

```
┌──────────────────┐               ┌────────────────┐               ┌────────────────┐
│   Input Stream   │ ────────────► │ Sensory Neurons│ ────────────► │ Motor Neurons  │
│  (Slip Velocity) │  (Rate Coded) │ (LIF Population)│ (Static Syn) │ (LIF Population)│
└──────────────────┘               └────────────────┘               └────────────────┘
```

This structural topology is modeled after a basic monosynaptic biological reflex arc:
* **Strictly Feedforward:** Data flows in one direction: `Sensory (Input) ──► Motor (Output)`. There are no hidden intermediate layers, lateral connections, or loops.
* **Single Connection Path:** A single connection projection translates spikes from the sensory pool directly to the motor pool.
* **Static Synapses:** Synaptic weights are modeled as uniform, static scalers (e.g., a connection weight of `1.0`) that do not dynamically change over time unless adjusted by a localized learning rule (such as the specific PES sleep wrapper).
* **Application Focus:** This is optimized for simple closed-loop reflexive control—such as detecting a physical slip and generating a corresponding immediate grip force boost.

---

## 2. Advanced Topologies Needed for Neuromorphic R&D

To expand beyond basic reflexes and enable human-like cognitive tasks, robotic control, and temporal pattern processing, an SNN compiler must support three major classes of advanced topologies:

### A. Deep Feedforward Spiking Networks (Deep SNNs)
```
  Sensory Layer ──► Hidden Layer 1 ──► Hidden Layer 2 ──► Motor/Output Layer
```
* **What they are:** Multi-layered spiking neural networks featuring intermediate convolutional or dense layers.
* **Use Cases:** Event-based vision processing (e.g., routing spikes from a Prophesee DVS event camera through spiking convolutional layers to classify gestures, track objects, or recognize obstacles).

### B. Recurrent Spiking Neural Networks (RSNNs)
```
                        ┌─── Lateral Loops ───┐
                        ▼                     │
  Sensory Layer ──► Spiking Reservoir (Recurrent Pools) ──► Motor Layer
```
* **What they are:** Networks with cyclic connection loops. Neurons connect back to themselves, to other neurons within the same layer (lateral loops), or feed spikes backward to previous layers.
* **Use Cases:** 
  * **Temporal Sequence Processing:** Tracking changes over time (like continuous speech recognition or radar signal tracking).
  * **Central Pattern Generators (CPGs):** Generating rhythmic, self-sustaining motor signals for walking, swimming, or flying robots.
  * **Working Memory:** Retaining short-term neural states without persistent external inputs.

### C. Lateral Inhibition & Winner-Take-All (WTA) Networks
```
  Neuron A  ◄─── Inhibitory Synapse ───►  Neuron B
```
* **What they are:** Local neural populations where active neurons emit inhibitory signals to silence their neighbors.
* **Use Cases:** Feature selection, noise filtering, and decision-making. Whichever neuron fires fastest suppresses other interpretations of the data, stabilizing the output.

---

## 3. Implementation Plan for Arbitrary Topology Support

To move NMTK from a hardcoded reflex compiler to a generic, arbitrary SNN engine, four specific layers of the system must be updated:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. VISUAL CANVAS (Neurosim UI)                                              │
│    Migrate from hardcoded two-column panels to a Flutter Node-Graph Editor. │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. DSL PARSER (neurocnl Backend)                                            │
│    Expand the CNL parser to support multi-layer and recurrent syntax.       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. GRAPH COMPILER (CNL -> NIR)                                              │
│    Construct a Directed Graph mapping CNL relations directly to NIR.        │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. HARDWARE DRIVERS (Neurochip)                                             │
│    Enable target backends to map generic NIR graphs into physical registers.│
└─────────────────────────────────────────────────────────────────────────────┘
```

### Stage 1: Visual Canvas (Flutter UI)
* **The Current State:** The frontend visually lays out a static sensory panel and motor panel.
* **The Expansion:** 
  * Integrate a generic Flutter node-graph framework (e.g., `graphview` or custom canvas painters).
  * Enable users to dynamically drag-and-drop layer blocks (LIF populations, input sources, synapse matrices).
  * Allow dragging connection lines between output ports and input ports to visually establish feedback and lateral pathways.

### Stage 2: DSL Parser (`neurocnl`)
* **The Current State:** The grammar parses specific, reflex-oriented sentences.
* **The Expansion:** Support arbitrary connection and topological specifications in Controlled Natural Language:
```text
The sensory population has 100 LIF neurons.
The hidden population has 250 LIF neurons.
The sensory population connects to the hidden population via excitatory synapses.
The hidden population connects to itself via lateral inhibitory synapses.
The hidden population connects to the motor population.
```

### Stage 3: Graph Compiler (`CNL ──► IR ──► NIR`)
* **The Current State:** The compiler expects a fixed input structure and maps it directly to a pre-defined NIR shape.
* **The Expansion:** 
  * Parse CNL rules into an internal directed graph structure of nodes and edges.
  * Use the **NIR (Neuromorphic Intermediate Representation)** library's native support for complex structures:
    * Map populations to `nir.LIF` or `nir.ALIF` nodes.
    * Map feedforward connections to `nir.Linear` nodes.
    * Map recurrent loops utilizing standard `nir.Delay` and nested edge lists.
  * Output a comprehensive, unified `.nir` graph file containing arbitrary topologies.

### Stage 4: Hardware Compilation (`Neurochip`)
* **The Current State:** Translators expect standard reflex inputs.
* **The Expansion:** Update compiler backends to read a generic NIR graph:
  * **Teensy Driver:** Traverse the NIR graph topological sort and emit static C++ arrays representing intermediate arrays and recurrent state-buffers.
  * **Akida Driver:** Map multi-layer NIR graph sequences directly onto BrainChip Akida sequential layers.
  * **PYNQ FPGA Driver:** Map cyclic connections to localized hardware-register loops within the FPGA fabric overlay.
