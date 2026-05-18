# SNN Simulation Visualizer: Flutter-Native Architecture & Implementation Plan

> **Date:** 2026-05-17  
> **Status:** Architecture revision v2 — Flutter-native frontend, Python backend  
> **Context:** NeuroMorphicToolkit (NMTK) already has a near-complete Flutter desktop/mobile launcher. The visualizer must be a first-class Flutter feature, not a WebView wrapper.

---

## 1. Why Flutter-Native (Not Web)

The previous analysis suggested a web stack (D3.js/Three.js + Vue/Svelte inside a WebView). This is **wrong** for NMTK because:

- **You already own a Flutter app.** Adding a WebView layer adds dependency bloat, bridge latency, and platform inconsistency.
- **Performance.** CustomPaint + AnimationController in Flutter can render 1,000+ nodes and animated spike pulses at 60fps without leaving the GPU-composited layer tree. A WebView cannot.
- **Native integration.** The visualizer can directly use existing NMTK state (Riverpod/Bloc stores), navigation, theming, and module routing. No JS ↔ Dart bridge required.
- **Offline & desktop.** Flutter desktop (macOS/Windows/Linux) compiles to native. The Python backend runs locally via `venv`/Docker. Zero browser dependencies.
- **Touch & pen input.** Flutter's gesture system is superior for panning, zooming, and selecting neurons on touchscreens and tablets.

**Decision:** Build the visualizer as a native Flutter feature inside the existing `nmtk_ui_core` / NeuroStudio codebase.

---

## 2. Tech Stack

### 2.1 Flutter Frontend (Dart)

| Concern | Package / Approach | Justification |
|---------|-------------------|---------------|
| **Network graph rendering** | `CustomPaint` + `graphview` (for layout only) | `graphview` computes Sugiyama/layered node positions. `CustomPaint` draws nodes/edges/spikes at 60fps with zero widget overhead. |
| **Spike pulse animation** | `CustomPaint` + `AnimationController` | Pulses are small circles traveling along cubic Bézier edge paths. `AnimationController` drives progress 0→1 with adjustable speed. |
| **Charts (raster, traces)** | `fl_chart` | Mature, highly customizable, performant. Supports line charts, scatter plots, bar charts. Dark theme friendly. |
| **Real-time comms** | `web_socket_channel` | Standard Dart WebSocket client. Streams `SpikeEvent`s into a `StreamController` consumed by UI. |
| **State management** | `Riverpod` (already used in NMTK) | Simulation state (play/pause/speed), network topology, selected neuron, trace buffers. Reactive rebuilds of widgets. |
| **Data models** | `freezed` + `json_serializable` | Immutable data classes with JSON codegen for WebSocket payloads. |
| **Architecture** | Layered: `UI → State (Riverpod) → Service (WebSocket) → Models` | Consistent with existing NMTK patterns in `nmtk_ui_core`. |
| **3D (future)** | `flutter_gl` or embedded `three.js` in a small WebView *only* for the optional 3D tab | 3D is not MVP. If added later, isolate it to one widget. |

### 2.2 Python Backend

| Concern | Technology | Justification |
|---------|-----------|---------------|
| **Web server** | `FastAPI` | Async-native, auto-generated OpenAPI docs, built-in WebSocket support. NMTK already uses FastAPI in other modules. |
| **SNN simulation** | `snnTorch` (PyTorch-based) or lightweight custom LIF engine | `snnTorch` is what SNNtrainer3D uses. For a lighter dependency, a custom NumPy-based LIF/Synaptic simulator is ~200 lines. |
| **Simulation runner** | `asyncio` background task | Simulation loop runs in a `asyncio` task, yielding spike events via `async for` to the WebSocket. |
| **Data validation** | `Pydantic v2` | Request/response models for network definition, neuron parameters, simulation config. |
| **Serialization** | `orjson` | Fast JSON encoding for high-frequency spike streaming. |
| **Storage** | `HDF5` (via `h5py`) or `zarr` | Store long simulation traces (membrane voltage, spike times) for post-hoc scrubbing. |

### 2.3 Communication Protocol

**Transport:** WebSocket (`ws://localhost:<port>/ws/simulation`)

**Why WebSocket?**
- Spike events are high-frequency, time-sensitive, and server-pushed. Polling is wasteful.
- Bidirectional: Flutter sends parameter tweaks; Python streams simulation state.

**Message Schema (JSON):**

```json
// Flutter → Python: Start simulation
{
  "type": "sim.start",
  "payload": {
    "network": {
      "layers": [
        {"size": 784, "type": "input"},
        {"size": 128, "type": "lif", "tau_mem": 20.0, "v_thresh": 1.0},
        {"size": 10,  "type": "lif", "tau_mem": 20.0, "v_thresh": 1.0}
      ],
      "weights": { /* optional pre-trained weights */ },
      "connectivity": "fully_connected"
    },
    "stimulus": {
      "type": "mnist_digit",
      "digit": 7
    },
    "duration_ms": 1000,
    "dt_ms": 1.0
  }
}

// Python → Flutter: Spike event (streamed continuously)
{
  "type": "event.spike",
  "payload": {
    "neuron_id": "L1_N042",
    "layer": 1,
    "index": 42,
    "time_ms": 125.0
  }
}

// Python → Flutter: Membrane state snapshot (batched every N ms)
{
  "type": "state.membrane",
  "payload": {
    "time_ms": 125.0,
    "neurons": [
      {"id": "L1_N000", "v": 0.85, "i_syn": 0.12},
      {"id": "L1_N001", "v": 0.23, "i_syn": 0.05}
    ]
  }
}

// Python → Flutter: Weight update (if plasticity enabled)
{
  "type": "event.weight_change",
  "payload": {
    "source": "L0_N007",
    "target": "L1_N042",
    "delta": 0.003,
    "new_value": 0.523
  }
}

// Python → Flutter: Simulation finished
{
  "type": "sim.finished",
  "payload": {
    "duration_ms": 1000,
    "total_spikes": 1247
  }
}

// Flutter → Python: Parameter tweak at runtime
{
  "type": "cmd.set_param",
  "payload": {
    "neuron_id": "L1_N042",
    "param": "v_thresh",
    "value": 0.8
  }
}
```

---

## 3. Data Models (Flutter — `freezed`)

```dart
// lib/visualizer/models/network_topology.dart
@freezed
class NetworkTopology with _$NetworkTopology {
  const factory NetworkTopology({
    required List<LayerConfig> layers,
    required List<Synapse> synapses,
  }) = _NetworkTopology;

  factory NetworkTopology.fromJson(Map<String, dynamic> json) =>
      _$NetworkTopologyFromJson(json);
}

@freezed
class LayerConfig with _$LayerConfig {
  const factory LayerConfig({
    required int size,
    required String type, // 'input' | 'lif' | 'lapicque' | 'synaptic'
    double? tauMem,
    double? vThresh,
    double? vReset,
    double? refractoryMs,
  }) = _LayerConfig;

  factory LayerConfig.fromJson(Map<String, dynamic> json) =>
      _$LayerConfigFromJson(json);
}

@freezed
class Synapse with _$Synapse {
  const factory Synapse({
    required String sourceId,
    required String targetId,
    required double weight,
    double? delayMs,
  }) = _Synapse;

  factory Synapse.fromJson(Map<String, dynamic> json) =>
      _$SynapseFromJson(json);
}

// lib/visualizer/models/neuron_state.dart
@freezed
class NeuronState with _$NeuronState {
  const factory NeuronState({
    required String id,
    required double voltage,
    required double timeMs,
    double? synapticCurrent,
  }) = _NeuronState;

  factory NeuronState.fromJson(Map<String, dynamic> json) =>
      _$NeuronStateFromJson(json);
}

// lib/visualizer/models/spike_event.dart
@freezed
class SpikeEvent with _$SpikeEvent {
  const factory SpikeEvent({
    required String neuronId,
    required int layer,
    required int index,
    required double timeMs,
  }) = _SpikeEvent;

  factory SpikeEvent.fromJson(Map<String, dynamic> json) =>
      _$SpikeEventFromJson(json);
}
```

---

## 4. Flutter UI Architecture

### 4.1 Screen Layout

```
┌────────────────────────────────────────────────────────────────┐
│  AppBar: "SNN Visualizer"    [Play] [Pause] [Step→] [Reset]   │
│  Speed: [0.25x] [1x] [4x] [10x]    Time: 125ms / 1000ms      │
├────────────────────────┬───────────────────────────────────────┤
│                        │                                       │
│   Network Graph        │   Raster Plot (fl_chart scatter)      │
│   (CustomPaint)        │   • Each dot = one spike              │
│                        │   • X = time, Y = neuron index       │
│   ○ →●→ ○              │   • Layer separators as faint lines  │
│   │     ↑              │                                       │
│   ○     ●              ├───────────────────────────────────────┤
│         │              │                                       │
│   ○ →●→ ○              │   Membrane Potential Traces           │
│                        │   (fl_chart LineChart)                │
│   Yellow dots =        │   • Blue line = V_mem(t)              │
│   traveling spikes     │   • Orange dashed = v_thresh          │
│                        │   • Shaded area = refractory period   │
│                        │                                       │
├────────────────────────┴───────────────────────────────────────┤
│  Bottom: Timeline Scrubber + Layer firing rate mini-bars      │
└────────────────────────────────────────────────────────────────┘
```

### 4.2 Widget Breakdown

| Widget | Type | Responsibility |
|--------|------|---------------|
| `SnnVisualizerScreen` | `ConsumerWidget` | Top-level screen. Holds `Scaffold`, `AppBar`, playback controls. Watches `SimulationController` (Riverpod). |
| `NetworkGraphWidget` | `CustomPaint` | Renders nodes (circles), edges (lines), and traveling spike pulses (animated circles on edges). Handles pan/zoom via `GestureDetector`. |
| `RasterPlotWidget` | `fl_chart` `ScatterChart` | Displays spike raster. Updates when new `SpikeEvent`s arrive. |
| `MembraneTraceWidget` | `fl_chart` `LineChart` | Displays voltage traces for selected neurons. Scrolls right as simulation progresses. |
| `TimelineScrubber` | `Slider` + `CustomPaint` | Horizontal scrubber showing simulation progress and per-layer firing rate. |
| `ParameterPanel` | `ListView` + `Slider` | Runtime parameter tweaks (τ_mem, v_thresh, etc.). Sends `cmd.set_param` via WebSocket. |
| `NeuronInfoCard` | `Card` | Tooltip/overlay showing selected neuron stats (ID, layer, current V, spike count, avg rate). |

### 4.3 The `NetworkGraphPainter` (Core)

This is the heart of the visualizer. It must be performant for 1,000+ neurons.

```dart
class NetworkGraphPainter extends CustomPainter {
  NetworkGraphPainter({
    required this.nodes,
    required this.edges,
    required this.activePulses, // List<TravelingPulse>
    required this.nodeStates,   // Map<nodeId, NeuronState>
    required this.cameraOffset,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Apply camera transform (translate + scale)
    canvas.save();
    canvas.translate(cameraOffset.dx, cameraOffset.dy);
    canvas.scale(zoom);

    // 2. Draw edges (synapses)
    for (final edge in edges) {
      final paint = Paint()
        ..color = edge.weight > 0 ? positiveWeightColor : negativeWeightColor
        ..strokeWidth = 1.0 + (edge.weight.abs() * 2)
        ..alpha = (edge.weight.abs() * 255).toInt();
      canvas.drawLine(edge.sourcePos, edge.targetPos, paint);
    }

    // 3. Draw nodes (neurons)
    for (final node in nodes) {
      final state = nodeStates[node.id];
      final voltage = state?.voltage ?? 0.0;
      final radius = baseRadius + (voltage * 2); // Size by voltage
      final color = voltage > threshold ? activeColor : baseColor;
      canvas.drawCircle(node.position, radius, Paint()..color = color);
    }

    // 4. Draw traveling spike pulses
    for (final pulse in activePulses) {
      final t = pulse.progress; // 0.0 → 1.0, driven by AnimationController
      final pos = lerp(pulse.sourcePos, pulse.targetPos, t);
      canvas.drawCircle(pos, pulseRadius, Paint()..color = spikePulseColor);
    }

    canvas.restore();
  }
}
```

**Performance safeguards:**
- `shouldRepaint` returns `true` only when `activePulses` or `nodeStates` change.
- For >500 nodes, switch to **instanced drawing** or render edges only for selected layers.
- Use `compute()` isolate for layout calculations if network is large.

### 4.4 State Management (Riverpod)

```dart
// Providers

// 1. WebSocket connection
final simulationWebSocketProvider = Provider<SimulationWebSocketService>((ref) {
  return SimulationWebSocketService(url: 'ws://localhost:8080/ws/simulation');
});

// 2. Simulation controller (play/pause/speed/scrubber)
final simulationControllerProvider = StateNotifierProvider<SimulationController, SimulationState>((ref) {
  return SimulationController(ref.read(simulationWebSocketProvider));
});

// 3. Network topology (static after load)
final networkTopologyProvider = StateProvider<NetworkTopology?>((ref) => null);

// 4. Spike buffer (rolling window)
final spikeBufferProvider = StateProvider<List<SpikeEvent>>((ref) => []);

// 5. Membrane state (latest snapshot)
final membraneStateProvider = StateProvider<Map<String, NeuronState>>((ref) => {});

// 6. Selected neuron
final selectedNeuronProvider = StateProvider<String?>((ref) => null);
```

---

## 5. Python Backend API Spec

### 5.1 Endpoints

```yaml
POST /api/v1/network/compile
  body: NetworkTopology (JSON)
  response: { network_id: str, node_count: int, synapse_count: int }
  # Compiles a high-level layer spec into a concrete connectivity graph.

POST /api/v1/simulation/start
  body: { network_id: str, stimulus: {...}, duration_ms: float, dt_ms: float }
  response: { simulation_id: str, status: "running" }
  # Starts a simulation in the background. Spike events stream via WebSocket.

POST /api/v1/simulation/{id}/pause
  response: { status: "paused" }

POST /api/v1/simulation/{id}/resume
  response: { status: "running" }

POST /api/v1/simulation/{id}/step
  query: steps: int = 1
  response: { status: "stepped", time_ms: float }

POST /api/v1/simulation/{id}/reset
  response: { status: "reset" }

GET  /api/v1/simulation/{id}/results
  response: { spike_times: [...], membrane_traces: {...}, metadata: {...} }
  # Returns full results after simulation finishes (or mid-run snapshot).

GET  /api/v1/datasets/mnist/{digit}
  response: { pixel_values: [...], label: int }
  # Returns a flattened MNIST digit for use as input stimulus.
```

### 5.2 WebSocket Handler

```python
# backend/api/websocket.py
from fastapi import WebSocket
import asyncio

class SimulationStream:
    def __init__(self, simulator: SnnSimulator):
        self.simulator = simulator
        self.active = False

    async def run(self, websocket: WebSocket):
        await websocket.accept()
        self.active = True

        while self.active:
            step_events = self.simulator.step(dt_ms=1.0)

            for event in step_events:
                if event.type == "spike":
                    await websocket.send_json({
                        "type": "event.spike",
                        "payload": event.to_dict()
                    })
                elif event.type == "membrane":
                    await websocket.send_json({
                        "type": "state.membrane",
                        "payload": event.to_dict()
                    })

            # Throttle to ~20 FPS of state updates
            await asyncio.sleep(0.05)

        await websocket.close()
```

### 5.3 Simulation Engine (`snnTorch` vs Custom)

**Option A: snnTorch (recommended for training integration)**
- Pros: Already validated, supports STDP, surrogate gradients, export to hardware (Loihi, SpiNNaker).
- Cons: Heavy dependency (PyTorch).

**Option B: Lightweight Custom LIF (recommended for pure simulation speed)**
- ~200 lines of NumPy.
- Pros: Zero heavy dependencies, trivial to deploy inside NMTK Docker.
- Cons: No built-in learning; must implement STDP manually if needed.

**Decision:** Start with **Option B** for the MVP to keep deployment friction near zero. Add an adapter for **Option A** later when users want to visualize trained `snnTorch` models.

---

## 6. Integration with NMTK Ecosystem

| Existing Module | Integration Point |
|-----------------|-------------------|
| **NeuroStudio `/canvas`** | Primary home. Add a "Simulate" button to the canvas that opens the visualizer pre-loaded with the current CNL-compiled network. |
| **neurocnl** | CNL → SNN compiler output is fed directly into `POST /api/v1/network/compile`. No manual network reconstruction. |
| **Neurobench** | After a benchmark run, open the visualizer with the recorded spike data (no live sim needed — just playback mode). |
| **Neurosense** | Spike-encoded inputs (e.g., DVS events, cochleagrams) are shown in the left panel as a "stimulus preview" while the network simulates. |
| **Neurohub** | Export a visualizer session (network + recorded spikes + parameter config) as a shareable artifact. |
| **Neurochip** | Visualize hardware-in-the-loop responses by streaming spike counters from the chip instead of the Python simulator. |

---

## 7. Phased Implementation Roadmap

### Phase 1: Architecture View + Playback (Weeks 1–2)
**Goal:** A static network viewer that can load a topology and show it in 2D.

- [ ] Dart data models (`NetworkTopology`, `LayerConfig`, `Synapse`)
- [ ] `NetworkGraphPainter` with layered layout (input→hidden→output)
- [ ] Color-coded edges (green/red by weight sign, opacity by magnitude)
- [ ] Pan/zoom gesture support
- [ ] `SimulationWebSocketService` skeleton (can mock data locally)
- [ ] Playback controls (Play/Pause/Step/Reset) — UI only, no backend
- [ ] Dummy JSON loader to test layout with sample networks (MNIST-sized)

**Deliverable:** A Flutter screen in NeuroStudio `/canvas` that renders any feedforward SNN as a 2D graph.

### Phase 2: Live Simulation + Spike Animation (Weeks 3–4)
**Goal:** Connect to Python backend and see spikes travel.

- [ ] FastAPI backend with `POST /api/v1/network/compile` and WebSocket `/ws/simulation`
- [ ] Lightweight LIF simulator (Option B) in Python
- [ ] `SimulationController` (Riverpod) managing play/pause/speed/scrubber
- [ ] `TravelingPulse` animation in `NetworkGraphPainter`
- [ ] Real-time spike event consumption via WebSocket
- [ ] Timeline scrubber showing current simulation time

**Deliverable:** User clicks "Simulate" → sees yellow pulses travel from input→hidden→output in real time.

### Phase 3: Raster + Traces (Weeks 5–6)
**Goal:** Add analytical plots for debugging and understanding.

- [ ] `RasterPlotWidget` (`fl_chart` scatter) consuming `spikeBufferProvider`
- [ ] `MembraneTraceWidget` (`fl_chart` line) for selected neurons
- [ ] Click neuron in graph → pin its trace
- [ ] Click spike in raster → highlight neuron in graph
- [ ] Layer-based population firing rate mini-chart in bottom panel
- [ ] Parameter panel (sliders for `tau_mem`, `v_thresh`, etc.)

**Deliverable:** Full analytical dashboard. Researchers can see *why* a neuron spiked by inspecting its trace.

### Phase 4: Parameter Tweaking + Comparison (Weeks 7–8)
**Goal:** Make it interactive and suitable for exploration.

- [ ] Runtime parameter changes via WebSocket (`cmd.set_param`)
- [ ] Side-by-side comparison mode (two simulations running in parallel panes)
- [ ] Connectivity matrix heatmap (as an alternate view to the graph)
- [ ] Export: PNG/SVG of graph, MP4/GIF of animation, JSON of spike data
- [ ] Integration with Neurobench (load benchmark results directly)

**Deliverable:** Production-ready visualizer inside NMTK.

### Phase 5: Optional 3D + Hardware (Future)
- [ ] Three.js embedded in a small WebView widget for 3D overview
- [ ] Neurochip hardware-in-the-loop streaming
- [ ] `snnTorch` adapter for visualizing trained models

---

## 8. File Structure (Proposed)

```
nmtk_ui_core/
└── lib/
    └── visualizer/
        ├── models/
        │   ├── network_topology.dart
        │   ├── neuron_state.dart
        │   ├── spike_event.dart
        │   └── simulation_config.dart
        ├── providers/
        │   ├── simulation_controller.dart
        │   ├── network_topology_provider.dart
        │   └── websocket_service.dart
        ├── widgets/
        │   ├── network_graph_widget.dart
        │   ├── network_graph_painter.dart
        │   ├── raster_plot_widget.dart
        │   ├── membrane_trace_widget.dart
        │   ├── timeline_scrubber.dart
        │   ├── parameter_panel.dart
        │   └── neuron_info_card.dart
        ├── screens/
        │   └── snn_visualizer_screen.dart
        └── utils/
            ├── layout_algorithms.dart      # Sugiyama / layer layout
            ├── color_schemes.dart          # Dark theme palette
            └── pulse_animations.dart       # Traveling spike math

neurocnl/
└── backend/
    └── visualizer_api/
        ├── main.py                       # FastAPI entrypoint
        ├── websocket.py                  # WebSocket handler
        ├── simulator/
        │   ├── __init__.py
        │   ├── lif_engine.py             # Lightweight LIF sim
        │   └── snntorch_adapter.py       # Optional: snnTorch bridge
        ├── models/
        │   ├── network.py
        │   ├── neuron.py
        │   └── events.py
        └── routers/
            ├── network.py
            └── simulation.py
```

---

## 9. Risk & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Flutter CustomPaint performance degrades with >500 nodes** | High | Implement LOD: only render edges for visible layers; use `RepaintBoundary`; batch paint calls. |
| **WebSocket latency spikes on desktop** | Medium | Run Python backend on `localhost` inside same Docker network. Use binary WebSocket frames (MsgPack) instead of JSON if needed. |
| **MNIST-sized input (784 nodes) crashes graph** | High | Input layer nodes are tiny dots or a single "input patch" icon. Do not render 784 full-sized circles. |
| **snnTorch dependency too heavy for NMTK installer** | Medium | Make the Python backend a separate, optional module (like Neurobench). Use lightweight LIF engine for core visualizer. |
| **Integration with existing Riverpod stores is messy** | Low | Create a dedicated `visualizer` feature folder with its own providers. Only depend on shared `UserSettings` / `Theme` providers. |

---

## 10. Summary

This revised plan drops the web-stack recommendation entirely and proposes a **native Flutter visualizer** that is a first-class citizen of the NMTK ecosystem. The architecture is:

- **Flutter frontend:** CustomPaint graph + fl_chart plots + Riverpod state + WebSocket client
- **Python backend:** FastAPI + lightweight LIF simulator + WebSocket streaming
- **Protocol:** JSON-over-WebSocket with typed event stream (`spike`, `membrane`, `weight_change`)
- **Integration:** Lives in NeuroStudio `/canvas`, consumes neurocnl output, feeds Neurobench
- **Phasing:** 5 phases from static graph → live spike animation → full analytical dashboard → comparison mode → 3D/hardware

This leverages your existing investment in Flutter, maintains platform consistency across desktop and mobile, and avoids the performance and integration penalties of a WebView-based approach.
