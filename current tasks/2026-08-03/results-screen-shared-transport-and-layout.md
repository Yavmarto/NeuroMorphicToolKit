# Results screen: one shared transport, real speed control, no overlays — 2026-08-03

Third pass, after the user sent screenshots of both spike views. Round 2
(`results-screen-crash-tabs-and-dead-transport-bar.md`, committed as `86bcc5ef`)
fixed the crash and the tab maze but left the Grid view unusable.

## What the user reported, and what was actually wrong

1. **"Flickering boxes."** Round 2 set one frame per simulation timestep, which
   made spikes temporally exact and visually useless: spikes are sparse and
   binary, so every tile blinked independently — a strobe.
2. **"Autoplays at random moments."** The grid started playing on load *and*
   restarted whenever frames rebuilt, which after round 2 meant on every epoch
   and layer change. The raster had always opened paused.
3. **"Cannot control the speed."** The grid had no speed control at all — but
   the raster's ½×/1×/2×/5× buttons were **also inert**, which the screenshots
   hid. `_wallDuration` computed `max(4s, duration * 0.03 / speed)`: for any
   capture short enough to hit the 4-second floor — i.e. every real one at 20-32
   timesteps — all four speeds produced identical playback. The chip highlighted
   and nothing changed.
4. **Redundant labels.** "LIF 2 — Activity" printed directly under a
   "Layer LIF 2" dropdown, with "Nearest capture: epoch 1" as a third epoch
   readout.
5. **Overlays.** The epoch scrubber, share banners and Share/Deploy card all
   floated over the visualization.

Root cause behind 1-3: the two views had **six** independently-drifted
behaviours (autoplay, looping, scrub-resume vs scrub-pause, speed control,
reduce-motion handling, single-frame guard) because each carried a private
transport. There was no shared playback widget anywhere in the repo.

## What changed

**New `widgets/canvas/spike_playback_transport.dart`** — `SpikePlaybackTransport`
(play/pause + speed chips + ms readout + themed seek slider) and
`spikePlaybackWallDuration()`. Both views now use it, so the controls are
identical by construction rather than by convention. The wall-duration function
applies the floor to the *base* duration and lets speed divide the result, which
is what makes the speed buttons work at all. The raster's slider was previously
unthemed — an invisible track on this app's dark theme — and now inherits the
explicit theming.

**Grid (`_TileGridPlayback`)** — swapped `Timer.periodic` + frame index for an
`AnimationController` with the raster's semantics, deriving the frame index from
the clock and pushing to the tile renderer only on change (no per-tick
`setState`; the transport is scoped in an `AnimatedBuilder`). Opens paused. Added
spike persistence in `_buildFrames`: a spike lights its tile fully and decays at
0.78/frame, so activity reads as a trail. Verified numerically — a spike walks
the renderer's 10-step blue scale s9→s7→s5→s4→s3→s2→s1 over ~9 frames and clears
the glow gate after 13, so it neither strobes nor washes out.

**Labels** — `AnimatedSnnPlayback` gained `showHeader` (default `true`, so
`simulator_panel.dart` keeps its header); the Results step passes `false`. The
"Nearest capture" line moved into the epoch bar, so epoch info appears once.

**Layout** — the sidebar is now an in-flow `Row` child instead of a `Positioned`
overlay, which deleted `_sidebarInset` and the three call sites that manually
compensated for it, and structurally guarantees nothing floats over the
visualization. The epoch scrubber and layer picker merged into one compact
context bar at the top, placed **outside** the tab row's horizontal
`SingleChildScrollView` (a slider inside a horizontal scrollable fights it for
drag gestures). The entire bottom `Positioned` is gone: share banners became
`NmtkSnackBars` toasts (already the studio idiom, see `workspace_file_io.dart`),
and Share/Deploy moved into a sidebar footer.

**Deploy** — opens as a modal dialog via a new shared `showResultsDeployDialog`,
used by both the Results step and the comparison view, which carried a
near-identical duplicate of the whole bottom panel (banners, 360px inline deploy
card, its own hardcoded `right: 16 + 240 + 16`).

Net **−187 lines** across the two screens, from deleting the duplication.

## Test work

- Split `_seedTrainingHistoryAndExpandDeploy` into `_seedTrainingHistory` /
  `_openDeployPanel`. Six Manage-Targets tests reached the screen *underneath*
  the panel via `_openManageTargetsFor`, which a modal barrier blocks; they only
  ever needed the seed, so the deploy expansion was incidental coupling. Also
  replaced the helper's silent `if (tester.any(...))` guard with a hard `expect`
  — it previously no-opped when the finder stopped matching, surfacing as a
  confusing failure far from the cause.
- The Akida-readiness test needed restructuring (seed → Manage Targets → back →
  *then* open the dialog), and its provider override reused one Notifier
  instance, which Riverpod rejects once the panel mounts in a route rather than
  staying inline. Now creates a fresh instance per build.
- New `test/widgets/canvas/spike_playback_transport_test.dart` (5 tests). The
  wall-duration cases are the valuable ones: they pin the speed fix directly
  (1× = 4000ms, 2× = 2000ms for a 25-timestep capture — previously both 4000).
- New Results-step test asserting Share/Deploy render in the sidebar and the old
  "Hide Deploy" affordance is gone.

## Verification

- `flutter analyze lib/ test/` — **0 errors**.
- Full suite **1657 passing**, 1 failure: the pre-existing, unrelated
  `setup_step_local_import_test.dart` (`shared_preferences`
  `MissingPluginException`, reproduces standalone). Baseline was 1651 + 6 new.
- Ran the seven at-risk deploy/responsive files explicitly; all green.
- A 25px `RenderFlex` overflow appeared in the deploy dialog at 390px width,
  caught by `studio_responsive_audit_test.dart`. Diagnosed with a throwaway
  probe rather than guessing (it was the dialog header row) and fixed by making
  the title `Expanded` + ellipsis. Probe deleted.

**Process note:** a `dart format lib/ test/` reformatted 43 unrelated files. All
formatting-only churn was reverted so the diff contains only intended work —
worth using narrow paths next time.

## Not done / deliberately left

- `_ComparisonMetricsTable` (`results_comparison.dart:229`) is dead code
  superseded by the inline `_TableHeaderRow`/`_TableDataRow` build. It was
  already unreferenced at HEAD; surfaced now only because this round re-analyzed
  the file. Out of scope.
- The eval-path activity capture overwriting the final training epoch's slot
  (`notebook.py:2870`) remains documented-as-intentional; still untouched, still
  worth a deliberate decision.

## Restart / where to look

Flutter-side only, no backend or server restart. `flutter run -d macos` from
`nmtk/neuro_toolkit`, connect to `192.168.68.53`, open a completed run's Results
step:

1. Grid and Raster show the same transport (play/pause, ½×/1×/2×/5×, ms readout,
   themed slider).
2. Neither autoplays; changing epoch or layer doesn't start playback.
3. Speed buttons visibly change the rate in **both** views — this never worked
   before at these durations.
4. Grid reads as fading trails, not blinking.
5. Nothing floats over the visualization; epoch bar at top, sidebar beside it.
6. No "LIF 2 — Activity" under the Layer dropdown; epoch info appears once.
7. Share/Deploy in the sidebar; Deploy opens a dialog; share status is a toast.
8. The Run step's simulator panel still shows its population header.
