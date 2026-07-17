# CNL editor hidden by default on Model + Run canvases

## Problem
Studio's Model step (`defineModel`) and Run step (`_RunStep`) both embed the
same `CanvasScreen` widget locked to `CanvasTab.architecture`. The CNL Editor
overlay panel defaulted to visible (`_showCnl = true`) on every fresh
`CanvasScreen` instance, cluttering both screens even though a manual toggle
button already existed to show/hide it.

## Fix
- `lib/screens/canvas/canvas_screen.dart:62`: `bool _showCnl = true` →
  `false`. Single shared `State` field (not a Riverpod provider, not
  persisted anywhere), so this one line controls the default for every
  `CanvasScreen` instance — both the Model step
  (`studio_screen.dart:281-283`) and the Run step's background canvas
  (`studio/steps/run_step.dart:316-320`). Now consistent with
  `_showProperties` and `_showNir`, which already defaulted to `false`.
- `test/widget_test.dart:176`: updated the `/canvas` base-route test, which
  asserted `find.text('CNL Editor')` (the panel title) was present by
  default — now asserts `find.byTooltip('CNL Editor')` (the toggle button)
  instead, matching the new hidden-by-default behavior.

No provider, persistence layer, or other call sites needed changes —
confirmed via grep that no other test or code path assumes `_showCnl`
starts `true` (`preservation_property_test.dart` and
`widgets/cnl_editor_test.dart` instantiate `CnlEditor` directly in their own
harness, bypassing `CanvasScreen` entirely; `studio_screen_test.dart:668`
only checks the toggle button exists, unaffected by panel visibility).

## Verification
- No `dart`/`flutter` binary available in this environment, so
  `dart format`/`dart analyze`/`flutter test` were not run here — flagged
  for the user to run locally before merge:
  - `dart format lib/screens/canvas/canvas_screen.dart test/widget_test.dart`
  - `flutter test test/widget_test.dart test/screens/studio_screen_test.dart`
- Manual verification needed in a live session: open Studio → Model step,
  confirm CNL Editor panel starts closed and the toggle still opens it;
  repeat for the Run step's background canvas.
