# Node-Aware Visualization Upgrade

## Verified Implementation Status (2026-07-04)

**Status: DONE.** All five architectural changes described in this plan exist in the `neurocnl` module (the active copy; a stale duplicate also exists under top-level `Neurosim/`).

- **Backend contracts:** `NodeBulkData` and `BulkSpikeFrame` (dict-of-node payload) are implemented exactly as specced in `neurocnl/neurosim/contracts/design_contracts.py:239-266` (`nodes: dict[str, NodeBulkData]`, `scale_hint: Literal["raster","particle","density"]`).
- **Backend aggregation:** `build_bulk_spike_frame` in `neurocnl/neurosim/app/services/density_aggregator.py:80-99` iterates per-node and returns "a `BulkSpikeFrame` with one `NodeBulkData` per node in playback_nodes" (docstring at line 91).
- **Backend demo generator:** the "Signal Cascade Generator" was implemented as a separate module `neurocnl/neurosim/app/services/topology_cascade_generator.py`, hardcoding the 13-node topology (`CASCADE_TOPOLOGY` tuple, lines 34-49: `input`(784) → `conv1`(4096) → `pool1`(1024) → ... → `output`(10)), reusing `poisson_demo_generator.py`'s tile helpers without modifying that file (kept deliberately separate, per its own docstring).
- **Frontend models:** `nmtk_ui_core/lib/models/bulk_spike_frame.dart` defines `NodeBulkData`/`BulkSpikeFrame` Dart classes that mirror the Python contract 1:1 (comment explicitly cross-references `design_contracts.py`), including a `toVisualizationFrame()` conversion helper (renamed from the plan's `NodeVisualizationData`/`VisualizationFrame` split, but same purpose).
- **Frontend UI:** `neurocnl/frontend/lib/widgets/canvas/canvas_simulation_surface.dart:70-150` implements `_BulkNodeVisualizationPanel`, which spawns one `NeuronRenderer` per active `node_id` (`_renderers.putIfAbsent(entry.key, createNeuronRenderer)`, line 104) and lays them out in a `Stack` of `Positioned` boxes sized to each node's canvas geometry (lines 145-150+), matching the plan's "distinct bounding boxes per node" requirement. A standalone `visualization_panel.dart` file was not created — the panel lives inline in `canvas_simulation_surface.dart` instead.

**Not verified (out of scope for a static audit):** whether `pytest`/mypy actually pass and whether the `/viz-demo` route visually renders multiple distinct blocks at runtime — this requires running the app, which was not done.

---

**Task:** Transition from a flat 1D visualization to a node-aware, layer-separated visualization topology.

---

## Background

Currently, the `PreviewPlayback` and the resulting visualization shaders flatten the entire network of neurons into a single, massive 1D array. All structural meaning—the layers, nodes, and shapes—is lost on the screen, resulting in a single monolithic "random" looking box.

To make the visualization readable and reflective of the actual `CanvasGraph`, the data pipeline and the renderers must become **Node-Aware**.

---

> [!WARNING]
> ## User Review Required
> **Contract Breaking Change:** This plan requires modifying `BulkSpikeFrame` in `design_contracts.py`. The backend and frontend must be updated simultaneously, or the WebSocket streaming will fail to deserialize. Do you approve of switching the binary payload to the dictionary format proposed below?

---

## Architectural Changes

Instead of sending one massive binary blob for the entire graph, the backend will group spikes and density maps by `node_id`. The frontend will spawn a separate renderer instance (Fragment Shader or Wgpu Surface) for each active node in the graph, laying them out visually to match the network topology.

### 1. Backend Contracts (`design_contracts.py`)

Replace the flat arrays in `BulkSpikeFrame` with a dictionary mapping `node_id` to its isolated data.

```python
class NodeBulkData(BaseModel):
    """Compact spike and density payload for a single canvas node."""
    node_id: str
    data: list[float]  # Alternating [local_neuron_idx, time_ms]
    density_grid: list[float]
    grid_w: int
    grid_h: int
    neuron_count: int

class BulkSpikeFrame(BaseModel):
    """Network-wide bulk payload, partitioned by node."""
    node_data: dict[str, NodeBulkData] = Field(default_factory=dict)
    scale_hint: Literal["raster", "particle", "density"] = "raster"
```

### 2. Backend Aggregation (`density_aggregator.py`)

- **[MODIFY]** `build_bulk_spike_frame`: Instead of ignoring node boundaries, it will iterate over the `node_id` keys in the raw spike data.
- It will compute `density_grid` and `data` arrays locally for *each* node, returning a populated dictionary of `NodeBulkData` blocks.

### 3. Backend Demo Generator (`poisson_demo_generator.py`)

- **[MODIFY]** `generate_demo_frame`: We will completely replace the independent, random Poisson generation (which looks like television static) with a structured **Signal Cascade Generator**.
- The generator will hardcode the specific 13-layer topology you provided (`input` → `0` → `1` ... → `12` → `output`), sizing the mock data blocks precisely to match your convolution, pooling, and affine dimensions (e.g., node 1 gets 4,096 neurons, node 10 gets 256, node 12 gets 10).
- **Simulated Propagation:** Instead of random flashing, the generator will simulate a rhythmic "wave" of activity. A burst of spikes will trigger in the `input` node, followed by a delayed wave of activity propagating sequentially through nodes `0` to `12` over a 50-100ms window. This will visually look like real data flowing through the network layers.

### 4. Frontend Models (`renderer_interface.dart`)

The Dart payload must mirror the Python contract exactly.

```dart
class NodeVisualizationData {
  final String nodeId;
  final Float32List spikePositions;
  final Float32List densityGrid;
  final int gridW;
  final int gridH;
  final int neuronCount;
}

class VisualizationFrame {
  final Map<String, NodeVisualizationData> nodes;
  final double simulationTimeMs;
  final VisualizationScale scale;
}
```

### 5. Frontend UI (`visualization_panel.dart`)

- **[MODIFY]** The `VisualizationPanel` will no longer host a single monolithic `NeuronRenderer`.
- Instead, it will use a `Wrap`, `Flex`, or custom `Stack` layout mapped to the current `CanvasGraph`.
- For each `NodeVisualizationData` entry in the `VisualizationFrame.nodes` map, it will instantiate a dedicated `NeuronRenderer` scoped strictly to that node's geometry.
- This means you will see distinct bounding boxes (e.g., a small box for a 10-neuron output layer, a massive box for a 4,096-neuron convolutional layer).

---

## Verification Plan

1. **Contracts:** Run Python `pytest` and mypy against `design_contracts.py` to ensure the nested model serializes performantly.
2. **Demo Endpoint:** Launch the `/viz-demo` route. The 100k demo should now display multiple distinct visual blocks (e.g., 3 separate particle fields representing 3 mock layers) instead of one giant square.
3. **Integration:** Connect a real network in the Studio. Verify that a block appears in the preview panel exclusively for nodes that actually emitted spikes in that frame.
