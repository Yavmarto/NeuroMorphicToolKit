# CEL-162 (CEL-137): Feasibility — 3D brain visualization as a network-view mode

## Verdict

**Feasible, and mostly already built.** Do not port FounderOS-DEMO's code — there is nothing there to port at the rendering-stack level, and the native reimplementation this issue asks for already exists on this branch in a more advanced form than the reference repo. The open item is wiring **live training data** into the newest (true 3D, per-neuron) renderer; everything else asked for is done or trivially reachable.

---

## 1. What FounderOS-DEMO actually is

Cloned and inspected `github.com/Bennettxai/FounderOS-DEMO` directly (not just the README). It is a Next.js personal-assistant app ("Founder OS"); its "brain" visualization is a themed knowledge-graph view of the founder's org/tools/tasks, not a neuroscience visualization.

- **Rendering stack: plain React + inline SVG.** No three.js, no WebGL, no `<canvas>` even — `grep` for `three|webgl|WebGLRenderer|OrbitControls` across `app/`, `components/`, `lib/` returns nothing. Physics/positioning uses `d3-force` (`forceSimulation`, `forceLink`, `forceManyBody`, `forceRadial`) to lay out nodes, then everything is drawn as SVG `<circle>`/`<path>`/`<text>` elements (`components/KnowledgeGraph.tsx`, `components/NeuralGraph.tsx`, `components/BrainViz.tsx`).
- **Data model:** nodes are `self | team | task | employee | person | tool` (the operator, life-pillar teams, SOP tasks, AI/human workers, software tools) on five concentric rings (`lib/knowledge-graph.ts`); edges are `pillar | sop | does | member | uses | reports | board`. There is no neuron/activation concept, no correlation matrix, no time-series signal anywhere — "co-activation clustering" has no analogue here. It's a decorative "brain" metaphor for an org chart.
- **Visual techniques worth noting** (all CSS/SVG, not engine features): frayed multi-strand "silky" edge bundles with per-strand hash-jittered bowing (`NeuralGraph.tsx`), hover-driven camera zoom via CSS `transform: scale()` toward the hovered node, radial-gradient glow layers, and a synced side-panel directory list.

**Conclusion for ask #1/#2:** there is no WebGL/3D stack to assess porting of — it's a 2D SVG graph. Nothing here needs (or benefits from) `webview_flutter` or a native bridge, and nothing here exceeds what's already implemented natively in this codebase (see §2). The only transferable ideas are cosmetic: strand-bundle edge rendering and hover-zoom-to-node, both cheap to add to the existing `CustomPainter` if wanted later — not a driver for a new view mode on their own.

## 2. What already exists in `nmtk/neuro_toolkit` (same branch)

This exact question was already investigated once before, for a *closer* reference (AIS-OS's `/3d-brain`, actual three.js/WebGL), in `current tasks/2026-09-10/CEL-144-ais-os-3d-brain-spike.md`. That spike's recommendation — native reimplementation on the existing `CustomPainter` stack, not an embed — was accepted and built out across CEL-139/140/141/142/146/148/149/155/147/156. Concretely, as of this branch:

- **`network_2_5d_view.dart`** (`Network25DView` / `Network25DPainter`) — perspective-projected "2.5D" renderer on a plain `dart:ui` `Canvas` (`Paint.shader` gradients for depth/glow, no GLSL/WebGL). Has a full orbit camera (`OrbitCamera`: drag-to-rotate, scroll/pinch-zoom, camera-aware hit-testing), a spherical `GlobeNetworkLayout` (golden-angle equal-area node placement), a glow-sprite core + orbit rings (CEL-147), co-activation cluster coloring, and filter-by-layer search.
- **`brainviz_force_3d_view.dart`** (new, 736 lines, currently uncommitted) — a **true 3D, per-neuron, force-directed** renderer (`CorrelationForceBrainvizLayout3D` in `force_directed_layout.dart`): correlation pairs drive both layout attraction *and* visible edges, node radius/glow scale with activity and correlation degree, density-aware glow falloff, same `OrbitCamera` reused from the 2.5D view.
- **`results_brainviz_panel.dart`** (new, uncommitted) — wires `BrainvizForce3DView` into the Results step as **`StudioResultView.brainviz`**, the 4th tab in `studio_result_visualizer.dart`'s `IndexedStack` alongside Architecture/Grid-Raster/Weights (CEL-156 moved brainviz out of the editor-mode `StudioViewMode.network` slot into here). It bins the stored raster into a sliding `CoactivationWindow`, computes a live `CoactivationSnapshot` as the shared playback clock scrubs, and clusters via `coactivationClusterIndices`.
- **"Fire together, wire together" is already fully implemented**, in `coactivation_correlation.dart`: a sliding-window Pearson correlation matrix over per-node spike-rate samples, union-find clustering at `r ≥ 0.5` (`kCoactivationClusterThreshold`), and `coactivationEdgeStrengths` mapping correlation onto edge brightness. This is data-model-complete for both the 2.5D and the new 3D renderer — nothing new needs to be computed for ask #4.
- **Live streaming activation data already exists at the transport layer**: `api_client.dart`'s `streamTrainingEvents` (SSE, `GET /training/jobs/{id}/events`) feeds `training_run_provider.dart` → `training_mode_provider.dart` (`Map<nodeId, rate>`) on every epoch. The now-being-removed editor-mode `Network25DView`/`StudioViewMode.network` consumed this live; the new `BrainvizForce3DView` does not yet — see blocker below.

**Working-tree note:** `studio_view_mode_provider.dart` (removing the `network` enum variant) and `network_studio_view.dart` (deleted) are currently modified/deleted but **uncommitted** — this matches CEL-156's intentional relocation of brainviz from the editor slot to the Results tab, not an accidental revert. Recommend committing that relocation (or otherwise reconciling the working tree) before cutting a follow-up implementation issue, so new work doesn't collide with it mid-flight.

## 3. Where it plugs in (answering ask #3)

The Results-tab integration asked for already exists: `StudioResultView.brainviz` sits alongside Grid/Raster/Architecture/Weights in the same `IndexedStack`/segmented-control pattern (`support.dart`'s `StudioResultViewUi` extension gives it `stackIndex = 3`), reusing the shared playback clock, orbit camera, and co-activation engine. That fully covers **post-hoc review**.

**Live-during-training is the actual gap.** `ResultsBrainvizPanel` only consumes a stored raster (`Map<String, List<double>>`) via `_binnedRatesForBin`; it has no path from `training_mode_provider`'s per-epoch SSE stream. To cover live mode the same way the old editor-mode view did:
- Add a live-data branch to `ResultsBrainvizPanel` (or a thin sibling widget) that listens to `training_mode_provider` while a job is running and feeds `CoactivationWindow.addSample` per epoch tick, falling back to the existing raster/`PreviewPlayback` path once the run completes — mirroring `coactivation_provider.dart`'s existing live/review auto-switch, which the 2.5D view already used.
- This is additive, not a redesign: `BrainvizForce3DView` already takes `activity`/`correlationMatrix`/`nodeClusterIndices` as plain constructor args, so it doesn't care whether the caller sourced them from a raster or a live stream.

## 4. Co-activation grouping mechanics (answering ask #4)

Already concrete and implemented, no new signal needed:
- **Signal:** per-node spike-rate samples (live: SSE epoch events via `training_mode_provider`; review: binned raster via `PlaybackRateSeries`/`_binnedRatesForBin`), fed into a sliding-window Pearson correlation (`CoactivationWindow`, capacity 120 samples, min 8 to start correlating).
- **Grouping:** union-find over node pairs with `r ≥ 0.5` → `nodeClusterIndices`.
- **Visual mapping:** cluster index → one of 6 accent colors (`kCoactivationClusterPalette`); in the 3D force view, the same correlation matrix additionally drives layout attraction (correlated neurons pull toward each other physically, not just color-match) — a stronger "wire together" signal than color alone, and something FounderOS-DEMO has no equivalent of at all.

## 5. Blockers / open decisions

1. **Live-training feed into `BrainvizForce3DView`/Results-tab brainviz is not wired** (see §3). This is the one real gap the issue asked to flag rather than guess past.
2. **Uncommitted working-tree state** (CEL-156's editor→Results relocation) should be committed/reconciled before a follow-up issue starts, to avoid two agents editing the same files concurrently.
3. Per-neuron force-directed layout (`BrainvizForce3DView`) is O(n²)-correlation same as the layer-level view; fine at current model sizes used in Studio raster exports, but worth a sanity check on the largest supported neuron counts before calling it final.

## Recommendation

No implementation needed to satisfy "port FounderOS-DEMO" literally — there is no reference code worth porting. Recommend closing this out as: reference-repo assessed and superseded by already-in-flight native work; open one small follow-up issue scoped only to "wire live training data into the Results-tab brainviz panel" (§3), plus a housekeeping step to commit the CEL-156 relocation currently sitting uncommitted in the working tree. Awaiting sign-off before cutting that follow-up.
