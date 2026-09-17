import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// A render-only origin for a canvas child. Persisted canvas positions stay in
/// signed scene coordinates; the origin merely puts (0, 0) in the middle of
/// the finite Flutter child used to implement the otherwise unbounded world.
class CanvasWorldGeometry {
  const CanvasWorldGeometry(this.size);

  final Size size;

  Offset get origin => Offset(size.width / 2, size.height / 2);

  Offset sceneToChild(Offset scene) => scene + origin;

  Offset childToScene(Offset child) => child - origin;
}

/// Grid cell dimensions the canvas snaps node positions to.
///
/// Scaled up from the node footprint (`kNodeWidth`/`kNodeHeight` in
/// `network_canvas.dart`, 200.0x160.0) by [kGridScaleFactor] so a cell keeps
/// the node's exact aspect ratio while leaving a gutter around each node for
/// edge-routing lines.
const double kGridScaleFactor = 1.2;
const double kGridCellWidth = 200.0 * kGridScaleFactor; // 240.0
const double kGridCellHeight = 160.0 * kGridScaleFactor; // 192.0

/// How many rings outward [findNearestFreeCell] will search before giving up.
/// The canvas is conceptually infinite, so this is a generous safety cap
/// rather than a real limit.
const int kGridMaxSearchRadius = 200;

/// An integer cell address on the snapping grid.
class GridCoord {
  const GridCoord(this.col, this.row);

  final int col;
  final int row;

  @override
  bool operator ==(Object other) =>
      other is GridCoord && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'GridCoord($col, $row)';
}

/// Rounds a scene-space position to its nearest grid cell.
GridCoord toGridCoord(Offset scenePos) {
  return GridCoord(
    (scenePos.dx / kGridCellWidth).round(),
    (scenePos.dy / kGridCellHeight).round(),
  );
}

/// Rounds a scene-space node center to its containing grid cell.
GridCoord centerToGridCoord(Offset sceneCenter) {
  return GridCoord(
    ((sceneCenter.dx - kGridCellWidth / 2) / kGridCellWidth).round(),
    ((sceneCenter.dy - kGridCellHeight / 2) / kGridCellHeight).round(),
  );
}

/// The scene-space origin (top-left) of a grid cell — this is the value
/// that should be stored as a snapped `CanvasNode.position`.
Offset gridCoordToOffset(GridCoord coord) {
  return Offset(coord.col * kGridCellWidth, coord.row * kGridCellHeight);
}

/// The scene-space center of a grid cell.
Offset gridCoordToCenterOffset(GridCoord coord) {
  return Offset(
    coord.col * kGridCellWidth + kGridCellWidth / 2,
    coord.row * kGridCellHeight + kGridCellHeight / 2,
  );
}

/// The top-left scene-space position that centers a node in a grid cell.
Offset gridCoordToCenteredOffset(
  GridCoord coord, {
  required double nodeWidth,
  required double nodeHeight,
}) {
  final Offset center = gridCoordToCenterOffset(coord);
  return Offset(center.dx - nodeWidth / 2, center.dy - nodeHeight / 2);
}

/// Finds the grid cell closest to [target] that isn't in [occupied].
///
/// [ignoring], if given, is treated as free even if it's in [occupied] — use
/// it when re-snapping a node that already owns a cell, so dropping it back
/// in place is a no-op instead of triggering the collision search.
///
/// Searches outward ring by ring (Chebyshev distance) from the cell nearest
/// [target], picking the closest free cell by actual scene distance within
/// each ring before moving further out.
GridCoord findNearestFreeCell(
  Offset target,
  Set<GridCoord> occupied, {
  GridCoord? ignoring,
}) {
  bool isFree(GridCoord cell) => cell == ignoring || !occupied.contains(cell);

  final GridCoord center = centerToGridCoord(target);
  if (isFree(center)) {
    return center;
  }

  for (int radius = 1; radius <= kGridMaxSearchRadius; radius++) {
    GridCoord? best;
    double bestDistanceSq = double.infinity;
    for (int dCol = -radius; dCol <= radius; dCol++) {
      for (int dRow = -radius; dRow <= radius; dRow++) {
        if (math.max(dCol.abs(), dRow.abs()) != radius) {
          continue;
        }
        final GridCoord candidate = GridCoord(
          center.col + dCol,
          center.row + dRow,
        );
        if (!isFree(candidate)) {
          continue;
        }
        final Offset candidateCenter = gridCoordToCenterOffset(candidate);
        final double dx = candidateCenter.dx - target.dx;
        final double dy = candidateCenter.dy - target.dy;
        final double distanceSq = dx * dx + dy * dy;
        if (distanceSq < bestDistanceSq) {
          bestDistanceSq = distanceSq;
          best = candidate;
        }
      }
    }
    if (best != null) {
      return best;
    }
  }

  throw StateError(
    'No free grid cell found within $kGridMaxSearchRadius rings of $center',
  );
}

/// Finds a free cell to the right of or below [from], for placing a newly
/// added node relative to whatever node is "current".
///
/// Tries the immediate right cell and immediate below cell first, in the
/// order given by [preferRight]. If both are occupied, expands outward
/// ring by ring like [findNearestFreeCell], but restricted to the
/// right/below quadrant (`dCol >= 0 && dRow >= 0`) so the result never lands
/// to the left of or above [from].
GridCoord findNextCellRightOrBelow(
  GridCoord from,
  Set<GridCoord> occupied, {
  required bool preferRight,
}) {
  final GridCoord right = GridCoord(from.col + 1, from.row);
  final GridCoord below = GridCoord(from.col, from.row + 1);
  final List<GridCoord> immediate = preferRight
      ? [right, below]
      : [below, right];
  for (final GridCoord candidate in immediate) {
    if (!occupied.contains(candidate)) {
      return candidate;
    }
  }

  final Offset fromCenter = gridCoordToCenterOffset(from);
  for (int radius = 2; radius <= kGridMaxSearchRadius; radius++) {
    GridCoord? best;
    double bestDistanceSq = double.infinity;
    for (int dCol = 0; dCol <= radius; dCol++) {
      for (int dRow = 0; dRow <= radius; dRow++) {
        if (math.max(dCol, dRow) != radius) {
          continue;
        }
        final GridCoord candidate = GridCoord(from.col + dCol, from.row + dRow);
        if (occupied.contains(candidate)) {
          continue;
        }
        final Offset candidateCenter = gridCoordToCenterOffset(candidate);
        final double dx = candidateCenter.dx - fromCenter.dx;
        final double dy = candidateCenter.dy - fromCenter.dy;
        final double distanceSq = dx * dx + dy * dy;
        if (distanceSq < bestDistanceSq) {
          bestDistanceSq = distanceSq;
          best = candidate;
        }
      }
    }
    if (best != null) {
      return best;
    }
  }

  throw StateError(
    'No free right/below grid cell found within $kGridMaxSearchRadius rings '
    'of $from',
  );
}

/// The pan translation (in scene pixels) that centers [sceneCenter] within a
/// viewport of [viewportSize] at [zoom] -- the scene-space analog of
/// `translate` in the `Matrix4.identity()..translate(...)..scale(...)`
/// pattern already used by the canvas widgets to sync their
/// `TransformationController` with `CanvasViewport`.
Offset centeredPanFor(Offset sceneCenter, double zoom, Size viewportSize) {
  return Offset(
    viewportSize.width / 2 - sceneCenter.dx * zoom,
    viewportSize.height / 2 - sceneCenter.dy * zoom,
  );
}

/// The stable workspace-load anchor used by all three Studio canvases.
///
/// It leaves room for the fixed Studio chrome while putting the first node in
/// the left-hand working area rather than under the top edge of the canvas.
const Offset kWorkspaceRestoreFocusViewportFraction = Offset(0.18, 0.28);

/// The pan that places [scenePoint] at [viewportFraction] of [viewportSize].
///
/// Unlike [centeredPanFor], this is intentionally asymmetric: a restored
/// workflow should start at the left of the working area so its downstream
/// flow remains visible, with sufficient top clearance for fixed chrome.
Offset anchoredPanFor(
  Offset scenePoint,
  double zoom,
  Size viewportSize, {
  Offset viewportFraction = kWorkspaceRestoreFocusViewportFraction,
}) {
  return Offset(
    viewportSize.width * viewportFraction.dx - scenePoint.dx * zoom,
    viewportSize.height * viewportFraction.dy - scenePoint.dy * zoom,
  );
}
