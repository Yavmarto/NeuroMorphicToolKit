# Mobile-friendly Run/Results steps + vertical connector label fix

Plan file: `~/.claude/plans/i-need-you-to-shimmying-fog.md`

## What was done

1. **`neurocnl/frontend/lib/widgets/canvas/pipeline_phase_canvas.dart`**
   - Fixed vertical-node port label rows (were always horizontal left/right columns; now branch to top/bottom rows aligned under/over each port dot when `isVertical`).
   - Threaded `isVertical` through `pipelineEdgeControlPoints`/`pipelineEdgePointAt`/`pipelineEdgeDistance` (previously always bulged the bezier along dx, wrong for top-to-bottom wires) and their call sites (`selectedEdgeCentre`, hit-testing, `_drawBezier`).
   - Fixed the arrowhead to point downward (was always leftward) in vertical mode.

2. **`neurocnl/frontend/lib/screens/studio/steps/run_step.dart`**
   - Replaced hardcoded `Positioned(left: 264)` offsets and the fixed-width `_MetricsSidebar` with a `LayoutBuilder` + `NmtkShellTokens.compactBreakpoint` (840) responsive branch.
   - Below breakpoint: metrics move into an always-visible horizontal strip (`_MetricsSidebar(isHorizontal: true)`), Spikes chart moves to a bottom sheet.
   - Collapsed banners/metrics-strip/action-bar into one bottom `Column`, added bottom `SafeArea` inset, fixed sub-48dp touch targets, migrated hardcoded radii to `NmtkShellTokens.radiusSm`.
   - `_RunActionBar` drops button text to icon+tooltip on compact widths.

3. **`neurocnl/frontend/lib/screens/studio/steps/results_step.dart`**
   - Same `LayoutBuilder` pattern; below breakpoint the `_FinalMetricsSidebar` moves into a `DraggableScrollableSheet` (opened from a "Results · <metric>" chip in the tab row) instead of a fixed 240px inline column.
   - Context bar (layer dropdown + epoch scrubber) stacks into two rows on compact instead of overflowing one row.
   - Sidebar's Metrics/Dynamics tab row: `SingleChildScrollView` → `Wrap` (two tabs never need scrolling).
   - `showResultsDeployDialog` goes full-screen (no inset, `SafeArea`) below the breakpoint instead of a fixed 980×740 dialog.
   - Fixed sub-48dp touch targets (sidebar chevron, download button).

4. **Tests**
   - New `test/widgets/canvas/pipeline_edge_geometry_test.dart`: pure unit tests proving the vertical bezier midpoint lands on the wire (failed before the fix) and that control points bulge on the correct axis per orientation.
   - Updated `test/widgets/canvas/pipeline_port_add_test.dart` call site for the new `isVertical` parameter.
   - `test/screens/studio_responsive_audit_test.dart`: fixed the existing "Deploy surface" test to open the new Results sheet first (sidebar no longer inline at 390px); added two new tests for the Run step's horizontal-strip-vs-sidebar behavior at 390px/1200px.

## Verification
- `flutter analyze`: no new issues (pre-existing warnings elsewhere untouched).
- `flutter test`: 1670 passing (was 1664 before; +6 new), same 4 pre-existing unrelated failures (FPGA/Akida deploy-target-form tests, `setup_step_local_import_test` file-picker `setUpAll` — none touch these files).

## Deliberately not fixed (see plan for full list + reasons)
- `studio_screen.dart`'s `isMobile` breakpoint (600 vs. 840 elsewhere) — separate debt.
- `_SetupStep`'s `MediaQuery.sizeOf` vs `constraints.maxWidth` bug — out of scope.
- `pipelineDagNodeHeightFor` not shrinking in vertical mode — touches persisted node coordinates.
- `network_graph_view.dart`'s always-upward edge label — no vertical mode exists there today.
