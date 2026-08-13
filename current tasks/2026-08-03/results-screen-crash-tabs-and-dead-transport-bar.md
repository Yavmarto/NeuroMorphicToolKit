# Results screen: tile-grid crash, dead transport bar, invisible controls, tab maze — 2026-08-03

Second pass on the Results step, after the first pass (same day, see
`results-screen-epoch-playback-and-live-architecture.md`, committed as
`2132eb32`) failed to fix the symptoms the user actually reported. The user
came back with a screenshot, a repeating `RangeError`, and four complaints.

## Why the first pass missed

It fixed the wrong widget and signalled a hierarchy that isn't real:

- It converted `_PlaybackToolbar` in `animated_snn_playback.dart` — the
  **Raster** view's transport. The invisible controls are `_TileGridPlayback`'s
  own transport row in `results_step.dart`, the **Grid** view.
- It kept `Network | Architecture` above `Grid | Raster` and tried to make the
  nesting legible with a divider and a bolder font. Grid and Raster are two
  renderings of the same spike data, so there was no hierarchy to signal.

## Root causes found (each differed from the obvious guess)

1. **`RangeError` every paint.** `_buildFrames` sized the value buffers to
   `neuronCount` but set the grid to a padded near-square, so
   `tileRows*tileCols >= neuronCount` (1000 neurons -> 32x32 -> 1024 tiles,
   1000 values). The painter's only guard compared the index against
   `tileCount` — which *is* `rows*cols` — so it was tautological dead code that
   could never fire. No test covered a non-perfect-square grid.
2. **Dead transport bar — not the crash.** Flutter catches paint exceptions and
   still submits the frame. The real cause:
   `frameCount = ceil(duration / 40.0).clamp(1, 240)` where `duration` is the
   *timestep count* (dt = 1 ms). A typical raster is 20-32 timesteps, so
   `frameCount` was **1**: `Slider(min: 0, max: 0)`, an immovable thumb, a
   permanent "1/1", and every spike binned into one window so nothing animated.
3. **Invisible controls — not stale `AppTheme` tokens.** `results_step.dart`
   has zero bare `AppTheme.` statics. That row specified *no colours at all*
   and inherited Material 3 defaults from the Zeta `ColorScheme`, which
   populates only 9 slots and builds its dark theme from the same palette plus
   `copyWith(brightness: dark)`. So `surfaceContainerHighest` fell back to
   `surface` — the slider track painted in the panel's own background — and
   `onSurfaceVariant` fell back to a light-theme foreground.
4. **Tab maze.** Six switching controls across three `State` classes;
   `_SidebarTab` served four unrelated roles; `_selectedBucket` existed **twice**
   as independent state so the sidebar's layer choice didn't move the main view;
   the same export was fetched twice, with the sidebar's fetch passing no
   `epoch` (pinned to the latest capture forever).
5. **Scrubber counted the wrong thing.** `epochs` was every streamed event —
   one per training epoch, one per validation pass, and one per eval *test
   batch*, whose `epoch` field is a batch index. Hence "Epoch 6 / 27" for a
   5-epoch run.

## What changed

**Crash (two layers).** `_buildFrames` now allocates `rows * cols`; padded
tiles stay 0.0 and render inactive. In `nmtk_ui_core`, `TileActivityFrame`
gained `filledTileCount` (min of `tileCount` and both buffer lengths) and the
painter, hit-test, and hover popup all bound against it. The popup is
re-checked at the call site too, since a hover index captured on a larger frame
outlives its frame when the layer changes.

**Transport bar.** `_frameDurationMs` 40.0 -> 1.0 (one frame per timestep), so
a 25-timestep raster gives 25 frames and a real slider range — which also fixes
the sub-perceptual contrast, since activity now resolves to a crisp 0/1 per
timestep. The row is hidden entirely for a single-frame capture instead of
shipping an inert control, and `_TileGridPlaybackState` gained the missing
`didUpdateWidget` (it built frames only in `initState`, so a new epoch's data
arriving on the same keyed State kept replaying the old frames).

**Colours.** Explicit `AppTheme.textSecondaryOf(context)` on the icon and
counter, and a `SliderTheme` with Zeta colours copied from the working pattern
in `parameter_explorer.dart`.

**One flat tab row.** `_MainView` -> `_ResultsView { architecture, grid, raster }`
with an explicit `stackIndex` (the old code reused `Enum.index` as the
`IndexedStack` index, which is why enum order and on-screen order silently
disagreed). `_NetworkPlaybackPanel` is now presentational and takes the render
mode as a parameter.

**Keystone: the activity fetch moved up into `_ResultsStepState`**, which
resolved five things at once — duplicate HTTP, the two divergent layer
selections, the sidebar/main-view epoch disagreement, the tab row vanishing
behind a bare spinner mid-refetch, and the scrubber having no access to the
captured-epoch list for its ticks.

**Layer picker** is now one labelled dropdown, not a second row of pills, with
friendly names: new `resolveActivityLayerLabels` in `canvas_projection_utils.dart`
maps the slugged bucket key (`nir_lif_1785492030598`) back to its canvas node
using the same normalization rule as the neighbouring
`matchSpikeRatesToNodeIds`, falling back to the node's type ("LIF 1"/"LIF 2")
rather than the raw id.

**Scrubber** walks train-phase events only, labelled with the real epoch number,
with tick marks under epochs that have a captured snapshot. The accuracy chart's
marker now matches on epoch number (a train-phase selection can never match a
val-phase event by identity, so that marker was always absent).

**Also:** the spike-rate overlay now clears when an epoch carries no rates
(previously write-only, so badges lingered and misattributed themselves); the
`right: 264` hardcoded twice against a sidebar that animates 240<->80 now
derives from the sidebar's real width, with the sidebar reading the same
constants; and the Node Inspector's `nodeType`, computed but never rendered,
now shows as a Type row.

## Deliberately not done

- **The eval-path activity capture overwriting the final training epoch's
  slot** (`notebook.py:2870`) was in the approved plan as a correctness fix. On
  reading the surrounding comment it is *documented as intentional* — "being a
  real held-out sample rather than a training batch, it deliberately takes
  precedence". Reversing a documented decision was not mine to make here, so it
  was left alone. Worth a deliberate decision if the "Nearest capture: epoch N"
  label should distinguish held-out samples from training batches.
- Per-layer sparklines and live auto-follow (proposals, not defects).
- The ~322 bare `AppTheme.` statics in 30 *other* files — unrelated to this
  screen.

## Verification

- `nmtk_ui_core`: 174 tests pass, analyze clean. The new padded-grid test was
  confirmed to **fail** without the fix, reproducing the user's exact error
  shape (`RangeError (length): Invalid value: Not in inclusive range 0..9: 10`
  against their `0..999: 1000`).
- New `frontend/test/screens/results_step_test.dart` (3 tests) pins the flat
  tab set, the epoch-count semantics, and — by settling at all — the absence of
  the build->setState->build loop. The epoch test was likewise confirmed to fail
  without the phase filter.
- Full frontend suite back to its exact pre-existing baseline: one unrelated
  failure in `setup_step_local_import_test.dart` (`shared_preferences`
  `MissingPluginException`, reproduces standalone).
- `flutter analyze` clean on every touched file, `dart format` applied.

**One real bug was introduced and caught during this work**: the per-build
post-frame fetch trigger called `setState` unconditionally when no job id was
present, producing an infinite rebuild loop that hung 21 `studio_screen_test`
cases on `pumpAndSettle`. Fixed with a `(platform, epoch)` request-key guard;
those tests now pass in 6s.

## Restart / where to look

No backend or server restart needed — Flutter-side only, plus the
path-dependency package `nmtk_ui_core`. Run `flutter run -d macos` from
`nmtk/neuro_toolkit`, connect to `192.168.2.90`, open a completed run's Results
step: one tab row (Architecture | Grid | Raster), a legible and draggable
transport bar over the grid, "Epoch N / <train epochs>" with ticks, and a clean
console including when hovering the grid's bottom-right corner.
