import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_phase_canvas.dart';

// Regression coverage for the vertical-layout connector bug: the pipeline
// canvas's edge bezier used to bulge its control points along dx regardless
// of node orientation, so a vertical (top-to-bottom) wire got a curve shaped
// for a horizontal (left-to-right) one — and the edge-selection midpoint
// (where the delete "x" and any future connector label anchor) landed off
// the visible wire. See pipelineEdgeControlPoints/pipelineEdgePointAt/
// pipelineEdgeDistance in pipeline_phase_canvas.dart.
void main() {
  group('pipelineEdgePointAt', () {
    test('midpoint of a straight vertical wire lies on the wire', () {
      const start = Offset(100, 0);
      const end = Offset(100, 200);

      final mid = pipelineEdgePointAt(start, end, 0.5, isVertical: true);

      // A vertical control-point bulge keeps a purely-vertical wire's curve
      // on the x=100 line; the horizontal-bulge bug moved the "midpoint" off
      // to the side because the cubic's control points sat at (100+mid, y)
      // instead of (100, y+mid).
      expect(mid.dx, closeTo(100, 0.001));
      expect(mid.dy, closeTo(100, 0.001));
    });

    test('midpoint of a straight horizontal wire lies on the wire', () {
      const start = Offset(0, 50);
      const end = Offset(200, 50);

      final mid = pipelineEdgePointAt(start, end, 0.5, isVertical: false);

      expect(mid.dx, closeTo(100, 0.001));
      expect(mid.dy, closeTo(50, 0.001));
    });
  });

  group('pipelineEdgeDistance', () {
    test(
      'the vertical wire\'s own midpoint is on (distance ~0 from) itself',
      () {
        const start = Offset(100, 0);
        const end = Offset(100, 200);
        final mid = pipelineEdgePointAt(start, end, 0.5, isVertical: true);

        final distance = pipelineEdgeDistance(
          mid,
          start,
          end,
          isVertical: true,
        );

        expect(distance, lessThan(1.0));
      },
    );
  });

  group('pipelineEdgeControlPoints', () {
    test('bulges along dy when vertical, dx when horizontal', () {
      // A diagonal edge (both dx and dy nonzero) — realistic for a vertical
      // pipeline layout where sibling nodes aren't perfectly x-aligned.
      const start = Offset(80, 0);
      const end = Offset(120, 200);

      final verticalCps = pipelineEdgeControlPoints(
        start,
        end,
        isVertical: true,
      );
      final horizontalCps = pipelineEdgeControlPoints(
        start,
        end,
        isVertical: false,
      );

      // Vertical mode: control points keep each endpoint's own dx and only
      // move along dy (the bulge axis matches the direction the wire
      // actually travels in a top-to-bottom layout).
      expect(verticalCps.cp1.dx, start.dx);
      expect(verticalCps.cp2.dx, end.dx);
      expect(verticalCps.cp1.dy, greaterThan(start.dy));
      expect(verticalCps.cp2.dy, lessThan(end.dy));

      // Horizontal mode: control points keep each endpoint's own dy and only
      // move along dx — the opposite axis from the vertical case above.
      expect(horizontalCps.cp1.dy, start.dy);
      expect(horizontalCps.cp2.dy, end.dy);
      expect(horizontalCps.cp1.dx, greaterThan(start.dx));
      expect(horizontalCps.cp2.dx, lessThan(end.dx));
    });
  });
}
