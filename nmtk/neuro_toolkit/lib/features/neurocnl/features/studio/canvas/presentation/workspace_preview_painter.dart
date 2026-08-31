import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_minimap.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/canvas/presentation/preview_graph.dart';

/// Paints a compact canvas overview without mutating canvas state.
class WorkspacePreviewPainter extends CustomPainter {
  const WorkspacePreviewPainter({
    required this.graph,
    required this.edgeColor,
    required this.nodeRadius,
  });

  final PreviewGraph graph;
  final Color edgeColor;
  final double nodeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (graph.nodes.isEmpty) {
      final paint = Paint()
        ..color = edgeColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(nodeRadius)),
        paint,
      );
      return;
    }
    final projection = MinimapProjection.fit(
      bounds: computeSceneBounds(
        graph.nodes.map((MinimapNode node) => node.rect).toList(),
      ),
      widgetSize: size,
    );
    final edgePaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.65)
      ..strokeWidth = 1.5;
    for (final edge in graph.edges) {
      canvas.drawLine(
        projection.toLocal(edge.from),
        projection.toLocal(edge.to),
        edgePaint,
      );
    }
    for (final node in graph.nodes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          projection.rectToLocal(node.rect),
          Radius.circular(nodeRadius),
        ),
        Paint()..color = node.color.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WorkspacePreviewPainter oldDelegate) =>
      oldDelegate.graph != graph ||
      oldDelegate.edgeColor != edgeColor ||
      oldDelegate.nodeRadius != nodeRadius;
}
