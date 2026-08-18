# Merge the 3 simulator deploy targets into one table

## Ask

Deploy step for `snntorch_sim`/`lava_sim`/`sc_neurocore_sim` showed one
full-page workspace per target, reached by picking each individually from
the deploy-target dropdown, with its own copy of Timesteps/Seed/Firing
Rate/dt. User asked for: one combined table (row per target), shared
runtime parameters where possible, a per-row popup to override just that
target's settings, and a single "Run all" button top-right.

## What changed

- **`lib/models/simulator.dart`**: added `SimulatorOutcome` +
  `SimulatorStatusOutcome` extension — the one place that decides which
  `SimulatorStatus` values count as success/failure/caveat, now shared
  between the Deploy status card and the new table's row badges (previously
  only the status card had this mapping).
- **`lib/providers/simulator_provider.dart`**: added `setAll()` to
  `SimulatorSettingsController` (bulk-replace a backend's settings) and two
  new hand-written (non-codegen) providers —
  `simulatorSharedSettingsProvider` (one `SimulatorSettings` value) and
  `simulatorOverriddenBackendsProvider` (`Set<String>` of backends with
  their own settings). Hand-written rather than `@riverpod`-generated since
  this is plain file-local UI state with no async/family dimension — avoids
  a build_runner regeneration for something codegen wouldn't add value to.
- **`lib/widgets/simulator_panel.dart`**:
  - Extracted `runSimulatorBackend(ref, backend)` (was inline in
    `SimulatorParametersSection.handleRun`) so "Run all" and the table's
    per-row Run button trigger a run exactly the same way as the existing
    per-target Run button always has.
  - `SimulatorParametersSection` gained an optional `onAnyFieldChanged`
    callback (backward compatible, defaults to nothing) — the table's
    per-row settings dialog uses it to flip a target into "overridden" the
    moment its fields are hand-edited.
  - `_IntField`/`_FloatField` → renamed public `LabeledIntField`/
    `LabeledFloatField` (purely mechanical rename) so the new shared-settings
    card, which lives in a different file, can reuse them instead of
    duplicating the numeric-input widgets.
  - `_DeployRunStatusPane`'s done-view status mapping now reads
    `result.status.outcome`/`.outcomeLabel` instead of its own inline
    switch, per the dedup above.
- **`lib/screens/studio/deploy/simulator_deploy_workspace.dart`**: full
  rewrite. `_StudioSimulatorDeployWorkspace` no longer takes a
  `selectedTarget` — it always renders all three
  (`kSimulatorDeployBackends`) as rows in one `NmtkSectionCard`-per-target
  list, regardless of which of the three was picked from the dropdown.
  Structure: title row + "Run all" button → shared-settings card
  (`Timesteps`/`Seed`/`Firing Rate`/`dt`, cascades to every non-overridden
  backend) → one row per target (label, current-settings recap, run-status
  badge, pin icon when overridden, gear → settings dialog, small Run
  button).
- **`lib/screens/studio/deploy/deploy_target_workspace.dart`**: dispatch
  switch's three simulator cases now construct
  `_StudioSimulatorDeployWorkspace(isCompact:)` without `selectedTarget`.
- **`lib/screens/studio_screen.dart`**: added the three imports the new
  table code needed that weren't previously imported at this level
  (`models/simulator.dart`, `providers/simulator_provider.dart`,
  `widgets/labeled_parameter_grid.dart`) — the old per-target setup pane
  only ever used the higher-level `SimulatorParametersSection` widget, never
  these symbols directly.

### Override model

No manual toggle switch. A target's row starts "matching shared" (pin icon
absent); editing ANY field in its settings dialog marks it overridden
(pinned) automatically via `onAnyFieldChanged`, and a "Reset to shared
settings" button in that same dialog un-overrides it and snaps its values
back to the current shared card. The shared card's own edits skip any
backend currently in the overridden set.

### Not done / deliberately deferred

- **Mobile compact action dock**: the old per-target setup panes wired a
  `_MobileDeployActionReporter` so a compact-width Deploy view got one
  primary action in the bottom dock. The new table has no equivalent yet —
  at narrow widths there's no bottom-dock action, just the in-row Run
  buttons and top "Run all". Updated
  `test/screens/studio_responsive_audit_test.dart`'s
  `compact Deploy dock follows executable targets…` test to expect this
  (moved `snntorch_sim` into the "no dock action" bucket, next to
  `sc_neurocore_fpga`/`brian2`) rather than silently leaving a stale
  assertion for when the unrelated pre-existing `lava` mobile-action bug
  (see below) eventually gets fixed and this test starts actually running
  that far.
- **`lava_workspace.dart` untouched on purpose**: the hardware `'lava'`
  deploy target has its own internal sim/hw toggle that also drives the
  `lava_sim` backend's `SimulatorExecutionPane`/`SimulatorParametersSection`
  when in sim mode. That's a different navigation path (via the hardware
  Lava target, not the standalone `lava_sim` catalog entry) and correctly
  shares the same underlying `simulatorSettingsProvider('lava_sim')` state —
  left alone.

## Tests updated

- `test/widgets/standard_deploy_layout_parity_test.dart`: split the 3
  simulator ids out of the `NmtkDeployLayout`-per-target loop into a new
  loop asserting the combined table (`Key('simulator-targets-table')`) and
  all three rows render regardless of which sim id was in the URL.
- `test/screens/studio_responsive_audit_test.dart`: moved `snntorch_sim`
  out of the "owns the compact primary action" loop into the "no dock
  action" loop (see above).
- `test/widgets/deploy_targets_no_nested_cards_test.dart`: untouched,
  verified still green — it only covers the dropdown/selector area, which
  didn't change (still lists all three simulator ids individually).

## Verification

- `flutter analyze` — clean, whole project.
- `flutter test` across `standard_deploy_layout_parity_test.dart` (12/12),
  `deploy_targets_no_nested_cards_test.dart` (4/4), `simulator_panel_test.dart`
  (31/31), `run_step_test.dart` (7/7), `studio_responsive_audit_test.dart`
  (same 3 pre-existing unrelated failures as every prior round today —
  stepper-accordion width, the pre-existing `lava` mobile-action bug, Deploy
  Artifacts header — none new).
- **Not visually verified** — no browser/simulator surface for this macOS
  Flutter app in this session. Run `flutter run -d macos`, open Deploy,
  select any of snnTorch/Lava/SC-NeuroCore (Simulation), and check: all
  three rows render; editing the shared card's Timesteps updates all three
  rows' recap text; opening a row's gear, editing Seed, and closing pins
  that row (settings recap changes independently of further shared edits);
  "Reset to shared settings" un-pins it; "Run all" and each row's own Run
  button both work.
