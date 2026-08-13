# Results grid: the rewind bug, continuous decay, no scroll-zoom — 2026-08-03

Fourth pass on the Results screen. Round 3
(`results-screen-shared-transport-and-layout.md`) unified the transport and the
layout, but grid *playback* was still wrong: "the whole duration says 25 ms, but
the actual play duration seems somewhat random, also sometimes it seems to react
on the mouse movement afterwards."

## Root cause — found in code, then confirmed by the user

Asked whether the thumb froze, finished, or rewound, the user answered **jumps
back to 0**. That matched what reading the code had already turned up:

`_NetworkPlaybackPanel.build` called `_resolveActivityRaster(data[layer])`, and
`NpyParser.extractSpikeRaster` allocates a **fresh `Map`** every call.
`_TileGridPlayback.didUpdateWidget` then compared `widget.raster !=
oldWidget.raster` — and `Map !=` is *identity* for `LinkedHashMap`, so it was
always true. Every rebuild ran `_loadFrames()` → `_controller..stop()..value =
0.0`.

The parent watches `canvasProvider` **unselected** (`results_step.dart:335`),
whose `CanvasState` carries live pan/zoom, plus the SSE-fed
`trainingHistoryProvider`. So playback survived only until the next unrelated
rebuild — arriving at an arbitrary moment. Hence "5 ms one time, 18 ms the next".

`AnimatedSnnPlayback` has **no `didUpdateWidget` at all**, which is exactly why
the Raster — the "good screenshot" from round 3 — never showed this.

The regression test reproduces it precisely: with the old comparison restored it
fails `Expected: >= 6.25 / Actual: 0.0`.

## What changed

**The rewind (two layers, deliberately).** `_ResultsStepState` now resolves the
raster once, memoised on the source array's *identity*, and passes the record to
both consumers — the panel and the sidebar's Dynamics tab, which were each
parsing the same export every build. And `_TileGridPlayback` takes an explicit
`rasterId` (`"layer@epoch"`) as its reload condition, so a `Map` identity can
never be that condition again. The first removes the false positive; the second
removes the ability for one to reset the clock.

**Continuous decay instead of 25 prebaked frames.** `_buildFrames` binned
`ceil(duration)` frames across a 4-second wall-clock floor: 6.25 updates per
second, next to a raster repainting at 60 Hz — the residue of "flickering boxes".
The state now holds per-tile sorted spike times plus a forward cursor, and each
ticker tick samples `spikeTrailIntensity(t - lastSpike)` — exponential decay with
`tau = 4 ms`, chosen because `exp(-1/4.02) ≈ 0.78`, the per-frame retention it
replaces. Cursors advance monotonically while playing (O(tiles) per tick, no
binary search) and rescan on a backward seek. This also *removes* the reload step
the rewind bug lived in.

Frames are allocated fresh per sample rather than mutating buffers: both gates in
the renderer are identity-based (`ValueNotifier`'s `==` short-circuit and
`shouldRepaint`'s `!identical`), so a reused frame object would repaint nothing.

**Scroll-zoom off.** `TileGridNeuronRenderer` gained `enableZoom` (default
`true`). An `InteractiveViewer` reads a trackpad two-finger scroll as a zoom, so
the grid scaled whenever the pointer crossed it. The Results step passes `false`;
`/viz-demo` and `canvas_simulation_surface.dart` keep the default. Hover and tap
inspection are untouched.

**Renderer repaint scoping.** While in `buildSurface`: pointer handling moved
*above* both notifiers (the callbacks read the current frame from the notifier
instead of capturing it), and the `CustomPaint` is now inside a
`RepaintBoundary`. The old frame-outer/hover-inner nesting rebuilt
`InteractiveViewer` + `MouseRegion` + `GestureDetector` on every pushed frame,
which mattered a lot more at 60 fps than at 6.

**The readout states both clocks:** `12.0 / 25 ms sim · 1.9 / 4.0 s`. 25 ms of
simulation takes 4 real seconds, and only the sim axis was ever shown.

## Tests

- `results_step_test.dart`: start playback, advance 1 s, push a training-history
  update, assert the slider has not rewound. **Verified to fail without the
  fix** (`6.25 → 0.0`).
- `spike_playback_transport_test.dart`: `spikeTrailIntensity` pinned numerically
  — 1.0 at the spike, ≈0.78 at 1 ms, ≈0.37 at tau, below the renderer's 0.05
  glow gate by 12 ms, and monotonic.
- `tile_grid_renderer_test.dart`: `enableZoom: false` drops the
  `InteractiveViewer` while hover still produces the tile popup; the default
  still zooms.
- New `test/support/activity_fixtures.dart` holds the NPY/zip builders. They
  existed as private copies in `npy_parser_test.dart`; that file now imports the
  shared ones rather than the repo carrying two NPY writers.

## Verification

- `flutter analyze lib/ test/` — **0 errors** in both packages.
- `nmtk_ui_core`: **176 passing**, all green.
- `neurocnl/frontend`: **1662 passing**, 1 failure — the pre-existing, unrelated
  `setup_step_local_import_test.dart` (`shared_preferences`
  `MissingPluginException`), confirmed to reproduce standalone.

**Not measured:** the painter draws a `MaskFilter.blur` per active tile, so 6.25
→ 60 fps multiplies that cost ~10×. The `RepaintBoundary` is the mitigation. If a
1000-neuron layer janks on macOS, throttle `_pushSampleAt` with a minimum `t`
delta (~30 fps) rather than reverting the interpolation. This needs the running
app to judge.

## Not done / deliberately left

- `AnimatedSnnPlayback` still has no `didUpdateWidget`, so `_firingRates` and
  `_voltageTraces` never recompute on a prop change. Safe only because the panel
  keys it; latent and pre-existing.
- Padded trailing tiles remain hoverable and their popup reports a fabricated
  `Neurons: ~N`, contradicting the doc comment in `tile_grid_renderer.dart`.
- `_tileAtLocalPosition` hit-tests against the cached `attach()` size while
  `paint()` uses the real canvas size, so `canvas_simulation_surface.dart`'s
  hover math is off by its label height.
- `duration = shape[0]` gives a 25 ms axis while samples run 0…24. Defensible
  (sample *t* occupies `[t, t+1)`) and changing it would move the raster too.

## Restart / where to look

Flutter-side only, no backend or server restart. `flutter run -d macos` from
`nmtk/neuro_toolkit`, connect to `192.168.2.90`, open a completed run's Results
step, Grid tab:

1. Press play and leave it — the thumb travels 0 → 25 ms **once** and stops.
2. While it plays, click around the sidebar, or let training history tick —
   playback keeps its position instead of snapping back to 0.
3. Tiles fade smoothly rather than blinking ~6 times a second.
4. Two-finger scroll over the grid does nothing; hovering a tile still shows its
   info card.
5. The readout names both clocks, so the 4-second wait on a 25 ms capture is
   explained on screen.
6. Raster tab unchanged; `/viz-demo` and the Run step's canvas simulation
   surface still zoom on scroll.
