# SpiNNaker2 Integration Plan

## 1. Key API Differences: py-spinnaker2 vs PyNN-SpiNNaker 1

The transition from the legacy SpiNNaker 1 backend (`pyNN.spiNNaker`) to the new SpiNNaker 2 backend (`py-spinnaker2`) entails a shift from the PyNN abstraction layer to a custom, more direct API provided by `spinnaker2.snn`.

*   **Initialization & Network Scope:**
    *   *Legacy (PyNN):* Relies on a global `sim.setup()` and procedural network construction.
    *   *SpiNNaker 2:* Uses an object-oriented network container: `net = snn.Network()`. Components are added explicitly via `net.add(pop, proj)`.

*   **Populations:**
    *   *Legacy:* `sim.Population(size, sim.IF_curr_exp(...))` using standardized PyNN cell models.
    *   *SpiNNaker 2:* `snn.Population(size, neuron_model="lif", params={...})`. It accepts a plain dictionary for model parameters (`tau_m`, `tau_refrac`, `v_thresh`, etc.) and a specific string identifier (`"lif"`, `"spike_list"`, etc.) for the model type. Variables to record are passed via a list to the `record` argument.

*   **Projections / Connectivity:**
    *   *Legacy:* Uses Connector objects (e.g., `sim.AllToAllConnector()`) and defined synapse types (`sim.StaticSynapse(...)`).
    *   *SpiNNaker 2:* Connections are explicitly passed as a 2D list array of the form `[pre_idx, post_idx, weight, delay]` to `snn.Projection(pre=pop, post=pop, connections=conns)`.

*   **Execution:**
    *   *Legacy:* `sim.run(time)` followed by `sim.end()`.
    *   *SpiNNaker 2:* Hardware execution is orchestrated by a dedicated chip object: `hw = hardware.SpiNNaker2Chip()`, followed by `hw.run(net, timesteps)`.

*   **Result Retrieval:**
    *   *Legacy:* `pop.get_data()` retrieving a neo Block.
    *   *SpiNNaker 2:* Returns basic dictionaries via `pop.get_spikes()` (mapping neuron ID to a list of spike times) and `pop.get_voltages()`.

## 2. Parallel Coexistence with SpiNNaker 1

To maintain backward compatibility, the existing `spinnaker_exporter.py` remains untouched.
The new integration introduces `neurocnl/export/spinnaker2_exporter.py`, which is wholly self-contained and avoids polluting the `nengo` or `PyNN` namespace.
Capabilities for both targets are registered separately in `neurocnl/backends/capabilities.py` (as `"spinnaker"` and `"spinnaker2"`), allowing the pipeline validator to handle both pathways according to the requested export target.

## 3. Mapping NeuroCNL SNN Graph to SpiNNaker2

NeuroCNL compiles English specifications into `nengo.Network` objects. The exporter converts these objects into the `spinnaker2.snn` graph representation:

*   **Ensembles to Populations:** Iterate over `nengo.Network.all_ensembles`. Each ensemble is instantiated as an `snn.Population` with `neuron_model="lif"`. Physical units (like `tau_rc` and `tau_ref` from `nengo.LIF`) are converted from Nengo's native seconds to SpiNNaker2's native milliseconds.
*   **Connections to Projections:** Iterate over `nengo.Network.all_connections`. If both `pre` and `post` target known Ensembles, an `snn.Projection` is generated. The connection matrix (derived from the `transform` attribute) is unrolled into the required `[pre, post, weight, delay]` tuple array format.

## 4. Real-time Execution & Result Retrieval Workflow

1.  **Network Setup:** `spinnaker2.snn.Network` encapsulates all the populations and projections.
2.  **Mapping & Running:** `spinnaker2.hardware.SpiNNaker2Chip().run(net, timesteps)` maps the logical graph to the physical cores on the chip, compiles necessary binaries, and initiates the execution loop.
3.  **Extraction:** Once complete, data is extracted from the chip SRAM/DRAM into python variables.
4.  **Formatting:** The data dictionaries obtained via `get_spikes()` and `get_voltages()` are passed into `neurocnl/converter/spinnaker2_io.py` to standardize outputs (e.g., aligning timestamps and neuron index dimensions) so they match the expected internal simulation format.

## 5. Dependency Declaration

Added to `pyproject.toml` under `[project.optional-dependencies]`:
```toml
spinnaker2 = ["py-spinnaker2 @ git+https://gitlab.com/spinnaker2/py-spinnaker2.git"]
```
Because `py-spinnaker2` is hosted in a private repository, it points directly to the GitLab URL. Users will need proper SSH keys or tokens configured locally to install it.

## 6. Testing Strategy (Simulation vs Hardware)

*   **Software Simulation Tests (`test_spinnaker2_exporter.py`):** Asserts that the exporter correctly transcribes a `nengo.Network` into the expected `spinnaker2.snn` python string template. These tests do not require `py-spinnaker2` to be installed. They simply verify code generation (Regex or string matching).
*   **Brian2 Simulation Backend:** For integration tests without hardware, `py-spinnaker2` provides a software emulator (`spinnaker2.brian2_sim`). In the future, this can be used to test small SNNs in CI pipelines.
*   **Hardware Required Tests:** Any tests invoking `hardware.SpiNNaker2Chip()` natively must be marked (e.g. `@pytest.mark.hardware`) so they are skipped in generic CI and only executed on dedicated build servers with direct connection to the SpiNNaker2 boards.
