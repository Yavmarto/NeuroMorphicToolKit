# Developer Tooling
> Addresses the gap: no equivalent of PyTorch exists for building and debugging SNN models

---

## 1. Visual Network Editor

**Description**
Build SNN architectures graphically by placing and connecting neuron populations, then export to code.

**Target surfaces:** Desktop app

**Tags:** `GUI` `codegen` `visual`

### Spec
- Canvas with drag-and-drop neuron population nodes: LIF, ALIF, conductance-based, and custom types
- Draw synaptic connections; set weight distributions, delays, and plasticity rules in a side panel
- Live parameter validation — highlights configurations that exceed hardware constraints for the selected target
- One-click export to: NIR, Lava, PyNN, Nengo, or Brian2 Python code
- Import an existing code file or NIR file to render it as a visual graph for inspection

---

## 2. Spike Train Visualizer

**Description**
Inspect simulation output: raster plots, firing rates, membrane potentials, and population activity over time.

**Target surfaces:** Desktop app + Python library

**Tags:** `raster` `membrane` `analysis`

### Spec
- Accepts spike train data in common formats: NumPy arrays, Neo, PyNN RecordingArray
- Panels: raster plot, PSTH (peri-stimulus time histogram), membrane potential trace, synchrony measure
- Time-scrubber to zoom into specific windows; highlight individual neurons on click
- Compare two simulation runs side by side (e.g. before vs. after a parameter change)
- **Python:** `viz.raster(spikes)`, `viz.membrane(v_traces)` — returns a matplotlib Figure, or opens in the desktop app if running

---

## 3. Parameter Sweep Tool

**Description**
Systematically explore how neuron or network parameters affect behaviour, without writing nested for-loops.

**Target surfaces:** Desktop app + Python library

**Tags:** `sweep` `hyperparameter` `grid-search`

### Spec
- Define a parameter grid (e.g. threshold: 0.1–1.0, tau: 5–50 ms) in a YAML config file or via the desktop GUI
- Parallelises runs across CPU cores; optional GPU acceleration for large sweeps
- Results stored in a structured SQLite database; queryable from Python
- **Desktop:** heatmap of any two parameters vs. a chosen metric; export winning configuration to file
- **Python:** `sweep.run(model_fn, grid, metric="accuracy")` → returns a ranked DataFrame
