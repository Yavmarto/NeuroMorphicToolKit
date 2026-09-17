import 'dart:ui';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/node_geometry.dart';

/// Single source of truth for **what a wire looks like** on every canvas:
/// the curve it follows, its stroke, its arrowhead, its dash pattern, the
/// point its `✕` sits on, and the sampling used to hit-test it.
///
/// The Architecture canvas and the pipeline-phase canvases previously each
/// carried their own copy of this math (`ConnectionPainter` +
/// `_isPointNearBezier` on one side, `_PipelineEdgePainter` +
/// `pipelineEdge*` helpers on the other) — same cubic, separately written, so
/// stroke widths and selection weights had already drifted apart.
///
/// Wire *color* is deliberately not decided here: the pipeline canvases color
/// a wire by its port's data kind (spikes / loss / gradients / …) while the
/// Architecture canvas has no such notion — its `PortType` describes tensor
/// shape, not data kind — so it colors a wire by the source node's category.
/// Both palettes live in `theme/nir_node_styles.dart`.

/// Control points of the cubic drawn between [start] and [end].
///
/// Both control points offset along a single axis, which is what makes
/// [canvasEdgeMidpoint] exact.
({Offset cp1, Offset cp2}) canvasEdgeControlPoints(
  Offset start,
  Offset end, {
  required bool isVertical,
}) {
  if (isVertical) {
    final double mid = (end.dy - start.dy).abs() / 2;
    return (
      cp1: Offset(start.dx, start.dy + mid),
      cp2: Offset(end.dx, end.dy - mid),
    );
  }
  final double mid = (end.dx - start.dx).abs() / 2;
  return (
    cp1: Offset(start.dx + mid, start.dy),
    cp2: Offset(end.dx - mid, end.dy),
  );
}

/// Point on the wire's curve at parameter [t] (0 = start, 1 = end).
Offset canvasEdgePointAt(
  Offset start,
  Offset end,
  double t, {
  required bool isVertical,
}) {
  final ({Offset cp1, Offset cp2}) cps = canvasEdgeControlPoints(
    start,
    end,
    isVertical: isVertical,
  );
  final double u = 1 - t;
  return Offset(
    u * u * u * start.dx +
        3 * u * u * t * cps.cp1.dx +
        3 * u * t * t * cps.cp2.dx +
        t * t * t * end.dx,
    u * u * u * start.dy +
        3 * u * u * t * cps.cp1.dy +
        3 * u * t * t * cps.cp2.dy +
        t * t * t * end.dy,
  );
}

/// Midpoint of the wire — where the edge's delete `✕` and any badge sit.
///
/// Because both control points offset along one axis only, the cubic's t=0.5
/// point reduces to the arithmetic mean of the endpoints.
Offset canvasEdgeMidpoint(Offset start, Offset end) =>
    Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

/// Distance from [point] to the wire's curve, sampled along it. Sample count
/// scales with chord length so long wires are not under-sampled.
double canvasEdgeDistance(
  Offset point,
  Offset start,
  Offset end, {
  required bool isVertical,
}) {
  final double chord = (end - start).distance;
  // Rounded up to an even count so t=0.5 — the point the edge's `✕` and its
  // badge sit on — is always one of the samples.
  final int samples =
      ((chord / kCanvasEdgeHitTolerance).ceil().clamp(20, 400) + 1) & ~1;
  double best = double.infinity;
  for (int i = 0; i <= samples; i += 1) {
    final double d =
        (canvasEdgePointAt(start, end, i / samples, isVertical: isVertical) -
                point)
            .distance;
    if (d < best) best = d;
  }
  return best;
}

/// True when [point] is close enough to the wire to select it.
bool canvasEdgeHit(
  Offset point,
  Offset start,
  Offset end, {
  required bool isVertical,
  double tolerance = kCanvasEdgeHitTolerance,
}) => canvasEdgeDistance(point, start, end, isVertical: isVertical) < tolerance;

/// Stroke width of a wire. One rule for every canvas, so a selected wire
/// reads the same everywhere.
double canvasEdgeStrokeWidth({required bool isSelected, double weight = 1.0}) =>
    (isSelected ? 3.5 : 2.0) * weight;

/// Draws one wire from [start] to [end], with the arrowhead at [end].
///
/// [dashed] draws the "plastic"/learning-rule pattern (8px on, 5px off)
/// instead of a solid stroke.
void drawCanvasEdge(
  Canvas canvas,
  Offset start,
  Offset end,
  Color color, {
  required bool isVertical,
  double strokeWidth = 2.0,
  bool dashed = false,
  bool arrowhead = true,
}) {
  final Paint paint = Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..style = PaintingStyle.stroke;

  final ({Offset cp1, Offset cp2}) cps = canvasEdgeControlPoints(
    start,
    end,
    isVertical: isVertical,
  );
  final Path path = Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(cps.cp1.dx, cps.cp1.dy, cps.cp2.dx, cps.cp2.dy, end.dx, end.dy);

  if (dashed) {
    const double dashLen = 8.0;
    const double gapLen = 5.0;
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double segEnd = (distance + (draw ? dashLen : gapLen)).clamp(
          0.0,
          metric.length,
        );
        if (draw) {
          canvas.drawPath(metric.extractPath(distance, segEnd), paint);
        }
        distance = segEnd;
        draw = !draw;
      }
    }
  } else {
    canvas.drawPath(path, paint);
  }

  if (arrowhead) {
    drawCanvasArrowhead(canvas, end, color, isVertical: isVertical);
  }
}

/// Draws a filled triangular arrowhead at [end], pointing in the direction of
/// travel. Wings trail behind that direction: leftward for a horizontal
/// (left-to-right) wire, upward for a vertical (top-to-bottom) one.
void drawCanvasArrowhead(
  Canvas canvas,
  Offset end,
  Color color, {
  required bool isVertical,
  double size = 7.0,
}) {
  final Paint arrowPaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  canvas.drawPath(
    isVertical
        ? (Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - size * 0.6, end.dy - size)
            ..lineTo(end.dx + size * 0.6, end.dy - size)
            ..close())
        : (Path()
            ..moveTo(end.dx, end.dy)
            ..lineTo(end.dx - size, end.dy - size * 0.6)
            ..lineTo(end.dx - size, end.dy + size * 0.6)
            ..close()),
    arrowPaint,
  );
}
