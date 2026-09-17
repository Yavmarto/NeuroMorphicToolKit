# [CNL-053] SynSense Rockpool — Model Converter Integration Plan

## 1. Mapping NeuroCNL's SNN Graph to Rockpool Constructs

NeuroCNL compiles sentences into an SNN graph consisting of neuron populations (Ensembles), connections (Weights/Transforms), and probes. Rockpool represents SNNs natively using the `Module` API, with compositional combinators like `Sequential`.

*   **Populations/Ensembles**: Map to discrete `Module` layers such as `LIF` or `LIFTorch`. Since Rockpool layers are intrinsically vectorized, an ensemble of size $N$ translates directly to a module initialized with `shape=(N,)` or simply processing inputs with an output feature dimension of $N$.
*   **Connections (Synapses)**: Map to connection modules such as `Linear` or `LinearTorch` for static weights. Synaptic dynamics (e.g., low-pass filtering) are handled either via integrated synapse modules (like `ExpSyn`) or directly baked into the neuron model if using combined `ExpSynLIF`.
*   **Graph Assembly**: NeuroCNL networks are generally directed graphs but not strictly sequential. To map a generic NeuroCNL graph, we will use Rockpool's functional API or graph-based networks (`rockpool.nn.combinators.GraphModule` if available, or composing them natively in a custom `TorchModule`). For purely feed-forward paths, `Sequential` combinator seamlessly chains `Linear` -> `LIF` modules.

## 2. Key Rockpool Modules for Neuromorphic Hardware

Rockpool provides both raw NumPy (native) and PyTorch backends. For hardware deployment (e.g., via the Xylo or Dynap-CNN chips eventually, though sinabs handles CNNs), the core modules include:

*   **`Linear` / `LinearTorch`**: Defines the weighted dense connections between layers. This strictly maps to `nengo.Connection(..., transform=Matrix)`.
*   **`LIF` / `LIFTorch` / `LIFBitshift`**: The standard Leaky Integrate-and-Fire neuron. Parameters include time constant (`tau_mem`), threshold (`v_thresh`), and rest potential (`v_rest`). `LIFBitshift` is particularly important for hardware targets that require power-of-two (bit-shift) quantizations for decay.
*   **`ExpSyn` / `ExpSynTorch`**: Implements exponential synaptic current decay (first-order lowpass filter), corresponding to Nengo's `nengo.Lowpass` synapse.

## 3. Import/Export Converter Design: `neurocnl ↔ rockpool`

The conversion strategy will utilize **NIR (Neuromorphic Intermediate Representation)** as the pivot format, adhering to NeuroCNL's existing architecture (`pivot.py`).

*   **`to_nir` (Rockpool -> NIR)**:
    We will leverage `nir.write` or directly iterate over a Rockpool `Module` (especially `TorchModule`s) to extract the computational graph and convert it to NIR primitives (`nir.LIF`, `nir.Linear`, `nir.Input`, `nir.Output`). Since Rockpool's torch backend is fully compatible with standard computational graphs, extracting weights and time constants is straightforward.
*   **`from_nir` (NIR -> Rockpool)**:
    Implementing the `FrameworkIO` protocol in `rockpool_io.py`. We will traverse the `nir.NIRGraph`. Nodes map to Rockpool equivalents (e.g., `nir.LIF` -> `LIFTorch`, `nir.Linear` -> `LinearTorch`). The edges of the NIR graph will dictate how these modules are composed.
*   **`export_to_rockpool` (Nengo -> Rockpool directly via NIR)**:
    For ease of use, `rockpool_exporter.py` will wrap the sequence: `Nengo -> export_to_nir -> rockpool_io.from_nir -> Rockpool`.

## 4. Surfacing Rockpool's Training Utilities (BPTT, e-prop)

One of Rockpool's primary strengths is its PyTorch integration, enabling training with Surrogate Gradients (BPTT).

*   By exporting a NeuroCNL SNN into a Rockpool `TorchModule` network, the model inherently supports PyTorch's `autograd`.
*   We can expose a helper function in NeuroCNL's training utility that accepts a generated Rockpool module, attaches a standard loss function (e.g., `torch.nn.CrossEntropyLoss` on spike counts or membrane potentials), and an optimizer.
*   The `BackendCapabilityProfile` for Rockpool will register `learning_rules={"bptt", "surrogate_gradient"}`.

## 5. Relationship and Overlap with Sinabs Converter (CNL-052)

**Overlap**: Both Rockpool and Sinabs are SynSense SDKs targeting their neuromorphic hardware. Both use PyTorch under the hood.
**Delineation**:
*   **Sinabs** is strictly optimized for Vision/CNN topologies, focusing on converting existing PyTorch CNNs (via `nn.Conv2d`, `nn.MaxPool2d`) to SNNs using weight quantization and parameter transfer.
*   **Rockpool** is for general-purpose signal processing (audio, sequence modeling), supporting recurrent networks, varied neuron models, and training SNNs from scratch using surrogate gradients.
*   **Mitigation**: NeuroCNL will use **Sinabs** primarily for image-based/convolutional pipelines and pre-trained CNN weight quantization. NeuroCNL will use **Rockpool** for recurrent graphs, generic Nengo Ensembles, and sequential data processing. The quantization logic for dense layers in Rockpool will remain separate from the CNN-focused quantization in Sinabs. Both will share the `[synsense]` extra dependency.

## 6. Dependency Declaration

Added to `pyproject.toml` under `[project.optional-dependencies]`:

```toml
synsense = ["rockpool>=2.8.0", "sinabs"]
```
*(Assuming `sinabs` is added in CNL-052. For this PR, we ensure `rockpool>=2.8.0` is in the `synsense` extra).*
