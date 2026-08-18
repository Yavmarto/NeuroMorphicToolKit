# Run / Deploy / Review results panels — differentiate instead of duplicate

## Problem

Run, Deploy, and Review all rendered the same result widgets, so the three
steps looked like the same screen three times:

- Run's Grid/Raster/Weights tabs instantiated the exact same
  `_StudioResultVisualizer` (`results_step.dart`) Review uses for its
  Architecture/Grid/Raster/Weights tabs — same charts, same data.
- Deploy's simulator/lava-sim inference pane
  (`SimulatorExecutionPane(showResults: true)`) duplicated the Activity/Report
  tabs that Review's `SimulatorResultsPanel` already shows once a run
  completes. Every other deploy target (Akida, PYNQ, hardware-mode Lava)
  already followed the "controls only, charts live in Review" pattern — only
  the software-simulator path hadn't been switched over, despite
  `SimulatorExecutionPane` already shipping a `showResults: false` path
  (`_ResultsMovedToReviewNote`) for exactly this.

## Fix

- `results_step.dart`: `_ResultsViewSwitch` takes an optional `views` list
  (defaults to all four, so Review is unchanged).
- `run_step.dart`: both `_ResultsViewSwitch` instances now pass
  `views: _runResultViews` = `[architecture, raster]`. Run is a live
  health-check (is training/inference working right now — spike raster +
  `_MetricsSidebar`), not a second Review. Grid and Weights only ever
  replayed the finished run, which Review already shows.
- `simulator_deploy_workspace.dart`, `lava_workspace.dart`: sim / lava-sim
  inference pane now passes `showResults: false`, matching every other
  target's Deploy pane (controls + readiness only; setup pane stays on the
  right; charts appear in Review).
- Updated the doc comment and setup-pane copy in
  `simulator_deploy_workspace.dart` to stop claiming charts render in Deploy.
- `test/screens/studio_responsive_audit_test.dart`: updated the two Run-step
  assertions that expected all four tabs to expect only Architecture/Raster,
  and switched `.grid` probes there to `.raster`.

## Verification

- `flutter analyze` on the 4 changed lib files: clean.
- `flutter test test/screens/studio_responsive_audit_test.dart`: 27/30 pass.
  The 3 failures (`floating controls stay separate on desktop`, `lava should
  own the compact primary action`, `Deploy artifacts - Header metrics...`)
  reproduce in isolation and touch code this change never edited
  (`studio-workflow-accordion` sizing, lava mobile action, Artifacts step).
  They come from a pre-existing **uncommitted** WIP already in the tree before
  this task started — `git diff --stat` shows unstaged changes in
  `studio_screen.dart`, `akida_workspace.dart`, `pynq_workspace.dart`,
  `sc_neurocore_fpga_workspace.dart`, `studio_standard_deploy_page.dart`, and
  `nmtk_ui_core/lib/widgets/deploy_layout.dart` (an `NmtkDeployLayout.subtitle`
  removal mid-propagation) — none of it touched by this task.
- `flutter test test/widgets/simulator_panel_test.dart`: 23/23 pass.
- `flutter test test/screens/run_step_test.dart`: 7/7 pass.

## Not done here

The pre-existing uncommitted refactor above (subtitle removal cascading
through deploy workspaces + `studio_screen.dart`) is unrelated WIP and was
left untouched — it predates this task and isn't part of the Run/Deploy/
Review redesign.

## Follow-up round: fill the Deploy pane, simplify the raster's epoch controls

After the first round, the user pointed out the Deploy step's left pane
(sim/lava-sim targets) was now just empty space where the charts used to be,
asked what the fourth Run tab (they only remembered three) had been, and
asked for a specific raster cleanup from an annotated screenshot.

**Missing tab:** Grid (the tile-grid chip-die renderer) — the other three
they recalled (Architecture, Raster, Weights) were right.

**Deploy pane** (`simulator_panel.dart`, `_SimulatorExecutionPaneState`):
replaced the empty placeholder/note with a real status pane, scoped to the
`!showResults` (Deploy) path only — the `showResults: true` path (still used
by the separate standalone `SimulatorPanel` widget/tests) is untouched.
- Idle: short explainer of what Run does and where full results end up.
- Running: spinner + a wall-clock elapsed-time readout, ticked by a local
  `Timer.periodic` — `SimulatorRunResult.durationSeconds` is *simulated*
  time, not wall time, so elapsed/completion timestamps are tracked locally
  in `_SimulatorExecutionPaneState` (`_runStartedAt`/`_completedAt` via
  `ref.listen`) rather than added to the model for a Deploy-only display.
- Done: status pill (completed/failed/ran-with-caveats, mapped to
  `NmtkShellTokens` semantic colors), backend, duration, total spike count
  (summed across all populations), and a wall-clock "ran at" time — no
  "open in Review" button, per explicit instruction to leave that out.

**Raster epoch controls** (`results_step.dart`,
`_StudioResultVisualizerState`): removed the epoch-scrubber slider
(`_EpochScrubber` + its tick painter, now fully dead code, deleted) from
both the compact and desktop context-bar layouts, keeping the "Epoch N / M"
counter text and the loop toggle. Also removed the redundant epoch-level
play/pause icon that sat next to the counter — deleting it is the actual
"merge into one button" fix: that icon called
`_epochPlaybackSession.toggle()`, which is the *exact same call* the spike
view's own `SpikePlaybackTransport` play button already makes when a session
is passed in (`_TileGridPlaybackState`/`_AnimatedSnnPlaybackState._togglePlay()`
both delegate to `session.toggle()`). The two play buttons were always
wired to the same action; only the UI was duplicated. With the outer button
and the slider gone, the transport's play/speed row (already the first
thing rendered inside the raster/grid view) is now the sole play control and
sits directly under the shortened context bar — no controller-lifting
refactor needed, since "play all epochs" was already implemented via
`_advanceEpochPlayback`'s `onPlaybackComplete` callback advancing
`_scrubberEpoch` each time a clip finishes while the session is playing.
Also deleted `_toggleEpochPlayback` and `_capturedScrubIndices`, both now
unreachable.

**Verification:** `flutter analyze` clean on both files;
`flutter test test/widgets/simulator_panel_test.dart` 31/31,
`test/screens/run_step_test.dart` 7/7,
`test/models/studio_result_visualization_test.dart` +
`test/screens/results_comparison_data_test.dart` all green;
`studio_responsive_audit_test.dart` still 27/30 — the same 3 pre-existing,
unrelated failures as the first round, no new ones.

**Manual verification still needed:** none of this was visually checked in
a running app (no browser/simulator surface for this macOS Flutter app in
this session's tools) — run `flutter run -d macos` and look at Run's raster
tab and Deploy's sim-target pane before considering this visually done.

## Correction: Run's Grid/Weights restriction was wrong, reverted

The first round's premise — "Grid/Weights only replay what Review already
shows" — is only true for the `akida`/`lava`/`pynq` deploy targets, where
Review's `_AkidaVisualizationPanel`/etc. wrap the *same*
`_StudioResultVisualizer` Run uses. For the simulator-family targets
(`snntorch_sim`/`lava_sim`/`sc_neurocore_sim` — `kSimulatorDeployBackends`
in `deploy_results_provider.dart`), `_DeployReviewBody`
(`deploy_review_step.dart:113`) renders `SimulatorResultsPanel` instead —
Activity/Report tabs over a *different* dataset (the simulator's own
inference run), with no Grid or Weights concept at all, ever. For those
targets Run was the *only* place Grid/Weights training diagnostics were
reachable, and restricting Run's tabs deleted them with no fallback —
exactly what the user hit and couldn't find in Review, because they were
never there to begin with.

Reverted: `run_step.dart`'s two `_ResultsViewSwitch` call sites no longer
pass a restricted `views` list (both deleted, along with the now-unused
`_runResultViews` constant), and the `views` param was removed from
`_ResultsViewSwitch` in `results_step.dart` since nothing calls it anymore.
`studio_responsive_audit_test.dart`'s two Run-tab assertions are back to
expecting all four tabs. Verified: same 27/30 baseline (3 pre-existing,
unrelated failures), all four tabs render in Run again.

If Run/Review duplication for akida/lava/pynq specifically is still worth
trimming, the correct target is Review's wrapper
(`_AkidaVisualizationPanel` etc.), not Run — Run is the canonical home for
training-time diagnostics regardless of deploy target, not a duplicate of
anything for the simulator family. Not attempted here; flag separately if
wanted.

## Deploy status pane rebuild, after `/impeccable critique`

The first version of `_DeployRunStatusPane` (idle/running/done text floating
`Center`'d in the old charts' empty space) drew an `/impeccable critique` —
dual sub-agent (design review + a manual mechanical audit substituting for
the web-only detector, since this is a Flutter/Dart app with no DOM). Full
report persisted at
`.impeccable/critique/2026-08-17T21-00-32Z__neurocnl-frontend-lib-widgets-simulator-panel-dart.md`.
Findings and fixes, all in `simulator_panel.dart`:

- **Status icon lied for 2 of 3 outcomes** (fixed checkmark tinted red/amber
  for Failed/caveats) — now switches icon per outcome
  (`check_circle_outline`/`cancel_outline`/`warning_outline`), the same
  vocabulary `_PreflightBadge` already uses two hundred lines up in this
  same file.
- **Reinvented two widgets that already exist** — the hand-rolled status
  pill is now `_PreflightBadge` (reused, not a new pill); the `_kv` helper
  (a third near-duplicate of a pattern already twice in this file) is now
  `NmtkKeyValueRow` from `nmtk_ui_core`.
- **`ref.listen` mutated state without `setState`** in 2 of 3
  `_onRunStateChanged` branches — wrapped all three in `setState`.
- **`Center`-everything produced the reported void** — replaced with
  `Align(topCenter)` + fixed top padding in one shared `_DeployRunStatusCard`
  used by all three states, so switching states no longer jumps between
  inconsistent paddings/widths either.
- **Idle/Running showed nothing backend-specific** — both now say which
  backend ("Ready to run snntorch_sim" / "Running snntorch_sim… 12s").
- **No hierarchy on the actual numbers** — `NmtkKeyValueRow` steps values up
  to `bodyMedium`/w700/`mainPrimary` instead of the old plain `bodySmall`.
- Minor: false `ZETA-MIGRATION-EXEMPT` comment on a bolt icon that does have
  a Zeta equivalent (`ZetaIcons.flash_on`) — fixed; `CircularProgressIndicator`
  exemption now documented (Zeta's progress circle is determinate-only);
  elapsed-time formatting now zero-pads seconds to match
  `akida_execution_pane.dart`'s `_elapsedLabel` exactly; card width is a
  named, commented constant (`_DeployRunStatusCard._maxWidth = 360`) instead
  of a bare `260`.

Verification: `flutter analyze` clean; `simulator_panel_test.dart` 31/31;
`studio_responsive_audit_test.dart` 46/49 combined with the prior suite run
— same 3 pre-existing, unrelated failures, no new ones. Still not visually
checked in a running app.
