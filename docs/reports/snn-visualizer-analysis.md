# SNN Simulation Visualizer: Comparative Analysis Report

> **Date:** 2026-05-17
> **Scope:** Analyze three existing SNN visualization/simulation tools to inform the design of a custom SNN simulation visualizer for the NeuroMorphicToolkit (NMTK) ecosystem.
> **Repositories Analyzed:**
> - [SNNtrainer3D](https://github.com/jurjsorinliviu/SNNtrainer3D) — 3D architecture visualization + training
> - [NetPyNE](https://github.com/suny-downstate-medical-center/netpyne) — Biological neuronal network simulation & analysis
> - [RAVSim](https://github.com/Rao-Sanaullah/RAVSim) — Runtime analysis & visualization simulator

---

## 1. Executive Summary

Our goal is to build an SNN simulation visualizer that shows **how data (spikes) flow through a spiking neural network** in real time. It does **not** need to be 3D, though 3D may be useful for architecture overview. The visualizer will live inside the **NMTK** ecosystem, likely as part of or adjacent to the existing **NeuroStudio / Neurosim canvas** (`/canvas` route).

This report analyzes three open-source projects, extracts their most valuable ideas, and recommends a feature set and architecture for our own visualizer.

**Key Takeaway:** The most impactful visualizer combines **NetPyNE's analytical depth** (spike rasters, traces, connectivity matrices) with **SNNtrainer3D's intuitive architecture view** (color-coded weights, interactive layers) and adds **real-time spike propagation animation** — something none of the three do well out of the box.

---

## 2. Repository Analysis

### 2.1 SNNtrainer3D

**What it is:** A web-based training tool for Spiking Neural Networks with an interactive 3D architecture visualization. Published research software (Appl. Sci. 2024).

**Stack:** Flask (Python) + Three.js (WebGL) + PyTorch/snnTorch

**Visualization Approach:**

| Aspect | Implementation |
|--------|---------------|
| **Geometry** | 3D layers arranged along X-axis. Nodes = spheres, connections = lines, layer boundaries = white boxes |
| **Weight Encoding** | Green = positive weights, Red = negative weights, Opacity = `abs(weight)`. Very intuitive |
| **Interactivity** | OrbitControls: zoom, rotate, pan. Camera auto-centers based on network depth |
| **Node Colors** | Input = green, Hidden = red, Output = blue. Optional toggle to hide nodes for performance |
| **Updates** | Post-training only (not real-time). Weights fetched via `/get_weights` endpoint |
| **Training Metrics** | Loss, accuracy, precision, recall, F1, confusion matrix, FLOPs count |

**What it does well:**
- **Intuitive weight visualization** — the color/opacity encoding makes weight structure immediately visible.
- **Clean separation** — backend trains, frontend visualizes. JSON API between them.
- **Layer editing UI** — add/remove hidden layers dynamically with immediate visual feedback.
- **Performance-aware** — optional node rendering; post-training weight updates avoid frame drops.

**Where it falls short for *simulation* visualization:**
- **No real-time spike propagation** — weights update only after training completes. You cannot see a spike travel from input→hidden→output.
- **No membrane potential display** — nodes are static colored spheres, not showing voltage traces.
- **Only fully-connected layers** — no conv, recurrent, or skip connections.
- **Scalability ceiling** — >1000 nodes and the naive `O(n²)` line rendering between layers will choke.

**Code snippet — weight-to-color mapping (from `nn_visualize.js`):**

```javascript
const weight = weights[node2index][node1index];
const opacity = Math.abs(weight);
const material = new THREE.LineBasicMaterial({
    color: weight > 0 ? 0x00ff00 : 0xff0000,
    transparent: true,
    opacity: opacity
});
```

---

### 2.2 NetPyNE

**What it is:** A high-level Python interface to the NEURON simulator for biologically realistic neuronal networks. Very mature (4,800+ commits, 169 stars), backed by NIH/NSF/Human Brain Project.

**Stack:** Python + NEURON + Matplotlib/Bokeh + Geppetto (web GUI: React/JavaScript)

**Visualization Approach:**

NetPyNE is not an SNN *trainer* in the machine-learning sense; it is a *biophysical simulation* tool. Its visualization suite is extremely comprehensive:

| Visualization Type | Description |
|---------------------|-------------|
| **Raster Plots** | Spike times vs. neuron index, colored by population. Essential for seeing network-wide activity |
| **Spike Histograms** | Population firing rates over time |
| **Traces** | Membrane voltage (`V`), ionic/synaptic currents, conductances, molecular concentrations |
| **2D Network Layout** | Top-down (X-Y) view of cell positions and connections |
| **3D Morphology Viewer** | State-of-the-art neuron morphology viewer with color-coded variables (e.g., synapse count) |
| **Connectivity Matrix** | Heatmap of connection probability/weight/number between populations |
| **LFP / EEG / CSD** | Local field potentials, electroencephalogram signals, current source density |
| **Rate PSD & Spectrograms** | Frequency-domain analysis of population activity |
| **Granger Causality / Transfer Entropy** | Information-theoretic directed connectivity measures |

**Web GUI (NetPyNE-UI):**
- Built on **Geppetto** platform (open-source neuroscience visualization infrastructure)
- React-based frontend synchronized bidirectionally with a Python Jupyter kernel
- Two modes: **Edit** (define network) and **Explore** (visualize & simulate)
- 3D representation with population controls (show/hide, color, zoom to cell)

**What it does well:**
- **Production-grade analysis** — every plot a neuroscientist could want is already implemented.
- **Declarative specification** — define a network in a Python dict, instantiate and simulate.
- **Parallel simulation support** — scales to very large networks via MPI.
- **Rich data export** — pickle, JSON, Matplotlib figures.

**Where it falls short for *our* use case:**
- **Biological, not machine-learning SNNs** — It models ion channels and dendritic trees, not typically the abstract LIF neurons used in ML-oriented SNNs.
- **Heavy dependency stack** — Requires NEURON, which is non-trivial to install.
- **No "flow" animation** — Like SNNtrainer3D, it does not animate spikes moving through the network.
- **GUI is generic neuroscience** — Not tailored to the "design → train → deploy" loop we want.

**Code snippet — plotter framework (from `plotRaster.py`):**

```python
# NetPyNE uses a MetaFig / ScatterPlotter abstraction that wraps matplotlib
scatterData = {
    'x': spkTimes,      # spike times
    'y': spkInds,       # neuron indices
    'c': spkColors,     # population colors
    'marker': '|',
    'linewidth': 2
}
rasterPlotter = ScatterPlotter(data=scatterData, kind='raster', ...)
```

---

### 2.3 RAVSim

**What it is:** A LabVIEW-based "Run-time Analysis and Visualization Simulator" for SNN models. Published in *Frontiers in Computational Neuroscience* and *Int. J. Neural Systems*.

**Stack:** LabVIEW (graphical programming) — requires LabVIEW Runtime 2021+

**Visualization Approach:**

| Aspect | Implementation |
|--------|---------------|
| **Runtime VI** | Interactive front panel showing WTA (Winner-Take-All) networks with three connectivity modes: fully connected, source≠target, source==target |
| **Mixed Signal Plot** | Combined view of neuron spike trains and analog signals for understanding communication |
| **Image Classification VI** | Displays classification accuracy alongside a **weight visualization** (similar to SNNtrainer3D) |
| **Dataset Preprocessing VI** | Custom dataset creation from images with configurable pixel quality |
| **Model Comparison** | Side-by-side parameter adjustment and comparative results for different SNN models |

**What it does well:**
- **Runtime parameter tweaking** — Change neuron parameters while the simulation is running and see immediate effects.
- **Model comparison** — A/B testing different configurations is built into the UI.
- **Mixed signal plots** — Seeing spikes and analog traces together helps understand the hybrid nature of SNNs.

**Where it falls short:**
- **LabVIEW lock-in** — Not web-friendly, not scriptable, not integratable into a modern Python/JS stack.
- **Closed runtime dependency** — Users must install NI LabVIEW Runtime.
- **Limited visual depth** — Mostly 2D front-panel widgets; no true network graph visualization.
- **No open web interface** — Cannot be embedded into NMTK's Flutter/WebView architecture.

---

## 3. Synthesis — What We Should Borrow

### 3.1 From SNNtrainer3D

| Feature | Rationale | Effort |
|---------|-----------|--------|
| **Color-coded weights** (green=positive, red=negative, opacity=|weight|) | Immediately communicates learned structure. Proven intuitive in their user study | Low |
| **Interactive 3D layer view** | Useful for architecture overview, especially for non-expert users | Medium |
| **OrbitControls-style navigation** | Standard, user-friendly camera control | Low |
| **Toggle for node visibility** | Performance safeguard for large networks | Low |
| **Backend/frontend JSON API** | Clean architecture we already use in NMTK | N/A (already adopted) |

### 3.2 From NetPyNE

| Feature | Rationale | Effort |
|---------|-----------|--------|
| **Raster plot** | The canonical way to view population spike activity. Non-negotiable for SNN tools | Medium |
| **Membrane potential traces** | Shows *why* a neuron spiked (did it reach threshold?). Critical for debugging | Medium |
| **Connectivity matrix heatmap** | Alternative view of weight structure; good for large dense networks | Medium |
| **2D network layout** | Simpler than 3D for everyday use; faster to render | Low |
| **Population-based coloring** | NetPyNE colors by population; we can adapt this for layer types | Low |
| **Bokeh/Matplotlib dark theme** | Their dark theme (`#434343` background) is professional and reduces eye strain | Low |

### 3.3 From RAVSim

| Feature | Rationale | Effort |
|---------|-----------|--------|
| **Runtime parameter adjustment** | Change thresholds, time constants, etc., while simulating and see live feedback | Medium |
| **Model comparison mode** | Compare two SNN configurations side-by-side | Medium |
| **Mixed signal view** | Show both spike raster and analog traces (voltage, current) in one pane | Medium |

---

## 4. Recommended Feature Set for Our Visualizer

Based on the above synthesis and the fact that **NMTK already has a Neurosim canvas in NeuroStudio**, we recommend the following prioritized feature list.

### 4.1 Must-Have (MVP)

These are the minimum features needed for a useful SNN simulation visualizer:

1. **Architecture View (2D primary, 3D optional)**
   - Nodes = neurons, edges = synapses
   - Layer-based layout (input → hidden → output)
   - Color-coded weights (borrowed from SNNtrainer3D)
   - Zoom, pan, drag-to-rearrange

2. **Real-Time Spike Propagation Animation**
   - This is the *defining* feature for a "simulation visualizer."
   - When a neuron fires, a "pulse" (glowing dot or line flash) travels along its outgoing edges to post-synaptic neurons.
   - Speed should be adjustable (slow-mo to real-time).
   - This is **not** well-implemented in any of the three analyzed repos — it is our opportunity to differentiate.

3. **Spike Raster Plot**
   - Borrowed from NetPyNE.
   - X-axis = time, Y-axis = neuron index (grouped by layer).
   - Each dot = one spike.
   - Should be linked to the architecture view: click a spike → highlight the neuron.

4. **Membrane Potential Traces**
   - Borrowed from NetPyNE.
   - Select a neuron (or multiple) and see its `V(t)` over time.
   - Show threshold line.
   - Overlay synaptic currents if possible.

5. **Play / Pause / Step Controls**
   - Standard simulation playback.
   - Step-forward by one time step or one spike.
   - Scrubber to jump to any point in the recorded simulation.

### 4.2 Should-Have (Next Release)

6. **Live Parameter Tweak Panel**
   - Borrowed from RAVSim.
   - Sliders for: `tau_mem`, `tau_syn`, `v_thresh`, `v_reset`, `refractory_period`.
   - Changes apply on next simulation run (or live if backend supports it).

7. **Weight Evolution Timeline**
   - Show how a single weight (or layer-average) changes over training or plasticity.
   - Small sparkline next to each connection or in a side panel.

8. **Population Firing Rate Histogram**
   - Per-layer bar chart showing average firing rate over a sliding window.

9. **Connectivity Matrix View**
   - Borrowed from NetPyNE.
   - Heatmap of all weights between two selected layers.
   - Toggle between view modes: weight value, connection count, spike count.

10. **Input Stimulus Overlay**
    - If the SNN is processing e.g. an image or audio, show the raw input alongside the network.
    - For images: highlight pixels that are currently spiking (if using a rate-coded input).

### 4.3 Nice-to-Have (Future)

11. **3D Architecture Overview**
    - Full Three.js view (like SNNtrainer3D) for presentations and architecture exploration.
    - Toggle between 2D and 3D.

12. **STDP Animation**
    - Visualize spike-timing-dependent plasticity: when pre and post spikes are close in time, flash the connection and show weight change direction.

13. **Export to Video / GIF**
    - Record the animation for papers/presentations.

14. **Side-by-Side Comparison Mode**
    - Borrowed from RAVSim.
    - Load two different model checkpoints or parameter sets and compare their spike patterns.

15. **Multi-Scale Zoom**
    - Zoom out to see population-level statistics; zoom in to see individual neuron traces.

---

## 5. Architecture Recommendation

Given that NMTK is a **Flutter desktop app** with embedded **WebViews** for module UIs, and the **Neurosim canvas already exists** at `/canvas`, the visualizer should be implemented as:

### 5.1 Integration Point

- **Primary home:** Inside the existing **NeuroStudio `/canvas` route**.
- **Secondary home:** Standalone web component that can be launched from any module (e.g., Neurobench to visualize a benchmark run).

### 5.2 Tech Stack

| Layer | Technology | Justification |
|-------|-----------|---------------|
| **Frontend (graph)** | **D3.js** (2D) + optional **Three.js** (3D) | D3 is better for 2D force-directed/ layered layouts with data binding. Three.js for optional 3D view |
| **Frontend (plots)** | **Plotly.js** or **Chart.js** | Raster plots, traces, histograms. Both have good Flutter WebView support |
| **Frontend (UI)** | **Vue 3** or **Svelte** | Reactive, component-based, embeddable in existing canvas |
| **Backend (simulation)** | **Python** (our existing stack) — `snnTorch`, `norland`, or custom LIF backend | Already used in neurocnl |
| **Backend (API)** | **FastAPI** or existing Flask | REST/WebSocket for streaming spike data |
| **Data format** | **JSON** or **HDF5** for large traces | Interchange between Python sim and JS viz |

### 5.3 Data Flow

```
┌─────────────────┐      WebSocket/SSE      ┌──────────────────┐
│  Python SNN     │  ───────────────────►  │  JS Visualizer   │
│  Simulation     │   spike events, V(t)  │  (D3/Three.js)   │
│  Engine         │                       │                  │
│  (snnTorch)     │ ◄───────────────────  │  User controls   │
└─────────────────┘   parameter changes     │  (play/pause/etc)│
                                           └──────────────────┘
```

**Why WebSocket/SSE instead of polling?**
- Spike data is high-frequency and time-sensitive.
- We want to push events as they happen in the simulation loop.
- NetPyNE and SNNtrainer3D both use request/response polling; we can do better for "flow" visualization.

### 5.4 Performance Considerations

| Challenge | Mitigation |
|-----------|-----------|
| **1000+ neurons** | Use **instanced rendering** (Three.js `InstancedMesh`) or **SVG `<use>`** (D3). Do not create individual DOM/WebGL objects per neuron |
| **10,000+ synapses** | Use **edge bundling** or **aggregated connectivity matrix** when zoomed out; only show individual edges when zoomed in |
| **High-frequency spikes** | Buffer spike events in 50ms bins before rendering; use **particle systems** for traveling pulses |
| **Long traces** | Downsample membrane potential data using Largest-Triangle-Three-Buckets (LTTB) algorithm before sending to frontend |

---

## 6. UI/UX Design Notes

### 6.1 Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Toolbar: [Play] [Pause] [Step] [Reset] [Speed: 1x ▼]      │
├────────────────────────┬────────────────────────────────────┤
│                        │                                    │
│   Architecture View    │   Raster Plot + Traces Panel      │
│   (2D/3D network)      │   (time-series plots)              │
│                        │                                    │
│                        ├────────────────────────────────────┤
│                        │   Selected Neuron Info            │
│                        │   (V_mem, threshold, stats)        │
├────────────────────────┴────────────────────────────────────┤
│  Bottom: Timeline scrubber + Spike density histogram       │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Color Scheme

Borrow the **dark theme** from NetPyNE (`#434343` background, `#E0E0E0` text) — it reduces visual fatigue during long simulation sessions and makes colored spikes/weights pop.

**Proposed palette:**
- Background: `#2D2D2D`
- Panel borders: `#444444`
- Text: `#E0E0E0`
- Positive weights: `#4CAF50` (green)
- Negative weights: `#F44336` (red)
- Spikes / active pulses: `#FFEB3B` (yellow) — high contrast against dark background
- Membrane potential trace: `#2196F3` (blue)
- Threshold line: `#FF9800` (orange), dashed

### 6.3 Interactions

- **Hover neuron:** Show tooltip with ID, layer, current `V_mem`, firing rate.
- **Click neuron:** Pin its trace to the traces panel; highlight all its connections.
- **Click connection:** Show weight value, synaptic delay, plasticity history sparkline.
- **Double-click background:** Reset view.
- **Scroll on timeline:** Zoom time axis.

---

## 7. Integration with NMTK Ecosystem

Our existing codebase provides several integration opportunities:

| Existing Component | How the Visualizer Can Leverage It |
|--------------------|-----------------------------------|
| **NeuroStudio `/canvas`** | Embed the visualizer as a tab or overlay. The canvas already handles SNN spec editing |
| **neurocnl** (CNL→SNN compiler) | Visualize the compiled network directly from CNL output |
| **Neurobench** | After running a benchmark, open the visualizer pre-loaded with the benchmark's spike recordings |
| **Neurosense** | Show the spike-encoded input (e.g., cochleagram or DVS events) alongside the network |
| **Neurochip** | Visualize hardware-in-the-loop responses if the backend supports reading back spike counters |
| **Neurohub** | Export an animated simulation as a shareable artifact (model card + video clip) |

**Recommended milestone:**
1. **Phase 1:** Standalone 2D architecture view + raster plot (integrate into `/canvas`).
2. **Phase 2:** Add real-time spike animation + membrane traces.
3. **Phase 3:** Add parameter tweak panel + model comparison mode.
4. **Phase 4:** Add optional 3D view + export to video.

---

## 8. Conclusion

None of the three analyzed repositories provides a complete "spike flow" simulation visualizer out of the box:

- **SNNtrainer3D** has beautiful architecture visualization but is static (post-training only).
- **NetPyNE** has world-class analysis plots but is biophysically oriented and lacks flow animation.
- **RAVSim** has runtime interaction but is locked in LabVIEW and lacks a modern web-native network graph.

**Our opportunity:** Build the first open-source, web-native SNN simulator that **animates spikes propagating through the network in real time**, layered on top of the analytical depth of NetPyNE and the intuitive weight visualization of SNNtrainer3D.

The recommended stack (D3.js/Three.js + FastAPI WebSocket + snnTorch backend) aligns with NMTK's existing Python/Flutter/WebView architecture and can be incrementally delivered in four phases starting with the existing Neurosim canvas.

---

## 9. References

1. Jurj, S.L.; Banasaz Nouri, S.; Strutwolf, J. *SNNtrainer3D: Training Spiking Neural Networks Using a User-Friendly Application with 3D Architecture Visualization Capabilities.* Appl. Sci. 2024, 14, 5752. https://doi.org/10.3390/app14135752
2. Dura-Bernal, S. et al. *NetPyNE: A Python package to facilitate the development, simulation, parallelization, analysis, and optimization of biological neuronal networks using the NEURON simulator.* http://www.netpyne.org
3. Sanaullah et al. *Exploring spiking neural networks: a comprehensive analysis of mathematical models and applications.* Front. Comput. Neurosci. 2023, 17. https://doi.org/10.3389/fncom.2023.1143301
4. SNNtrainer3D GitHub: https://github.com/jurjsorinliviu/SNNtrainer3D
5. NetPyNE GitHub: https://github.com/suny-downstate-medical-center/netpyne
6. NetPyNE-UI GitHub: https://github.com/MetaCell/NetPyNE-UI
7. RAVSim GitHub: https://github.com/Rao-Sanaullah/RAVSim
