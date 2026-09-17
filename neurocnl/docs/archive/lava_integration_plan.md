# Intel Lava Framework (`lava-nc`) Integration Plan

## 1. Required Lava Abstractions

To map NeuroCNL specifications to the Lava framework, we utilize the following primitives:

*   **Neuron Models (`LIF`):** We use `lava.proc.lif.process.LIF` to represent basic Leaky Integrate-and-Fire neurons.
*   **Synapse Models (`Dense`):** We use `lava.proc.dense.process.Dense` to represent all-to-all connection matrices.
*   **Process / ProcessModel:** NeuroCNL maps SNN components directly to Lava `Process` instantiations (like `LIF` and `Dense`). The Lava compiler automatically maps these to appropriate `ProcessModel` backends (Python, C, or Loihi hardware) during execution based on the run configuration.
*   **Run Configuration:**
    *   `Loihi2SimCfg`: Directs execution to CPU/GPU simulators.
    *   `Loihi2HwCfg`: Directs execution to physical Loihi 2 hardware.
*   **Run Condition:** `RunSteps` is used to specify the simulation duration in timesteps.

## 2. Graph Mapping Strategy

*   **Populations/Ensembles:** Each population maps to a Lava `LIF` process.
    *   `shape`: Set to the number of neurons.
    *   `du`: Controls voltage decay. Maps roughly to $1/\tau_{rc}$ from standard LIF parameterizations, scaled as an integer.
    *   `dv`: Controls current decay.
    *   `vth`: Controls voltage threshold. Maps to an integer based on the IR threshold.
*   **Connections:** Each connection maps to a Lava `Dense` process.
    *   `weights`: Initialized with integer-quantized weights from the SNN graph.
    *   **Wiring:** Connect the pre-synaptic `s_out` port to the `Dense` `s_in` port, and the `Dense` `a_out` port to the post-synaptic `a_in` port.

## 3. Serialization and `lava_io.py`

For round-trip serialisation in `lava_io.py`:

*   **`from_nir` (Export):**
    *   Introduce a `hw_mode` boolean flag to toggle between generating `Loihi2SimCfg` and `Loihi2HwCfg`.
*   **`to_nir` (Import):**
    *   Extract node parameters (`shape`, `du`, `vth`, `weights`) from `LIF` and `Dense` processes.
    *   *Limitation:* Full automated connectivity extraction from a Lava process graph requires inspecting runtime objects, which remains complex. Current simple property extraction allows basic parameter round-tripping.

## 4. Simulation vs. Hardware Paths

We cleanly separate the software simulation path and the physical hardware execution path:

*   Expose a `hw_mode` flag in `export_lava()` and `LavaIO.from_nir()`.
*   If `hw_mode=False`: The generated code imports and configures `Loihi2SimCfg()`.
*   If `hw_mode=True`: The generated code imports and configures `Loihi2HwCfg()`.
*   The generated pipeline exposes this flag to the user to easily switch execution targets.

## 5. Dependency Management

Lava is integrated as an optional dependency. In `pyproject.toml`, it is declared under the `[project.optional-dependencies]` section:
```toml
lava = ["lava-nc>=0.9.0"]
```

## 6. Testing Strategy

*   **Simulation Mode Stubs:** Tests that verify `export_lava(net, hw_mode=False)` and `from_nir(graph, hw_mode=False)` generate Python scripts containing `Loihi2SimCfg`. These can run in CI without Loihi 2 hardware.
*   **Hardware Mode Stubs:** Tests that verify `export_lava(net, hw_mode=True)` and `from_nir(graph, hw_mode=True)` generate Python scripts containing `Loihi2HwCfg`. These also do not require hardware to generate the strings, ensuring our exporter logic is sound.
