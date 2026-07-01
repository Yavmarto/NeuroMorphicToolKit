# Chip-Die Visualization Redesign for `/viz-demo`

## Context

The `/viz-demo` screen (`neurocnl/frontend/lib/screens/viz_demo_screen.dart`) currently renders synthetic neuron activity as a flat 2D scatter of glowing particles (10k/100k tiers) or a raster-style time/neuron-index heatmap (1M tier), via GLSL fragment shaders (`nmtk_ui_core/lib/visualization/fragment_shader_renderer.dart`). This was called out as unclear, visually flat, and unrelated to what the numbers actually mean — and it stutters/freezes at 100k/1M scale because the wire protocol sends raw per-spike data (up to ~5,000 floats/frame) and the fragment shaders hardcode a 4096-spike loop limit, silently dropping the rest.

Separately, an attempt to add a native Rust/wgpu renderer for the same raw-particle approach (`nmtk_wgpu` crate, `WgpuNativeNeuronRenderer`) hit a SIGSEGV crash in its macOS `CVPixelBuffer` texture bridge; that renderer is now disabled by default (`nmtk_ui_core/lib/visualization/renderer_registry.dart`) with a fix applied but unverified live. This redesign does not depend on that native path — it targets the existing Dart/fragment-shader pipeline, which the wgpu work was always meant to be an optional accelerator for, not a replacement.

This spec replaces the raw-particle approach entirely with a **chip-die view**: a static grid of tiles, one per physical (or virtual) core, each glowing by aggregate activity. This directly fixes the performance problem (aggregating server-side means constant, small payloads regardless of neuron count) and gives the visualization actual meaning tied to this toolkit's purpose — showing how activity distributes across a *neuromorphic chip's* cores — rather than an abstract particle field or literal brain anatomy (Emotiv Brainviz was the aesthetic inspiration, but this toolkit is about hardware, not EEG/anatomy).

## 1. Target & scale selection

A dropdown, replacing the current bare 10k/100k/1M picker, offers:

- **Software / Simulated** (default) — keeps the existing 10k/100k/1M scale picker. Tile count scales with it:
  | Scale | Tiles | Grid |
  |---|---|---|
  | 10k | 64 | 8×8 |
  | 100k | 256 | 16×16 |
  | 1M | 1024 | 32×32 |
- **Named hardware chip** — one entry per target with known core-count data in `Neurochip/neurochip/targets/*.json` (Akida, Loihi2, SpiNNaker2, SpiNNaker, Speck2, BrainScaleS, PYNQ-Z2). Selecting one:
  - Sets tile count = that chip's core count (Akida 80, Loihi2 128, SpiNNaker2 152, SpiNNaker 18, Speck2 11, BrainScaleS 50, PYNQ-Z2 2), arranged `rows = floor(sqrt(cores))`, `cols = ceil(cores / rows)`.
  - Sets total neuron count = that chip's rated capacity (Akida 1.2M per `docs/AKIDA_SUPPORT_SEMANTICS.md`; others read from their target JSON — normalize any per-core-vs-total ambiguity in the target JSON during implementation, e.g. SpiNNaker2's "1K per core" × 152 cores).
  - Replaces the 10k/100k/1M picker for that mode (confirmed: chip choice determines neuron count, not the scale picker).
  - UI copy must state the grid is an **illustrative approximation**, not the vendor's real floorplan — the source JSONs have no physical layout data, only core counts.

## 2. Per-tile visual encoding

One square tile per core (real or virtual). Per frame, each tile encodes two values:

- **Activity level** → tile brightness/hue, blue (low) → red (high).
- **Concentration** ("core vs. edge") → a soft square gradient inside the tile: a soft bright square centered in the tile when activity concentrates among neurons near that tile's local center index, glow pushed toward the tile's edges when it concentrates among neurons near the local index extremes. Square shape (not circular) to match the sharp tile boundary; soft/blurred edges on the gradient itself for visual polish.

Concentration is computed from real per-frame spike data, not fabricated: for a tile covering local neuron indices `0..k-1`, each neuron's `edge_distance = |local_index - (k-1)/2| / ((k-1)/2)` (0 = center, 1 = edge). `concentration = spike-weighted mean edge_distance over that tile's spikes this frame`.

## 3. Backend aggregation protocol (the performance fix)

Replace both the raw per-spike stream (`BulkSpikeFrame.data`) and the existing time-vs-neuron-index `density_grid` with one uniform payload, computed server-side in `neurocnl/neurosim/app/services/poisson_demo_generator.py`:

- Per frame: `[activity_0, concentration_0, activity_1, concentration_1, ...]` — 2 floats per tile.
- Computed by vectorized numpy binning of the same ~200–5,000 spikes/frame already generated today (neuron index → tile via floor division by tile size; activity = spike count per tile; concentration = the weighted mean above). Cost stays `O(spikes_per_frame)`, not `O(neuron_count)` — 1M-neuron scale costs the same as 10k.
- Max payload: `tile_count × 2 floats × 4 bytes` ≤ ~8KB at 1024 tiles, vs. today's ~40KB of raw spike floats.
- This also retires the fragment shaders' hardcoded 4096-spike silent-drop limit (`spike_field.frag`, `raster_plot.frag`) — there's no per-spike loop anymore.
- `BulkSpikeFrame`/`PreviewPlayback` contracts (`neurocnl/neurosim/contracts/design_contracts.py`) gain a `tile_activity: list[float]` (or similar) field; `data`/`density_grid`/`grid_w`/`grid_h` and `scale_hint` are removed once the new renderer is the only consumer.
- Client-side rendering draws a fixed `tile_count` quads/frame regardless of scale — GPU cost becomes constant instead of scaling with neuron count. This, not the wire-protocol size alone, is what fixes the 100k/1M stutter (today's fragment shaders re-encode a full RGBA texture from spike data every frame).

## 4. Timeline scrubber

Reuse the existing play/pause/seek buffering pattern from `neurocnl/frontend/lib/providers/canvas/simulation_provider.dart`, but bounded to a **60-second rolling window** (ring buffer, ~1,800 frames at 30fps) rather than that pattern's unbounded full-history buffer — this demo can run indefinitely, so memory must stay bounded.

Out of scope for this iteration, noted for later: real hardware monitoring elsewhere in the app may want to reconstruct history from persisted snapshots rather than an in-memory ring buffer. The per-frame tile-stats schema above is simple enough to serialize later without rework, but no persistence is built now.

## 5. Interactivity

- **Hover/click a tile** → popup: core index, neuron count assigned, current activity level, current concentration.
- **Zoom/pan** the die view — useful on denser grids (e.g. SpiNNaker2's 152 tiles).
- No 3D tilt/rotation — the die stays a flat 2D grid.

## 6. Visual style

- Die boundary: sharp rectangle, straight grid lines, square tiles (chosen over a rounded/organic boundary and over hexagonal tiles — reads honestly as a chip die, not anatomy).
- Color scale: blue → red for activity level.
- Per-tile concentration cue: soft-edged square gradient (see §2).

## Explicitly out of scope

- Literal 3D brain mesh or anatomical layout.
- Persisted/reconstructable history (noted as a future direction for real hardware monitoring, not built here).
- Any change to real hardware deployment/monitoring screens, or to the native wgpu renderer — this redesign is scoped to `/viz-demo`'s existing Dart/fragment-shader pipeline only.

## Files expected to change

- `neurocnl/neurosim/app/services/poisson_demo_generator.py` — per-tile aggregation instead of raw spike/density_grid generation.
- `neurocnl/neurosim/contracts/design_contracts.py` — `BulkSpikeFrame`/`PreviewPlayback` payload shape.
- `neurocnl/neurosim/app/routers/viz_demo.py` — handshake gains a `target` field (chip name or `"simulated"`) alongside existing `scale`/`grid_w`/`grid_h`.
- `neurocnl/frontend/lib/widgets/canvas/viz_demo_provider.dart` — decode new payload shape.
- `nmtk_ui_core/lib/visualization/` — new tile-grid renderer replacing `fragment_shader_renderer.dart`'s three shaders (or a new renderer type alongside it); `renderer_interface.dart`'s `VisualizationFrame` model updated for tile data.
- `neurocnl/frontend/lib/screens/viz_demo_screen.dart` — target dropdown, timeline scrubber, tile hover/click/zoom-pan interactions.
- A new small module/constant list mirroring `Neurochip/neurochip/targets/*.json` core counts for the frontend's target dropdown (or read from an existing shared source if one already exposes this to the frontend — check `deploy_target_catalog.dart` first).
