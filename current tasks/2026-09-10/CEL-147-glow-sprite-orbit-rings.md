# CEL-147: Glow-sprite core + orbit rings

## Done

- Added `nmtk/neuro_toolkit/lib/features/neurocnl/utils/glow_sprite.dart` — additive radial-gradient disc + orbit ring helpers (AIS-OS canvas-texture trick, no WebGL).
- `Network25DPainter._paintOrbitalChrome` in `network_2_5d_view.dart`: central core (mean-activity pulse), white hotspot, two pitch-flattened orbit rings; drawn after background, before edges/nodes.
- Per-node activity glow unchanged.
- Tests: `glow_sprite_test.dart`, `network_2_5d_view_test.dart` — 19/19 green.

## Verify in app

Studio → Network view with a model that has layers. Expect violet core + two faint rings at centre; core brightens during live training activity.
