# CEL-156 — Brainviz in Results tab

## Summary
Moved brainviz from editor `StudioViewMode.network` (wrong place) to `StudioResultView.brainviz` tab in Results.

## Key files
- `studio_result_session.dart` — `brainviz` enum value
- `results_brainviz_panel.dart` — new tab widget
- `force_directed_layout.dart` — correlation attraction + `CorrelationForceNetworkLayout`
- `network_2_5d_view.dart` — `forceDirected` mode
- `studio_result_visualizer.dart` — IndexedStack child #4

## Tests
- `force_directed_layout_test.dart` — correlation attraction
- All existing `network_2_5d_view_test.dart` pass

## Manual QA
Run app → training results → Brainviz tab → play raster, watch correlated neurons cluster.
