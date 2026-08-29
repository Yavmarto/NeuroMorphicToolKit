import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// The scene-space bounding box that contains every rect in [nodeRects].
/// Returns [Rect.zero] when [nodeRects] is empty.
Rect computeSceneBounds(List<Rect> nodeRects) {
  if (nodeRects.isEmpty) {
    return Rect.zero;
  }
  Rect bounds = nodeRects.first;
  for (final Rect rect in nodeRects.skip(1)) {
    bounds = bounds.expandToInclude(rect);
  }
  return bounds;
}

/// Maps between scene-space coordinates and a minimap widget's local
/// coordinate space, fitting [bounds] into [widgetSize] with [padding] on
/// all sides while preserving aspect ratio (letterboxed on the slack axis).
class MinimapProjection {
  const MinimapProjection._({
    required this.bounds,
    required this.scale,
    required this.origin,
  });

  factory MinimapProjection.fit({
    required Rect bounds,
    required Size widgetSize,
    double padding = 8,
  }) {
    final double availableWidth = widgetSize.width - 2 * padding;
    final double availableHeight = widgetSize.height - 2 * padding;

    double scale;
    if (bounds.width <= 0 && bounds.height <= 0) {
      scale = 1.0;
    } else if (bounds.width <= 0) {
      scale = availableHeight / bounds.height;
    } else if (bounds.height <= 0) {
      scale = availableWidth / bounds.width;
    } else {
      scale = availableWidth / bounds.width < availableHeight / bounds.height
          ? availableWidth / bounds.width
          : availableHeight / bounds.height;
    }
    if (!scale.isFinite || scale <= 0) {
      scale = 1.0;
    }

    final Size contentSize = Size(bounds.width * scale, bounds.height * scale);
    final Offset origin = Offset(
      (widgetSize.width - contentSize.width) / 2,
      (widgetSize.height - contentSize.height) / 2,
    );

    return MinimapProjection._(bounds: bounds, scale: scale, origin: origin);
  }

  final Rect bounds;
  final double scale;
  final Offset origin;

  Offset toLocal(Offset scene) => origin + (scene - bounds.topLeft) * scale;

  Offset toScene(Offset local) => bounds.topLeft + (local - origin) / scale;

  Rect rectToLocal(Rect scene) =>
      Rect.fromPoints(toLocal(scene.topLeft), toLocal(scene.bottomRight));
}

/// The scene-space rect currently visible through [transform] within a
/// viewport of [viewportSize] -- the inverse of the scale+translate applied
/// by the host canvas's `TransformationController`.
Rect computeViewportRectInScene(Matrix4 transform, Size viewportSize) {
  final Matrix4 inverse = Matrix4.inverted(transform);
  final Offset topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final Offset bottomRight = MatrixUtils.transformPoint(
    inverse,
    Offset(viewportSize.width, viewportSize.height),
  );
  return Rect.fromPoints(topLeft, bottomRight);
}

/// A single edge, resolved to scene-space endpoints, for minimap rendering.
class MinimapEdgeLine {
  const MinimapEdgeLine(this.from, this.to);
  final Offset from;
  final Offset to;
}

/// A single node, resolved to its scene-space rect and its real on-canvas
/// category color (e.g. `nirCategoryColor` for Architecture, `_categoryColor`
/// for Train/Eval), for minimap rendering. Carrying the node's real color
/// (rather than one flat accent for every node) is what lets the minimap read
/// as a truthful thumbnail of the actual graph instead of a decoration.
class MinimapNode {
  const MinimapNode(this.rect, this.color);
  final Rect rect;
  final Color color;
}

/// A small overview of a canvas's full node layout with the current
/// viewport highlighted, shared identically by the Architecture canvas
/// ([NetworkCanvas]) and the pipeline-phase canvases (Train / Eval in
/// [PipelinePhaseCanvas]) -- same reuse pattern as [CanvasPortWidget]: a
/// self-contained, callback-only widget with no provider reads of its own.
///
/// Tapping anywhere on the minimap calls [onJumpTo] with the corresponding
/// scene-space point; the host canvas is responsible for actually panning
/// there.
class CanvasMinimapWidget extends StatelessWidget {
  const CanvasMinimapWidget({
    super.key,
    required this.nodes,
    required this.edgeLines,
    required this.transformationController,
    required this.viewportSize,
    required this.onJumpTo,
    this.size = const Size(180, 130),
  });

  /// Every node on the host canvas, with its scene-space rect and its real
  /// on-canvas category color.
  final List<MinimapNode> nodes;

  /// Scene-space endpoints of every edge on the host canvas.
  final List<MinimapEdgeLine> edgeLines;

  /// The same controller the host canvas uses for its `InteractiveViewer`.
  final TransformationController transformationController;

  /// The rendered size of the host canvas's viewport (not the minimap's own
  /// size), used to compute the visible-area rectangle.
  final Size viewportSize;

  final void Function(Offset sceneCenter) onJumpTo;

  final Size size;

  @override
  Widget build(BuildContext context) {
    final NmtkShellTokens tokens = NmtkShellTokens.of(context);
    final MinimapProjection projection = MinimapProjection.fit(
      bounds: computeSceneBounds(nodes.map((MinimapNode n) => n.rect).toList()),
      widgetSize: size,
    );
    final BorderRadius radius = BorderRadius.circular(tokens.radiusSm);

    return Material(
      elevation: 4,
      color: tokens.utilityPanelBackground,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox.fromSize(
        size: size,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails details) =>
              onJumpTo(projection.toScene(details.localPosition)),
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: transformationController,
            builder: (BuildContext context, Matrix4 transform, Widget? _) {
              return CustomPaint(
                painter: _MinimapPainter(
                  nodes: nodes,
                  edgeLines: edgeLines,
                  projection: projection,
                  viewportRectInScene: computeViewportRectInScene(
                    transform,
                    viewportSize,
                  ),
                  viewportColor: tokens.studioPalette.accent,
                  edgeColor: tokens.chromeBorder,
                  nodeCornerRadius: tokens.radiusSm,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.nodes,
    required this.edgeLines,
    required this.projection,
    required this.viewportRectInScene,
    required this.viewportColor,
    required this.edgeColor,
    required this.nodeCornerRadius,
  });

  final List<MinimapNode> nodes;
  final List<MinimapEdgeLine> edgeLines;
  final MinimapProjection projection;
  final Rect viewportRectInScene;
  final Color viewportColor;
  final Color edgeColor;
  final double nodeCornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint edgePaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (final MinimapEdgeLine edge in edgeLines) {
      canvas.drawLine(
        projection.toLocal(edge.from),
        projection.toLocal(edge.to),
        edgePaint,
      );
    }

    for (final MinimapNode node in nodes) {
      final Rect localRect = projection.rectToLocal(node.rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(localRect, Radius.circular(nodeCornerRadius)),
        Paint()..color = node.color.withValues(alpha: 0.85),
      );
    }

    final Rect viewportLocalRect = projection.rectToLocal(viewportRectInScene);
    canvas.drawRect(
      viewportLocalRect,
      Paint()..color = viewportColor.withValues(alpha: 0.15),
    );
    canvas.drawRect(
      viewportLocalRect,
      Paint()
        ..color = viewportColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edgeLines != edgeLines ||
        oldDelegate.viewportRectInScene != viewportRectInScene ||
        oldDelegate.viewportColor != viewportColor ||
        oldDelegate.edgeColor != edgeColor ||
        oldDelegate.nodeCornerRadius != nodeCornerRadius;
  }
}
