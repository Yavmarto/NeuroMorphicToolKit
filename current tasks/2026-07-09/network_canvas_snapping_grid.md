# Network canvas: snapping grid + no-overlap placement

## What
Replaced free-form pixel node placement on the NIR editor canvas
(`neurocnl/frontend/lib/widgets/canvas/network_canvas.dart`) with a snapping
grid: every spawned or dragged node lands on a grid cell, and no two nodes
may ever occupy the same cell.

## How
- New `neurocnl/frontend/lib/models/canvas/grid.dart`: `GridCoord`,
  `toGridCoord`/`gridCoordToOffset`, `findNearestFreeCell` (spiral search).
  Cell size = node size (200x160) scaled by 1.2 → 240x192, preserving the
  node's aspect ratio with a gutter for edge-routing lines.
- `canvas_provider.dart`: `addNode` now snaps the spawned node's position to
  the nearest free cell (collisions auto-resolve outward). New
  `snapNodeToGrid(id)` commits a dragged node's final position the same way,
  called once on drag release — `updateNodePosition` is unchanged and still
  drives smooth, unsnapped visual feedback during the drag itself.
- `network_canvas.dart`: `GridPainter`'s decorative background grid now
  matches the real snap cell size (was a hardcoded 50px square, unrelated to
  actual placement). Added `onPanEnd` on node drag to call `snapNodeToGrid`.
- Deliberately left `pasteClipboard` untouched — it has its own tested
  offset-from-original behavior (`canvas_clipboard_test.dart`), and the
  approved plan scoped "spawn" to the palette-drop / handwriting-popup path
  (`_createNodeAt` → `addNode`), not paste.

## Tests
- `test/models/canvas/grid_test.dart` — pure grid math.
- `test/providers/canvas/canvas_provider_grid_snap_test.dart` — addNode
  collision resolution, drag-release snap, no-op when dropped in place,
  never-overlap invariant.
- Full `flutter test` run: only 4 pre-existing failures remain
  (`simulator_preflight_provider_test.dart`, `studio_screen_test.dart`),
  confirmed present on unmodified `dev` HEAD before this change (unrelated:
  preflight provider flakiness and a deactivated-widget lookup in
  `StudioScreen` dispose).

## Restart / verify
Run `cd neurocnl/frontend && flutter test test/models/canvas/grid_test.dart
test/providers/canvas/canvas_provider_grid_snap_test.dart`. To see it live,
run the neurocnl frontend app, open the canvas, and drag two palette nodes
onto the same spot — the second should land in the next free cell.
