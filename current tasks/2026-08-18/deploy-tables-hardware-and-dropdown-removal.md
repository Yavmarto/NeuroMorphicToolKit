# Real tables for Deploy, hardware table added, target dropdown removed

## Ask

Follow-up to the 2026-08-17 simulator-table merge. User pointed out the
"combined table" was actually stacked `NmtkSectionCard`s, not a real table.
Asked for: a genuine columnar table, a second table for hardware targets
(Akida etc.) above it, removal of the deploy-target dropdown entirely, and
less empty space between the stepper and the Deploy content.

## What changed

- **New file `lib/screens/studio/deploy/deploy_targets_overview.dart`**:
  `_DeployTargetsOverview` — the Deploy step's whole content now. Renders,
  in order: a **Hardware Targets** `DataTable` (Akida/PYNQ-Z2/Lava·Loihi2/
  SC-NeuroCore FPGA — always all four, one row each), the existing shared
  simulator-settings card, a **Software Simulators** `DataTable` (the three
  sim backends, replacing last round's card list), and — only when Setup has
  selected a codegen-only platform (brian2/sinabs/rockpool/pynn/nengo) — a
  row of small buttons to preview that target's generated code.
  - Both tables use Flutter's `DataTable`/`DataColumn`/`DataRow`/`DataCell`
    directly (`// ZETA-MIGRATION-EXEMPT: zeta_flutter has no table/data-grid
    component`), the same exemption already used by `NmtkQuantizationTable`
    in `nmtk_ui_core`.
  - Hardware table columns: Target | Status (paired device or "Not
    paired") | Trainable | a "Configure" button. Configure opens that
    target's **existing, unmodified** full setup/execution page
    (`_StudioAkidaWorkspace` / `_StudioPynqWorkspace` / `_StudioLavaWorkspace`
    / `_StudioScNeuroCoreFpgaWorkspace`) inside a `Dialog` — these pages
    (device pairing, overlay setup, benchmarking) are too involved to
    flatten into one row.
  - Simulator table columns: Target (+ pin icon if overridden) | Status |
    Settings recap | gear (settings dialog) + Run button. Behavior unchanged
    from the 2026-08-17 round (shared-settings cascade, per-row override).
  - Codegen preview buttons open `_CodegenPreviewPanel` the same way, in a
    dialog.
  - **Gotcha**: `DataRow.key` only feeds `Table`'s internal row-diffing — it
    is never attached to an actual widget, so `find.byKey` can't see it.
    Every row also wraps its first cell's content in a `KeyedSubtree` with
    the same key, matching how `_TargetDropdown` used to do the same thing
    for its per-item icons.
- **Deleted `lib/screens/studio/deploy/deploy_target_workspace.dart`**: the
  old `switch (selectedTarget) { ... }` single-target dispatcher. Nothing
  reads `selectedTarget` for *what to render* any more — the tables always
  show everything.
- **`lib/screens/studio/deploy/simulator_deploy_workspace.dart`**: removed
  `_StudioSimulatorDeployWorkspace` (the old per-page wrapper with its own
  scroll view and heading) and `_SimulatorTargetRow` (the `NmtkSectionCard`
  row) — both fully absorbed into the new file. Kept `_RunAllSimulatorsButton`,
  `_SharedSimulatorSettingsCard`, and the settings-dialog code untouched.
- **`lib/screens/studio/deploy/deploy_workspace_panel.dart`**: deleted
  `_TargetDropdown` (the `ZetaDropdown<String>`/single-label selector) and
  the header/`showHeader` plumbing around it. `_DeployWorkspacePanel` now
  takes the full `selectedDeviceLabels`/`selectedDeviceDataByTarget` maps
  (keyed by every hardware target id, not just "the selected one") and
  renders `_DeployTargetsOverview` directly.
- **`lib/screens/studio/studio_top_bar.dart`**: deleted `_DeployHeaderActions`
  — the top-bar's own copy of the same dropdown (shown on wide screens,
  floating below the stepper).
- **`lib/screens/studio_screen.dart`**: `deployHardware` no longer reserves
  the floating "below-stepper header row" (`showBelowStepperHeaderRow`) —
  that 56px + margin was solely for the now-deleted dropdown, and removing
  it closes most of the empty gap the user flagged between the stepper and
  the tables. `_buildDeployPanel` passes the full device-label/device-data
  maps instead of a single selected target's values.

### Deliberate behavior changes (disclosed, not just implementation detail)

- **Hardware targets now always show, regardless of what's ticked in
  Setup.** Before, Deploy only offered platforms Setup had selected — the
  dropdown filtered by `selectedPlatforms`. The hardware table drops that
  filter, for the same reason the simulator table already did in the
  2026-08-17 round: the user asked to see the table, not to re-derive
  Setup's selection state. Codegen targets keep the old Setup-gated
  behavior (their preview button only appears once selected), since they
  weren't part of this ask and gating them avoids clutter from five rarely
  used entries.
- **A hardware target's page is one tap further away.** Deep-linking with
  `?target=akida` still sets `selectedDeployTarget` (still drives
  validation/preflight scheduling), but no longer auto-opens Akida's page —
  the tables render unconditionally and "Configure" must be tapped. This
  matches the tables-first design but is a real UX change for anyone using
  that deep link to jump straight to a target's setup form.
- **Mobile compact bottom-action-dock no longer reaches hardware targets.**
  `Dialog`s open via `showDialog` sit outside `_MobileDeployActionScope`'s
  ancestry, so a hardware page's `_MobileDeployActionReporter` calls become
  silent no-ops once that page only exists inside a dialog. This extends the
  same deferral already accepted for the simulator table in the 2026-08-17
  round (see `project_simulator_targets_combined_table.md`) to hardware
  targets too — not requested, but a necessary consequence of moving every
  hardware page behind "Configure".

## Tests updated

- `test/widgets/deploy_targets_no_nested_cards_test.dart`: fully rewritten —
  was entirely about the now-deleted dropdown; now asserts the dropdown is
  gone, both tables render with all their rows, and a hardware row's
  Configure button opens/closes a dialog.
- `test/widgets/standard_deploy_layout_parity_test.dart`: hardware-target
  loop now opens each Configure dialog before asserting `NmtkDeployLayout`
  inside it (rather than expecting it inline); added a codegen-target loop
  (toggles Setup selection, opens the preview dialog); the "wide desktop
  side-by-side" test opens Akida's dialog first.
- `test/widget_test.dart`: the three `deploy-targets-dropdown` presence
  checks (used only as a proxy for "the Deploy panel rendered") swapped for
  the new `deploy-targets-overview` key.
- `test/screens/studio_responsive_audit_test.dart`: the "compact dock
  follows executable targets" test rewritten — no target owns the outer
  dock any more, so it now just asserts the dock is absent for every target
  id. The three Akida-specific mobile-dock tests (safe-and-unique at N
  widths, wraps cleanly at N text scales) rewritten to open the Configure
  dialog and check *it* renders safely, since the dock itself is
  unreachable from the main page now. The two "renders without overflow"
  tests' dropdown-presence check swapped for the `deploy-targets-overview`
  key.
- `test/screens/studio_screen_test.dart`: rewrote the two dropdown-filter
  tests to assert the hardware table always shows all four targets; every
  test that deep-links straight into Akida/PYNQ/SC-NeuroCore FPGA content
  (SSH keystrokes, pairing, compiled-artifacts "View NIR Artifact") now taps
  that target's Configure button first.

## Verification

- `flutter analyze` — clean, whole project.
- `flutter test` — `deploy_targets_no_nested_cards_test.dart`,
  `standard_deploy_layout_parity_test.dart`, `widget_test.dart` (27/27
  combined), `studio_screen_test.dart` (51/51, 2 pre-existing unrelated
  split-view-stepper `RenderFlex` failures unchanged), `simulator_panel_test.dart`
  (16/16), `run_step_test.dart` (7/7), `studio_responsive_audit_test.dart`
  (29/31 — 2 pre-existing unrelated failures: stepper-accordion width,
  Deploy Artifacts header; both confirmed present before this session).
  - One real bug found and fixed along the way: three of my new
    "Akida's Configure dialog" tests used `pumpAndSettle()` at 600px width,
    which never returns there because of a pre-existing rendering hiccup in
    `nmtk_ui_core/lib/widgets/snn_workflow_stepper.dart` that keeps
    scheduling frames — the *old* test avoided this entirely by using fixed
    `pump()` calls plus a `FlutterError.onError` whitelist. Fixed by
    switching those three tests to fixed-duration pumps too.
- **Not visually verified** — no browser/simulator surface for this macOS
  Flutter app in this session. Run `flutter run -d macos`, open Deploy: both
  tables should render with no dropdown above them and little gap under the
  stepper; a hardware row's "Configure" opens its full setup page in a
  dialog; simulator rows behave as before (shared settings cascade,
  per-row override, Run all).

## Follow-up (same day): filter by Setup selection + results summary

User feedback after the first pass: the tables should only list targets
Setup actually selected (not always all four/all three), and should show
the results summary the old per-target pages used to show, not just a bare
status pill.

- **Filtering**: `_DeployTargetsOverview` now reads
  `workspace.selectedPlatforms` and filters `hardwareTargetIds`/
  `kSimulatorDeployBackends` down to what's ticked, hiding a whole section
  (heading, shared-settings card, run-all button) if nothing in that
  category is selected. Falls back to showing everything only when
  `selectedPlatforms` contains no id this build's catalog recognizes at
  all (a fresh/edge-case workspace) — the step gate normally prevents
  reaching Deploy with nothing ticked, so this is a defensive fallback, not
  the normal path. `_RunAllSimulatorsButton`/`_SharedSimulatorSettingsCard`
  (`simulator_deploy_workspace.dart`) took a `backends` param instead of
  always iterating the full `kSimulatorDeployBackends` constant.
- **Results summary**: researched whether a shared "outcome + key metric +
  when" model exists across hardware and simulator targets — it doesn't.
  `StudioPlatformResult` (`studio_result_session.dart`) is a training-run
  model, not a deploy-result one. The only real compact summary anywhere
  is `_DeployRunStatusPane._buildDone` in `simulator_panel.dart` (status
  badge + duration + total spikes + a "Ran at" timestamp that's local
  widget state, not stored on `SimulatorRunResult`, so it isn't
  reproducible in a stateless table row without duplicating that state
  tracking — left out). The simulator table's Status cell now shows that
  same badge + duration + spike count for a completed run. Hardware
  targets have no shared result shape at all (Akida/PYNQ/Lava are each
  bespoke; SC-NeuroCore FPGA never produces one) — added a "Results"
  column using the same `deployTargetHasResultProvider` bool the Review
  step already gates on, rendered as "Ran" / "Not run yet" rather than
  inventing a per-target metric extraction.
- Reverted the "always show all targets" test coverage from the first
  pass: `studio_screen_test.dart`'s hardware-table test now asserts
  exactly the ticked ids show and the rest don't (instead of the old
  "always all four" claim), plus a new test covering the empty-selection
  fallback. Other test files (`standard_deploy_layout_parity_test.dart`,
  `deploy_targets_no_nested_cards_test.dart`, `studio_responsive_audit_test.dart`)
  needed no changes — none of them tick any Setup platform, so they hit
  the fallback and keep seeing every target, same as before.
- Verified: `flutter analyze` clean; `studio_screen_test.dart` 51/51 (2
  pre-existing unrelated failures unchanged); `standard_deploy_layout_parity_test.dart`
  + `deploy_targets_no_nested_cards_test.dart` + `widget_test.dart` 27/27;
  `studio_responsive_audit_test.dart` 29/31 (same 2 pre-existing failures);
  `simulator_panel_test.dart` + `run_step_test.dart` 23/23.

## Second follow-up (same day): Results column, Lava placement, icon color

Three more fixes from user feedback on the first-pass screenshot:

- **Results gets its own column.** The simulator table's Status cell had
  been carrying both the run-state badge AND the duration/spike-count
  recap together (from the first follow-up above). Split into two real
  `DataColumn`s — Status (badge only) and Results (duration + spike count,
  or `—` when idle/running/failed) — matching the hardware table's
  existing Status/Results split.
- **Lava / Loihi2 moved out of the Hardware Targets table.** Its catalog
  `kind` is `'hardware'`, but `StudioLavaDeployState.runConfig` defaults to
  `'sim'` — opening its Configure dialog shows simulator content unless the
  user has already flipped its own internal toggle to hardware. Filing it
  under "Hardware Targets" next to three targets with no such ambiguity
  was misleading. It's now rendered as its own single-row table right
  below the Software Simulators table (still using `_HardwareTargetsTable`
  unmodified — same row shape, same Configure-opens-a-dialog behavior —
  just relocated and gated on `selectedPlatforms.contains('lava')`
  independently of whether any true simulator backend is selected).
  Confirmed via a research agent that Setup already lists `lava` and
  `lava_sim` as two separate tickable rows (`setup_step.dart`, iterating
  the full `_deployTargets` catalog) — no Setup-side change was needed,
  contrary to what the ask implied.
  - **Bug caught before landing**: `_HardwareTargetsTable`'s
    `SingleChildScrollView` had a hardcoded `Key('hardware-targets-table')`.
    Rendering it twice (once for the fixed hardware targets, once for
    Lava alone) put two widgets with the *same* `LocalKey` as siblings in
    the same `Column` — Flutter's duplicate-key assertion. Fixed by adding
    a `tableKey` parameter (defaults to the original key) and passing
    `Key('lava-hardware-table')` for the Lava instance.
- **Icon colors.** Every plain `Icon`/`IconButton` in
  `deploy_targets_overview.dart` and the simulator-settings dialog
  (`simulator_deploy_workspace.dart`) had no explicit `color:` — target
  icons in both tables, the settings gear, and both dialogs' close
  buttons. Confirmed via grep that this app's convention is to always set
  an explicit Zeta color token on plain `Icon`s (dozens of examples across
  the codebase); nothing here does that, so they render in Flutter's
  Material default (dark) regardless of the app's theme. Fixed by adding
  `color: colors.mainDefault` (target icons, settings gear, close buttons)
  — `NmtkStatusBadge`'s own icons were already correctly tone-colored and
  didn't need touching.
- Test fix: `deploy_targets_no_nested_cards_test.dart`'s
  `findsNWidgets(2)` `DataTable` count bumped to 3 (hardware + Lava's own
  + simulator), plus an explicit `lava-hardware-table` key check.
- Verified: `flutter analyze` clean; `deploy_targets_no_nested_cards_test.dart`
  + `standard_deploy_layout_parity_test.dart` + `widget_test.dart` 27/27;
  `studio_screen_test.dart` 51/51 (2 pre-existing failures unchanged);
  `studio_responsive_audit_test.dart` 29/31 (same 2 pre-existing failures);
  `simulator_panel_test.dart` + `run_step_test.dart` 23/23.
