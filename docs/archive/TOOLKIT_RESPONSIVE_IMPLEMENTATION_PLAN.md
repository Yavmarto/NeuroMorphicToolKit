# Toolkit Responsive Implementation Plan

## Goal

Make the toolkit frontend surfaces fully responsive across desktop, tablet, and compact widths,
with implementation ordered so shared primitives land before downstream module cleanups that would
otherwise duplicate work.

Target widths for every module in this plan:

- `1440 px`
- `1024 px`
- `768 px`
- `600 px`
- `390 px`

## Semble Status

Attempted again on `2026-05-04`.

Current result:

- MCP `semble` calls still fail with `Transport closed`.
- Local `semble` is on `$PATH` at `/Users/yoshimartodihardjo/miniconda3/bin/semble`.
- The local CLI still fails before search completes because the Python environment cannot import
  NumPy C extensions.

Because of that, the ordering below is based on the actual issue dependencies and the frontend code
already inspected directly.

## Issue Set

Primary active responsiveness issues:

1. [nmtk_ui_core/issues/08-auto-aligning-pipeline-strip-primitive.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/issues/08-auto-aligning-pipeline-strip-primitive.md)
2. [neurocnl/issues/15-neurostudio-pipeline-pane-responsive-audit.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/issues/15-neurostudio-pipeline-pane-responsive-audit.md)
3. [Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md)
4. [Neurosense/issues-next/004-prod-responsive-frontend-surface-audit.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/issues-next/004-prod-responsive-frontend-surface-audit.md)

Already completed first-pass shell work:

- `neurocnl/frontend` Studio shell, compact pipeline header, one-pane-at-a-time pipeline view,
  and active-tab left-edge alignment are already implemented.

## Status: COMPLETE (2026-05-04)
- [x] Stage 1: Shared Primitive Hardening (nmtk_ui_core)
- [x] Stage 2: Target Surface Refactoring (Neurohub, Neurocnl, Neurosense)
- [x] Stage 3: Deep Workflow Verification & Audit

### Final Summary
- **Shared Primitives**: `NmtkSurfaceCard` and `NmtkPipelineStepper` are fully responsive and verified.
- **Neurohub**: Hardened `Dashboard`, `New Project`, and `Project Detail` screens. 
- **Neurocnl**: Hardened all pipeline panes (Parse, Validation, Generation, Simulation, Deployment).
- **Neurosense**: Hardened `SignalMonitor`, `DeviceConfig`, `FilterPipeline`, and `Sessions/Replay` screens.
- **Toolkit Coverage**: Zero `RenderFlex` overflows detected at 390px across all modules.


## Recommended Order

### Stage 1: Shared primitive extraction

1. `nmtk_ui_core/issues/08-auto-aligning-pipeline-strip-primitive.md`

Why first:

- `neurocnl` already has a working module-local implementation.
- `Neurohub` explicitly depends on this shared primitive in the new issue.
- If another module needs a horizontally scrollable, selected-step strip, shipping the shared
  widget first prevents another round of local one-off implementations.

Expected outcome:

- A reusable state-management-agnostic pipeline strip in `nmtk_ui_core`.
- Widget tests for active-step alignment and compact behavior.

### Stage 2: Finish the highest-risk existing workflow

2. `neurocnl/issues/15-neurostudio-pipeline-pane-responsive-audit.md`

Why second:

- `neurocnl` is already partially migrated and has real compact-width tests.
- The remaining work is pane-level hardening, not architectural discovery.
- It is the fastest route to proving the quality bar for the rest of the toolkit.

Expected outcome:

- All Studio pipeline panes are usable at compact widths.
- No pane-local overflow remains in parse, validation, generate, simulation, or deploy.

### Stage 3: Parallel module audits

3. `Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md`
4. `Neurosense/issues-next/004-prod-responsive-frontend-surface-audit.md`

Why together:

- They touch separate modules and can run in parallel.
- Both already show some breakpoint logic, which means the likely work is cleanup and test
  hardening rather than a full shell redesign.
- Neither should block the other once the shared primitive question is settled.

Recommended focus inside each:

For `Neurohub`:

- `dashboard_screen.dart`
- `bundle_inspection_screen.dart`
- `project_detail_screen.dart`
- `new_project_screen.dart`
- `activity_feed.dart`
- `project_card.dart`
- `suite_health_bar.dart`

For `Neurosense`:

- `signal_monitor_screen.dart`
- `device_config_screen.dart`
- `filter_pipeline_screen.dart`
- `replay_controls.dart`
- `recording_controls.dart`
- `spike_encoding_panel.dart`
- `signal_quality_bar.dart`
- `live_signal_viewer.dart`

## Concrete Execution Sequence

1. Extract and test the shared auto-aligning pipeline strip in `nmtk_ui_core`.
2. Decide whether `neurocnl` should immediately migrate to that primitive or keep the local
   version until the pane audit is done.
3. Complete the `neurocnl` pane-level audit and expand its compact-width widget coverage.
4. Run the `Neurohub` responsive audit and land widget tests for dashboard and bundle inspection.
5. Run the `Neurosense` responsive audit and land widget tests for monitoring, device config, and
   replay/encoding-heavy screens.
6. Do a final toolkit-level manual resize pass across the modules touched in this rollout.

## Parallelization Guidance

Safe parallel plan:

1. One engineer on `nmtk_ui_core/issues/08`.
2. One engineer on `neurocnl/issues/15`.
3. After the `nmtk_ui_core` API is stable, one engineer on `Neurohub/issues/025`.
4. In parallel with NeuroHub, one engineer on `Neurosense/issues-next/004`.

Unsafe parallel plan:

- Starting separate shared-strip implementations in multiple modules before `nmtk_ui_core/issues/08`
  is resolved.
- Refactoring NeuroHub and NeuroSense top bars independently if they end up needing the same
  shared compact-shell treatment.

## Acceptance Bar Per Stage

For every stage:

- No `RenderFlex overflow` in the target flows at the target widths.
- No page-level horizontal scrolling used as a substitute for real responsive layout.
- Primary actions remain visible and operable.
- The owning module frontend test suite passes.

Module verification commands:

- `cd nmtk_ui_core && flutter test`
- `cd neurocnl/frontend && flutter test`
- `cd Neurohub/frontend && flutter test`
- `cd Neurosense/frontend && flutter test`

## Definition Of Done

The responsiveness rollout is complete when:

- Shared compact interaction primitives that need to be shared are in `nmtk_ui_core`.
- `neurocnl`, `Neurohub`, and `Neurosense` all pass their responsive widget checks.
- Manual resize verification confirms that the main workflows in each module remain usable at
  `1024 px`, `768 px`, `600 px`, and `390 px`.
- No module still relies on accidental desktop squeezing for critical surfaces.
