# CEL-144: AIS-OS `/3d-brain` view — feasibility + design spike

## Verdict

**Feasible as a native re-implementation of the visual/interaction style. Not feasible, and not recommended, as a literal code port (embedding the actual web app).**

Inspected the real source (`.claude/skills/3d-brain/assets/template/` in `nateherkai/AIS-OS`, not just the README): it's a Node-served static bundle built on `3d-force-graph` (`three.js` + `d3-force-3d`), with `UnrealBloomPass` for the glow, `CSS2DRenderer` for labels, and browser `OrbitControls` for drag-orbit/zoom. That's a WebGL renderer running in a browser — there is nothing in this repo to "port" into Dart; it would have to be embedded (`webview_flutter`) or re-implemented. NMTK has zero 3D/WebGL dependency anywhere today (confirmed on CEL-138) and the shipped-then-reverted CEL-139 renderer deliberately avoided one, using perspective-projected 2.5D on `CustomPainter` instead. Embedding the actual web app would be the first WebGL/3D dependency in the codebase, adds a Node bundle to ship and version inside the app, and is a known-bad fit for the mobile targets (iOS/Android `webview_flutter` WebGL support is inconsistent). Recommend against it.

The visual language is portable, though, and closer to what's already built than it looks:

| AIS-OS technique (source-verified) | NMTK equivalent today |
|---|---|
| Perspective 3D projection, nearer nodes larger | `network_2_5d_view.dart` already does perspective projection + z-sorted painting on `CustomPainter` (from CEL-139, currently mid-revert on CEL-143) |
| Node glow driven by note "heat" | Same file already drives node glow from live `activity` (spike rate) |
| Edge emphasis from wikilinks | Same file already drives edge strength from `edgeStrengths` (CEL-140 co-activation correlation) |
| Central glowing core + 2 orbit rings (`makeOrbitals`, additive-blend radial-gradient sprite texture) | New — a 2D canvas-texture glow sprite is the same trick AIS-OS itself uses (not true volumetric bloom), so it fits the existing `Paint.shader`/gradient painter family directly |
| Spherical equal-area node placement (`composeGlobe`: golden-angle per-category sector sampling) | New — pure layout math, no rendering dependency, straightforward Dart port |
| Drag-orbit + scroll-zoom camera (`ForceGraph3D`'s built-in `OrbitControls`) | New — needs an actual orbit camera (rotate the whole scene, not just re-run force relaxation), which the current 2.5D painter doesn't have |
| Search with keyboard nav | New — small, standard `TextField` + filtered list, same pattern as other Studio search UI |

Net: v1 needs a spherical/orbital layout, an orbit camera, and the glow-sprite treatment. It does **not** need a new rendering engine — the existing perspective-projection/`CustomPainter` approach validated on CEL-139 extends to this directly, because AIS-OS's own "glow" is also a 2D-canvas-texture trick, not true GPU bloom.

## Data mapping (the actual open question — AIS-OS has no neuron concept)

AIS-OS nodes = notes (categorized by `source`: meeting/entity/person/concept/page/document/...), edges = wikilinks + relation kinds, with health flags (`stale`/`quiet`/`orphan`/`stub`/`broken-links`) surfaced as attention indicators, plus search and a detail panel on click.

Mapping, reusing the CEL-138 decision (already validated, already partly built before CEL-143's revert):

- **Nodes = layers/components**, not raw neurons — same reasoning as CEL-138: per-neuron graphs (up to 100k+ neurons) aren't legible as a node graph at any rendering fidelity.
- **Node category/color = layer type** (input/hidden/output/module kind) — plays the role of AIS-OS's `source` category, which drives both node color and globe sector placement in `composeGlobe`.
- **Node size/glow = live activity** (spike rate from `training_mode_provider` during training, `PreviewPlayback` during review) — already wired in the reverted CEL-139 renderer.
- **Edges = two layers**: (1) actual model connections (`CanvasGraph`/`CanvasEdge`, always present), (2) co-activation correlation edges above a threshold (`coactivation_correlation.dart`, CEL-140/142, already built and threshold-clusters at 0.5) — this **is** the "fire together, wire together" grouping and plays the role of AIS-OS's wikilinks.
- **Health flags** (optional, not v1): a plausible analogue exists (e.g. "dead" = zero activity, "orphan" = disconnected layer) but nothing in the ask calls for it — skip for v1, note as a stretch idea only.
- **Search** = filter by layer/component name, same list-search pattern as elsewhere in Studio.

## Where it plugs in

Same integration point as the reverted view: `StudioViewMode.network` in `studio_view_mode_provider.dart`, alongside `cnl`/`nir`/`canvas`. Applies to both live training (subscribing to `training_mode_provider` per-tick rates, incremental camera/layout updates, not full relayout per tick) and post-run review (replaying stored `PreviewPlayback`), identical to the CEL-141 wiring pattern. If CEL-143's revert lands first, this proposal's implementation would rebuild the same slot and largely the same backbone (`CanvasGraph` topology, `coactivation_correlation.dart`, `training_mode_provider` subscription) — that reverted code is effectively the reusable substrate for this version, just with a different layout/camera/visual treatment on top.

## Scope/effort (incremental, assuming CEL-143's revert has landed)

- Spherical/orbital layout math (`composeGlobe`-equivalent, golden-angle per-category sectors): ~1-2 days.
- Orbit camera (drag-to-rotate, scroll/pinch-zoom) over the perspective-projection painter: ~2-3 days — the new piece the old renderer didn't need.
- Glow-sprite core + orbit rings (canvas-texture radial gradient, additive blend) + per-node glow reuse: ~1-2 days.
- Search UI: ~0.5 day.
- Rebuild topology/correlation/live-review wiring (CanvasGraph, co-activation correlation, StudioViewMode slot): ~2-3 days — this is a rebuild of CEL-139-142's backbone, not new design.
- **Total: roughly 1.5-2 sprints**, similar order of magnitude to the original CEL-139-142 body of work plus the new camera/layout delta.

## Risks

- **Coordination**: CEL-143 (revert) is running concurrently in this same workspace. If both land, the net result is: shipped view removed, then a visually different view rebuilt in the same slot with mostly the same data plumbing. Worth confirming with the user that this double-motion (ship → revert → rebuild-with-new-skin) is intended, versus restyling the still-shipped view in place.
- **Orbit camera correctness**: rotating a 2D-projected scene convincingly (matching AIS-OS's drag-orbit feel) needs care in the perspective-projection math; more finicky than the previous free-form force layout, but bounded — no new dependency, no engine risk.
- **Performance**: same O(n²) correlation caveat as CEL-138, unchanged since it's layer-granularity, not per-neuron.

## Recommendation

Proceed with a **native re-implementation** of the AIS-OS visual/interaction language (spherical layout, orbit camera, glow-sprite core) on top of the existing perspective-projection `CustomPainter` stack, mapped to layers + co-activation correlation as nodes/edges, in the same `StudioViewMode.network` slot for both live training and review. Do not embed the actual AIS-OS web app. Awaiting sign-off before cutting implementation child issues.
