# SNN / Neuromorphic Hardware Visualization & Animation — Methods Survey and Recommendation

**Date:** 2026-06-11
**Status:** Research / recommendation (no code changes)
**Scope:** Visualization methods for neuromorphic hardware; animation of those visualizations during inference and training; survey of current implementations in this repo and in other tools.
**Context:** Suite control plane + all modules in `nmtk/neuro_toolkit/assets/modules.json`. Surface priority is neurocnl Studio (per follow-up question).

---

## How to read this

Section 1 is a survey of what already exists. Section 2 is what other tools do. Sections 3 and 4 are recommendations for new methods. Section 5 is the proposed placement in this repo. Section 6 is the ranked work plan. Section 7 is the cross-cutting requirements.

---

## 1. What already exists in this repo

| Surface | Location | Status |
|---|---|---|
| Matplotlib static plots (raster, voltage, topology, weight evolution, `to_html` PNG embed) | `neurocnl/neurocnl/visualization.py:1-357` | Mature; lazy-imported; behind `[viz]` extra |
| Animated SNN playback (play/pause, 0.5×–5× speed, scrubber, pinch-zoom, 40-window firing-rate bar chart) | `neurocnl/frontend/lib/widgets/canvas/animated_snn_playback.dart:1-1088` | Most mature animation in repo |
| Combined dynamics view (rates + raster + voltage on a shared time axis) | `neurocnl/frontend/lib/widgets/canvas/snn_dynamics_view.dart:1-296` | Mature |
| Static raster + voltage traces | `spike_raster_plot.dart`, `time_series_chart.dart` | Mature |
| Topology graph (CustomPainter, drag, node-size-by-neuron-count) | `network_graph_view.dart:1-1207` | Mature |
| Loss / energy / quantization curves | `widgets/canvas/loss_curve_chart.dart:1-274`, `widgets/energy_bar_chart.dart`, `widgets/quantization_curve_chart.dart` | Loss curve has trailing dot for in-progress training |
| Network canvas with simulation panel | `widgets/canvas/canvas_simulation_surface.dart:1-319` | Topology + selected-node playback |
| Studio pipeline animation | `nmtk_ui_core/lib/widgets/pipeline_stepper.dart` (pulse), `snn_workflow_stepper.dart` | Workflow chrome only |
| Motion tokens (durations, easings, `Pulse` widget) | `nmtk_ui_core/lib/motion_tokens.dart` | Standardize all new motion through this |
| Existing visualizer design doc (CustomPaint + WS + LIF plan, May 2026) | `docs/reports/snn-visualizer-flutter-plan.md:1-570` | Already covers phases 1–5; many items now built |
| Hardware WebSocket streams | `Neurochip/.../pynq_ws_stream.py`, `akida_ws_stream.py`, `spinnaker2_backend.py` | Backend has spike streams; no chip-side dashboard UI yet |
| Backend Python viz / Results-step guidance | `docs/unified_toolkit_architecture.md:678,693,1006,2026`; `docs/archive/2026-06-09-cnl-studio-workflow-advisory.md:89-115` | "Animated training & model visualization in Results step" is an explicit product direction |

### Gaps relative to other tools

1. No **traveling-spike pulse** animation along edges in the topology graph.
2. No **connectivity-matrix heatmap** view.
3. No **weight-heatmap / synaptogram** (Loihi "synapse map").
4. No **3D / WebGL** rendering path (graphview / deck.gl / three.js not used).
5. No **real-time parameter sliders** that re-stream into a running simulation.
6. No **chip-level live monitor** (PYNQ / Akida / SpiNNaker2) — backend streams exist; no UI consumes them.
7. No **side-by-side comparison** of two inference runs.
8. Loss/raster playback are **post-hoc only**; no live "show-this-epoch-as-it-happens" pipe from training.

---

## 2. What other tools currently do

| Tool | Visualization approach | Animation approach | Source |
|---|---|---|---|
| **snnTorch** (`snntorch.spikeplot`) | matplotlib: `raster`, `spike_count` bars, `traces` (membrane + spike overlay, 3×3 grid) | `Camera.snap()` + `matplotlib.animation.ArtistAnimation`; `animator(data, fig, ax, interval=40)` sweeps first dim as time; saves MP4/GIF | https://snntorch.readthedocs.io/en/latest/snntorch.spikeplot.html |
| **Lava (Intel)** | `lava.utils.visualizer` (graph), `lava.lib.dnf.utils.plotting` (rate-coded spike gen) | Static plots of spike trains, traces, STDP learning window | https://lava-nc.org/lava/lava.utils.html#lava-utils-visualizer |
| **Nengo GUI** | Browser-based live "rack" of semi-transparent nodes with adjustable gains/intercepts | Continuous real-time update while simulation runs; per-neuron "voltage" sliders | (Nengo GUI is the de-facto reference for live Nengo viz) |
| **NEST** | `nest.raster_plot`, `nest.voltage_trace`, `pynestml.visualisation` | Static matplotlib; can chain in notebooks | nest-simulator docs |
| **Brian2** | `SpikeMonitor`, `StateMonitor` → `plot()`, `brian2viz` (raster, traces, rates) | `run()`-time rendering via `report` callback or `play` in Jupyter | brian2 docs |
| **Norse** | `norse.torch.utils.plot.*` (spike-raster GIF using `imageio`) | Tensors → GIFs; "SNN vs ANN" comparison plots | Norse repo |
| **Bokeh / HoloViews / Panel / Streamlit / Gradio** | Web dashboards with sliders, decimation, linked brushing | WebSocket-backed; `streamz` for live data | general data-viz ecosystem |
| **TensorBoard** | Histograms, scalars, graphs (`tf.summary`); `add_image` for rasters | Time series, but not neuromorphic-native | standard ML |
| **Netron** | ONNX / NIR graph viewer; pan/zoom; node attributes | Read-only, no live animation | https://netron.app |
| **BrainChip MetaTF / Akida** | Model summary print + CSV; no built-in live dashboard | n/a | BrainChip docs |
| **Loihi NeuroCore tools (NxSDK)** | `nxproxy` / `nxviz` for probe buffers, energy/trace heatmaps, "synapse map" 2D spatial view of on-chip weights | Probe-based replay, not real-time | Intel NxSDK docs |
| **SpiNNaker2 / sPyNNaker** | `spynnaker8.plot` (raster, voltage, weights); 2D torus mapping for SpiNNaker board | Static matplotlib | spynnaker docs |

### Common patterns to borrow

- **snntorch's `Camera` / `animator` + `interval`** is the simplest training/inference animation pattern — a per-timestep raster frame.
- **Lava / Loihi "synapse map"** is the canonical way to make on-chip weights *legible* — colour-coded 2D heatmap per core.
- **Nengo GUI's live rack** is the gold standard for "you can poke a parameter while watching" — needs a *bidirectional* pipe.
- **snnTorch `spike_count` bars** are the cleanest way to communicate "what does the network think" — let users point at a class and see its spike histogram grow.

---

## 3. Suggested visualization methods

### Group A — for inferring what the network is doing

1. **Spike raster + firing-rate histogram** (per layer, per output class) — already partially built; add per-class overlay.
2. **Membrane-potential trace stack** for the k most-active neurons — extend `snn_dynamics_view.dart`.
3. **Connectivity-matrix heatmap** (sources × targets, colour = weight, sign = hue) — same heatmap can show synaptic changes during training.
4. **Population activity heatmap** (neurons × time, log-spike-count) — better than raster for dense (>500 neuron) layers.
5. **3D volumetric / `deck.gl` / `three.js` embed** (optional) for "where on the chip is the activity" — deferred per existing plan.

### Group B — for training visualization (long-horizon)

6. **Live loss/accuracy curve** (already a trailing dot) → make it rewindable, with replay + epoch marker scrubbing.
7. **Weight evolution strip** (small multiples of weight-histograms per epoch).
8. **Gradient-magnitude / surrogate-gradient flow** (Lava-style).
9. **Confusion-matrix sparkline** over training (input cells, predicted cells).
10. **Energy / spike-count per layer per epoch** bar race — `energy_bar_chart.dart` is the starting point.

### Group C — chip-level / hardware-in-the-loop

11. **On-chip synapse map** (2D heatmap per Loihi / SpiNNaker2 core) — Lava / Loihi style.
12. **Live event-bus monitor** (chip-to-host spike traffic over time) — uses existing `pynq_ws_stream.py`.
13. **Power / energy proxy** line per layer (chip-reported or estimated).
14. **Fault-injection overlay** on the raster (which spikes are dropped / silenced / duplicated).

### Group D — comparative / replay

15. **Side-by-side rasters** (original vs quantized, pre vs post fault, sim vs hardware).
16. **Connectivity diff** (weights_before − weights_after, signed heatmap).

---

## 4. Suggested animation methods

Driven by `NmtkMotionTokens` (`nmtk_ui_core/lib/motion_tokens.dart`) for durations / easings, plus the project's existing pulse / AnimationController pattern (`pipeline_stepper.dart`, `animated_snn_playback.dart`).

| Method | Where it helps | How |
|---|---|---|
| **Time-cursor sweep** (already built) | Post-hoc inference replay | `AnimationController` driving a cursor t∈[0, duration]; widgets slice buffers at t (existing `animated_snn_playback.dart` pattern) |
| **Live append** (snntorch `animator` style) | Live training + live inference | Append a new frame per WebSocket batch; let `AnimatedBuilder` rebuild; auto-throttle to 30 fps |
| **Traveling pulse along edges** (proposed) | Show spike propagation between populations | Cubic-Bézier path; `AnimationController` 0→1; lifetime ~0.4 s, scaled by synaptic delay |
| **Staged value reveal** | Multi-metric Results screen | Stagger `FadeTransition` / `SlideTransition` of metric cards with `interval = NmtkMotionTokens.shortStep` per card |
| **Trailing cursor dot on curves** | Live loss/accuracy | Already in `loss_curve_chart.dart:60`; replicate for accuracy + per-layer energy |
| **Heatmap tween** | Weight evolution per epoch | Two-pass: hold current heatmap visible for N frames, tween colour values with `ColorTween`, then reveal next epoch |
| **Topology pulse-on-spike** | When a neuron fires, ring expands | `AnimatedBuilder` with `CurvedAnimation`; `Tween<double>(0, 1)` on radius; ring colour = neuron class |
| **Pipeline stepper pulse** | Already exists; reuse | `nmtk_ui_core/pipeline_stepper.dart:281`; also `Pulse` widget in `motion_tokens.dart:323` |
| **Bar-race for spike counts** | Output class competition | Implicit in snntorch's `spike_count(animate=True)`; replicate in Flutter via `AnimatedBuilder` + `Tween<double>` per bar |
| **"Tape" / scope-style rolling chart** | Live inference (oscilloscope feel) | Reuse `time_series_chart.dart` with rolling x-window |
| **"Slow" mode / scrubber replay** | Inspecting training after the fact | Already implemented for inference; mirror for training curves |

Implementation levers in the repo:

- `AnimationController`, `TickerProviderStateMixin`, `AnimatedBuilder` (the dominant pattern in `animated_snn_playback.dart`).
- Riverpod `StateNotifierProvider` for sim / training state, with `StreamController` per WebSocket source.
- `MediaQuery.disableAnimationsOf(context)` is already respected (`animated_snn_playback.dart:122`) — new animations must also respect it.
- `RepaintBoundary` per animated region (graph, raster, traces) to avoid full-screen rebuilds.

---

## 5. Where the work would land

Single primary home: **`neurocnl/frontend/lib/widgets/canvas/`** (where `animated_snn_playback.dart`, `spike_raster_plot.dart`, `time_series_chart.dart`, `loss_curve_chart.dart`, `snn_dynamics_view.dart`, `network_graph_view.dart`, `canvas_simulation_surface.dart` already live). Promote reusable atoms (heatmaps, travelling-pulse painter, scope chart) into `nmtk_ui_core`.

Backend additions (data only, no new sim engine needed):

- Stream the existing chip WebSockets (`pynq_ws_stream.py`, `akida_ws_stream.py`, `spinnaker2_backend.py`) into a normalized `sim.viz.events` channel.
- Add `nn.energy` / `nn.weight_snapshot` probes if missing, mirroring Lava's `Monitor`.
- Hook the existing `training_inspector_panel.dart` epoch loop to also publish per-epoch `(weights, loss, accuracy, grad_norm, per_class_spike_count)` snapshots that the new viz consumes.

---

## 6. Ranked work plan (easiest → hardest)

Per the follow-up: surface = neurocnl Studio only, renderer = small embedded WebView (deck.gl / three.js / D3) for the heavy views plus plain `CustomPaint` for the rest, data = post-hoc replay only.

### Tier 1 — pure Flutter, post-hoc replay, no new dependencies

- **T1.1 — Trained-rasters-by-class bars** (10–20 LOC on top of `spike_raster_plot.dart`). Show per-class spike count growing as the time cursor sweeps. Mirrors snntorch's `spike_count(animate=True)`. Pure `CustomPaint`; zero new deps.
- **T1.2 — Connectivity-matrix heatmap** (new `connectivity_heatmap.dart`). `sources × targets`, colour by weight, hue by sign, intensity by magnitude. Same widget reused for weight-diff view (Tier 3).
- **T1.3 — Live-loss tape + replay scrubber for training** (extend `loss_curve_chart.dart`). Add `accuracy` twin curve, `grad_norm` bar, replay scrubber. Existing trailing-dot pattern (`loss_curve_chart.dart:60`) becomes a `Tween` over epochs.
- **T1.4 — Staged Results reveal** (per 2026-06-09 advisory). Wrap each Results card in `AnimatedSwitcher` + `NmtkMotionTokens.shortStep` stagger. Zero new files.

### Tier 2 — WebView atom for the network graph (the new rendering core)

- **T2.1 — `SnnGraphWebView` widget** (new `widgets/canvas/snn_graph_webview.dart`). Flutter host = `webview_flutter` (or `flutter_inappwebview` if postMessage ergonomics are needed). Renders one HTML file shipped as a Flutter asset: `assets/viz/snn_graph.html` containing **deck.gl** for 2D (force / sugiyama layout, edge bundling) and **three.js** for 3D mode. Bridge contract (postMessage JSON): `init`, `setTopology`, `setSpikes`, `setCursor(time_ms)`, `setLayerHighlight`.
- **T2.2 — Traveling-spike pulse in 2D mode**. deck.gl `LineLayer` with `getSourcePosition/getTargetPosition`, plus a `ScatterplotLayer` whose positions are `lerp(src, tgt, t)` where `t` is driven from the host (postMessage `{t: 0.42}`) so the WebView re-uses Flutter's time-cursor (`animated_snn_playback.dart` pattern). Pulse lifetime = `synaptic_delay_ms`; opacity fades to 0.
- **T2.3 — 2.5D / 3D toggle in the same WebView**. Same `snn_graph.html`, swap deck.gl `OrthographicView` → `OrbitView`; nodes become spheres (three.js or deck.gl `ScenegraphLayer`). Triggered by a `LayerToggle` button in the host toolbar.

### Tier 3 — comparative / weight-difference views (re-uses T1.2, T2.1)

- **T3.1 — Weight heatmap, animated per epoch**. `connectivity_heatmap.dart` already built in T1.2. Add `Tween<Color>` between epochs with `interval = NmtkMotionTokens.mediumStep`.
- **T3.2 — Weight-diff heatmap (before vs after)**. Reuse T1.2 with a `diffMode: true` flag and a diverging colour map.
- **T3.3 — Side-by-side rasters**. Two `SnnDynamicsView` in a `Row`, one shared `AnimationController` (drive `Tween<double>` for both cursors at once).

### Tier 4 — chip-level views (Lava / Loihi "synapse map" inspired)

- **T4.1 — On-chip synapse map** (2D heatmap per Loihi / SpiNNaker2 core). Reuses T1.2's heatmap painter; only the data source differs (a chip-side weight buffer instead of a `Linear.weight` matrix). No backend change in this phase — feed it from the existing `simulate_chip_preview` artifact if present; otherwise from mapped NIR weights.
- **T4.2 — Power / energy proxy line per layer**. New `widgets/canvas/energy_per_layer_tape.dart` — `CustomPaint` line per layer, rolling x-window (oscilloscope feel).

### Tier 5 — research-grade niceties (defer)

- **T5.1 — 3D volumetric** (three.js, already in T2.3 HTML).
- **T5.2 — Confusion-matrix sparkline** over training.
- **T5.3 — Surrogate-gradient flow diagram** (Lava-style, static + animation).
- **T5.4 — Bar-race for spike counts per class** over training (re-use T1.1 machinery with epoch index instead of time).
- **T5.5 — Export: PNG / SVG / MP4 / GIF** of the WebView (`html2canvas` + `MediaRecorder` API inside `snn_graph.html`).

---

## 7. Cross-cutting requirements (apply to every tier)

- **Motion tokens:** all Flutter-side durations/easings come from `nmtk_ui_core/lib/motion_tokens.dart`. No ad-hoc `Duration(milliseconds: …)` in new code.
- **Reduce-motion:** respect `MediaQuery.disableAnimationsOf(context)` (already done in `animated_snn_playback.dart:122`); mirror in the WebView with `prefers-reduced-motion: reduce` media query inside `snn_graph.html`.
- **WebView contract:** all messages in/out are typed; declare them as Dart `freezed` classes alongside the widget so the bridge is type-checked.
- **No live WS:** the WebView receives *snapshots* of the simulation artifact, not a stream. Playback is driven by Flutter's `AnimationController` posting `{t}` to the WebView (so the entire timing model is owned by the host).
- **Theme parity:** WebView receives a JSON palette from Flutter (`NmtkShellTokens`) so dark / light / HC themes propagate.
- **Tests:** widget tests for the new Flutter atoms; Playwright-on-Flutter for `snn_graph.html` smoke (or unit tests in JS via `node:test`).
- **No backend changes** in any tier (per "post-hoc replay only").

---

## 8. Files this plan will add or touch

- **Add (new):**
  - `neurocnl/frontend/lib/widgets/canvas/connectivity_heatmap.dart`
  - `neurocnl/frontend/lib/widgets/canvas/snn_graph_webview.dart`
  - `neurocnl/frontend/lib/widgets/canvas/side_by_side_raster.dart`
  - `neurocnl/frontend/lib/widgets/canvas/chip_synapse_map.dart`
  - `neurocnl/frontend/lib/widgets/canvas/energy_per_layer_tape.dart`
  - `neurocnl/frontend/assets/viz/snn_graph.html` + `snn_graph.js` + `snn_graph.css`
  - `neurocnl/frontend/lib/models/viz_bridge.dart` (freezed message types)
- **Edit (extend):**
  - `neurocnl/frontend/lib/widgets/canvas/loss_curve_chart.dart` (T1.3)
  - `neurocnl/frontend/lib/widgets/canvas/snn_dynamics_view.dart` (T3.3 host)
  - `neurocnl/frontend/lib/widgets/training_inspector_panel.dart` (T1.3 wiring)
  - `neurocnl/frontend/pubspec.yaml` (WebView deps + assets)
  - `neurocnl/frontend/lib/widgets/canvas/canvas_simulation_surface.dart` (mount T2.1)
- **Edit (docs):**
  - `docs/reports/snn-visualizer-flutter-plan.md` — annotate which phases are done by this plan.

---

## 9. Recommended first PR

T1.1 + T1.2 + T2.1 (skeleton) — gives the project a working "post-hoc replay with a real graph view" deliverable in one PR, and unblocks all later tiers because the WebView contract is the highest-risk interface.

---

## 10. Out of scope (explicit)

- Backend simulation changes (snntorch / nengo / lava engines, weight probes, energy probes) — not required for any tier above.
- Live WebSocket / bidirectional parameter pipes — explicitly deferred per "post-hoc replay only".
- Mobile-specific layouts — defer to the existing mobile-shell work; primary target is desktop Studio.
- 3D volumetric — Tier 5.
