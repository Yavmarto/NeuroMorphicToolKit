# Compact vertical (mobile) node layout — corrected target

## Correction
The first pass of this fix (below the line) only touched `pipeline_phase_canvas.dart`, which renders Train/Eval DAG-builder nodes. But the screen the user actually looks at by default (the "Model" step, and the background canvas on Run/Results) uses a **different, separate widget** — `NetworkCanvas`'s `_CanvasNodeWidget` in `network_canvas.dart` — which was never touched, hence "nothing changed." This second pass fixes the correct file.

## `neurocnl/frontend/lib/widgets/canvas/network_canvas.dart`
- Split `_CanvasNodeWidget`'s card content into `_buildMobileCardContent` and `_buildDesktopCardContent` (previously one inline, order-conflated `Column`).
- **Mobile**: dropped the fixed top header bar (which was previously *taller* on mobile — 64px vs desktop's 44px — the opposite of compact, and which visually overlapped the top-edge input port dots). Title is now centered in the middle via `Expanded(Center(...))`; a compact input-label row hugs the top edge (close to the input dots `_buildPorts` already places there) and an output-label row hugs the bottom edge. The collapse/expand button moved to a small top-right corner overlay.
- Desktop layout/sizing is byte-for-byte unchanged.
- Added `kNodeLabelClearanceVertical` (14px) replacing the old 64px header-height-as-clearance approach.
- **Bonus fix**: `findNearestInputPort` (used by drag-to-connect hover/drop detection) always assumed the desktop left-edge port layout even when called in mobile mode — added an `isMobile` parameter mirroring `_buildPorts`' own branch, wired from both call sites (`_NetworkCanvasState`'s `_isMobile` field). Without this, dragging a connection onto a node on mobile could miss the port it visually landed on.

## Deliberately not changed (stated plainly, not silently dropped)
- `node.width`/`node.height` — these are **persisted, user-resizable per-node model fields** (drag-resize handle), not a shared constant recomputed per orientation. Shrinking them at render time would either look inconsistent with the stored value or fight the resize-drag math and effectively disable resizing on mobile. The safe, real compactness win here is reclaiming the header bar's wasted height and tightening padding — it directly cuts empty space without touching resize behavior.
- `pipeline_phase_canvas.dart` — already fixed in the prior pass, unrelated to this one.

## Verification
- `flutter analyze`: no new issues (same 51 pre-existing baseline).
- New regression test in `test/widgets/canvas/network_canvas_port_geometry_test.dart`: `findNearestInputPort(isMobile: true)` matches the top-edge, width-spread mobile port layout instead of the desktop left-edge one.
- `flutter test test/widgets/canvas/`: 118/118 passing.
- Full `flutter test`: 1679/1679 relevant passing (same 4 pre-existing unrelated failures).
