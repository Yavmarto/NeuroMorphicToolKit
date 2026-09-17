import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';

void main() {
  group('toGridCoord / gridCoordToOffset', () {
    test('round-trips a cell origin exactly', () {
      const coord = GridCoord(3, -2);
      final origin = gridCoordToOffset(coord);
      expect(toGridCoord(origin), coord);
    });

    test('rounds to the nearest cell, not just floors', () {
      const nearCol1 = Offset(kGridCellWidth * 0.9, 0);
      expect(toGridCoord(nearCol1), const GridCoord(1, 0));
    });

    test('centers a node inside the target grid cell', () {
      expect(
        gridCoordToCenteredOffset(
          const GridCoord(0, 0),
          nodeWidth: 200,
          nodeHeight: 160,
        ),
        const Offset(20, 16),
      );
    });
  });

  group('findNearestFreeCell', () {
    test('returns the target cell when it is free', () {
      final cell = findNearestFreeCell(
        gridCoordToCenterOffset(const GridCoord(0, 0)),
        <GridCoord>{},
      );
      expect(cell, const GridCoord(0, 0));
    });

    test(
      'spirals to the nearest free neighbor when the target is occupied',
      () {
        final occupied = <GridCoord>{const GridCoord(0, 0)};
        final cell = findNearestFreeCell(Offset.zero, occupied);
        expect(cell, isNot(const GridCoord(0, 0)));
        expect(occupied.contains(cell), isFalse);
        // Nearest free neighbor of (0,0) is exactly one ring out.
        expect(math.max(cell.col.abs(), cell.row.abs()), 1);
      },
    );

    test('expands search radius when an entire ring is occupied', () {
      final occupied = <GridCoord>{
        for (int col = -1; col <= 1; col++)
          for (int row = -1; row <= 1; row++) GridCoord(col, row),
      };
      final cell = findNearestFreeCell(Offset.zero, occupied);
      expect(occupied.contains(cell), isFalse);
      expect(math.max(cell.col.abs(), cell.row.abs()), 2);
    });

    test('ignoring lets a node keep its own occupied cell', () {
      const own = GridCoord(0, 0);
      final occupied = <GridCoord>{own};
      final cell = findNearestFreeCell(
        gridCoordToCenterOffset(own),
        occupied,
        ignoring: own,
      );
      expect(cell, own);
    });
  });

  group('findNextCellRightOrBelow', () {
    const from = GridCoord(0, 0);

    test('prefers the right cell when preferRight is true', () {
      final cell = findNextCellRightOrBelow(
        from,
        <GridCoord>{},
        preferRight: true,
      );
      expect(cell, const GridCoord(1, 0));
    });

    test('prefers the below cell when preferRight is false', () {
      final cell = findNextCellRightOrBelow(
        from,
        <GridCoord>{},
        preferRight: false,
      );
      expect(cell, const GridCoord(0, 1));
    });

    test('falls back to below when right is occupied', () {
      final occupied = <GridCoord>{const GridCoord(1, 0)};
      final cell = findNextCellRightOrBelow(from, occupied, preferRight: true);
      expect(cell, const GridCoord(0, 1));
    });

    test('falls back to right when below is occupied and preferRight is '
        'false', () {
      final occupied = <GridCoord>{const GridCoord(0, 1)};
      final cell = findNextCellRightOrBelow(from, occupied, preferRight: false);
      expect(cell, const GridCoord(1, 0));
    });

    test('expands into the right/below quadrant when both neighbors are '
        'occupied, never landing left of or above from', () {
      final occupied = <GridCoord>{
        const GridCoord(1, 0),
        const GridCoord(0, 1),
      };
      final cell = findNextCellRightOrBelow(from, occupied, preferRight: true);
      expect(cell.col, greaterThanOrEqualTo(from.col));
      expect(cell.row, greaterThanOrEqualTo(from.row));
      expect(occupied.contains(cell), isFalse);
    });
  });

  group('centeredPanFor', () {
    test('centers a scene point in the viewport at 1x zoom', () {
      final pan = centeredPanFor(
        const Offset(100, 50),
        1,
        const Size(800, 600),
      );
      expect(pan, const Offset(300, 250));
    });

    test('scales the scene point by zoom before centering', () {
      final pan = centeredPanFor(
        const Offset(100, 50),
        2,
        const Size(800, 600),
      );
      expect(pan, const Offset(200, 200));
    });
  });

  group('anchoredPanFor', () {
    test('places a restored node below the floating Studio header', () {
      final pan = anchoredPanFor(
        const Offset(300, 200),
        1,
        const Size(1200, 900),
      );

      expect(pan.dx, closeTo(-84, 0.001));
      expect(pan.dy, closeTo(52, 0.001));
      expect((const Offset(300, 200) + pan).dx, closeTo(216, 0.001));
      expect((const Offset(300, 200) + pan).dy, closeTo(252, 0.001));
    });
  });

  group('CanvasWorldGeometry', () {
    const geometry = CanvasWorldGeometry(Size(10000, 10000));

    test('keeps signed scene coordinates inside the centered child', () {
      const scene = Offset(-320, -240);
      final child = geometry.sceneToChild(scene);

      expect(child, const Offset(4680, 4760));
      expect(geometry.childToScene(child), scene);
    });
  });
}
