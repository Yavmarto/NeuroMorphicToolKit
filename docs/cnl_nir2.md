# Designing a Conceptual Natural Language (CNL) for NIR

This guide outlines the core concepts, structural rules, and architectural tips for building a Conceptual Natural Language (CNL) compiler that outputs Neuromorphic Intermediate Representation (NIR) graphs. The goal of this CNL is to describe networks globally using natural language, abstracting away exact weights and matrices in favor of named identifiers and shapes.

---

## 1. Core Concepts to Translate

To have 100% coverage of the current neuromorphic graphs representable by the NIR specification, the CNL needs to translate *2 structural concepts* and *19 computational primitives*.

### Structural Concepts (Topology)
1.⁠ ⁠*NIRGraph:* The container concept representing the network itself.
2.⁠ ⁠*Edges/Connections:* The directional flow linking the output of one node to the input of another.

### Computational Primitives (Nodes)
•⁠  ⁠*Input / Output*
  * ⁠ Input ⁠: The entry point for data.
  * ⁠ Output ⁠: The exit point for data.
•⁠  ⁠*Neurons / Dynamics*
  * ⁠ IF ⁠: Integrate-and-Fire neuron.
  * ⁠ LIF ⁠: Leaky Integrate-and-Fire neuron.
  * ⁠ LI ⁠: Leaky Integrator.
  * ⁠ CubaLIF ⁠: Current-Based Leaky Integrate-and-Fire neuron.
  * ⁠ CubaLI ⁠: Current-Based Leaky Integrator.
  * ⁠ I ⁠: A simple Integrator neuron.
•⁠  ⁠*Linear Transformations*
  * ⁠ Linear ⁠: A standard linear transformation (weights matrix).
  * ⁠ Affine ⁠: An affine transformation (weights matrix + bias).
  * ⁠ Scale ⁠: Element-wise scaling (diagonal matrix).
•⁠  ⁠*Convolutions*
  * ⁠ Conv1d ⁠: 1-dimensional convolution.
  * ⁠ Conv2d ⁠: 2-dimensional convolution.
•⁠  ⁠*Pooling & Formatting*
  * ⁠ AvgPool2d ⁠: 2D Average pooling.
  * ⁠ SumPool2d ⁠: 2D Sum pooling.
  * ⁠ Flatten ⁠: Flattens spatial dimensions into a 1D vector.
•⁠  ⁠*Others*
  * ⁠ Delay ⁠: Delays the signal for a certain number of timesteps.
  * ⁠ Threshold ⁠: A thresholding operation (useful for surrogate gradients).

### Example CNL Translation
	⁠"Create a Neuromorphic Graph where **Input* of shape (1, 28, 28) connects to a *2D Convolution* (named 'conv1' with output shape 16, 14, 14), which flows into a *CubaLIF* neuron layer, which then *Flattens, routes through a **Linear* layer ('fc1'), and exits via the *Output."

---

## 2. Minimum Requirements & Graph Rules

Based on the ⁠ NIRGraph ⁠ implementation, any script written in the CNL must resolve to meet strict validation rules:

1.⁠ ⁠*Mandatory Elements:*
   - A dictionary of explicitly typed ⁠ nodes ⁠.
   - A list of directional ⁠ edges ⁠ connecting them: ⁠ (source_node_name, destination_node_name) ⁠.
   - At least one uniquely named ⁠ Input ⁠ (entry point) specifying the data shape.
   - At least one uniquely named ⁠ Output ⁠ (exit point).
2.⁠ ⁠*Structural Integrity:*
   - *No Ghost Nodes:* Every node referenced in an edge must exist.
   - *No Duplicate Edges:* You cannot define the exact same connection twice.
3.⁠ ⁠*Type/Shape Consistency:*
   - NIR performs an automated type-checking inference pass. For every edge connecting node A to node B, the output shape of A must mathematically align with the required input shape of B.

---

## 3. Starter Tips & Architectural Quirks

When building the CNL compiler, leverage these features of the NIR architecture:

### Mocking Weights and Matrices
Because the CNL hides specific weight configurations (caring only about named shapes), be aware that NIR nodes require actual NumPy arrays to instantiate (e.g., ⁠ Linear ⁠ requires a ⁠ weight ⁠ array).
*Tip:* Your CNL parser will need a compilation step where it translates named shapes into dummy NumPy arrays (e.g., ⁠ np.zeros(shape) ⁠) so that ⁠ nir.NIRGraph ⁠ can validate the types correctly.

### Utilize the ⁠ metadata ⁠ Dictionary
Every ⁠ NIRNode ⁠ has a ⁠ metadata: Dict[str, Any] ⁠ attribute that is saved during serialization.
*Tip:* You can store your original CNL text, variable names, or custom tags directly inside the NIR nodes using the metadata field. When you export your graph to a ⁠ .nir ⁠ file, your natural language metadata will travel with it.

### Hierarchical Modularity (Subgraphs)
Because ⁠ NIRGraph ⁠ inherits from ⁠ NIRNode ⁠, a node inside a graph can be another graph.
*Tip:* Your CNL should support modular blocks. A user could define a "ResNet Block" in natural language once, and instantiate it multiple times. Under the hood, this translates cleanly into nested ⁠ NIRGraphs ⁠.

### Serialization Flow (HDF5)
The primary way NIR interacts with neuromorphic hardware and simulators (snnTorch, Nengo, Lava, SpiNNaker, etc.) is via HDF5 files (⁠ .nir ⁠).
*Pipeline:*
1.⁠ ⁠Parse CNL text.
2.⁠ ⁠Map concepts to ⁠ nir.* ⁠ nodes and auto-generate dummy arrays.
3.⁠ ⁠Validate using ⁠ graph = nir.NIRGraph(nodes, edges) ⁠.
4.⁠ ⁠Export via ⁠ nir.write("model.nir", graph) ⁠.
5.⁠ ⁠The ⁠ .nir ⁠ file is ready for execution on 9+ supported simulators.

### Input Streams (⁠ NIRData ⁠)
If your CNL allows users to describe input data (e.g., "Provide a 100ms sparse event stream"), you can serialize these descriptions directly alongside the model using the ⁠ nir.write_data(...) ⁠ module, which supports ⁠ TimeGriddedData ⁠ and ⁠ EventData ⁠.

### Stay Framework Agnostic
NIR unifies operations across drastically different chips. Avoid PyTorch-specific or framework-specific terminology in your CNL syntax. Stick to pure mathematical abstractions (e.g., ⁠ CubaLIF ⁠, ⁠ Affine ⁠).
