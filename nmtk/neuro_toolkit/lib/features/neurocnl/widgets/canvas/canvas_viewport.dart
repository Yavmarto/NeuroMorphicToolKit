import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';

/// Shared viewport plumbing for every canvas: the world-space matrix, the
/// viewport→scene conversion, the zoom limits and the zoom-by-a-step gesture.
///
/// The Architecture canvas and the pipeline-phase canvases each carried their
/// own copy of this arithmetic, differing only in which [CanvasWorldGeometry]
/// they closed over — and, accidentally, in their zoom limits (0.1–2.0 vs
/// 0.2–3.0), so the same pinch reached a different scale depending on which
/// tab you were on.
///
/// Hosts mix this in and supply [canvasWorld] and [canvasTransform]. Animated
/// pan-to-node stays with the host: it needs a ticker and each canvas resolves
/// its own node positions.

/// Smallest and largest zoom any canvas allows, and the step a keyboard
/// zoom-in/out applies.
const double kCanvasMinZoom = 0.1;
const double kCanvasMaxZoom = 3.0;
const double kCanvasZoomStep = 1.1;

mixin CanvasViewportMixin<T extends StatefulWidget> on State<T> {
  /// The world the canvas child is laid out in. Persisted node positions are
  /// signed scene coordinates; the world's origin puts (0, 0) in the middle of
  /// the child so negative coordinates stay inside it.
  CanvasWorldGeometry get canvasWorld;

  /// The controller driving this canvas's [InteractiveViewer].
  TransformationController get canvasTransform;

  /// Scene-space position of a point given in viewport (local) coordinates.
  Offset canvasSceneFromViewport(Offset viewportPosition) =>
      canvasWorld.childToScene(canvasTransform.toScene(viewportPosition));

  /// The matrix that shows [pan] at [zoom], accounting for the world origin.
  Matrix4 canvasWorldMatrix({required double zoom, required Offset pan}) =>
      Matrix4.identity()
        ..translateByDouble(
          pan.dx - canvasWorld.origin.dx * zoom,
          pan.dy - canvasWorld.origin.dy * zoom,
          0,
          1,
        )
        ..scaleByDouble(zoom, zoom, 1, 1);

  double get canvasZoom => canvasTransform.value.getMaxScaleOnAxis();

  double canvasClampZoom(double zoom) =>
      zoom.clamp(kCanvasMinZoom, kCanvasMaxZoom).toDouble();

  /// The matrix for zooming the current view by [multiplier], or null when
  /// that would not move the scale (already at a limit).
  ///
  /// Returned rather than applied so the host stays in charge of persisting
  /// the new viewport to its own state.
  Matrix4? canvasZoomedBy(double multiplier) {
    final Matrix4 matrix = canvasTransform.value.clone();
    final double currentZoom = matrix.getMaxScaleOnAxis();
    final double targetZoom = canvasClampZoom(currentZoom * multiplier);
    if ((targetZoom - currentZoom).abs() < 0.001) return null;
    final double scaleFactor = targetZoom / currentZoom;
    return matrix..scaleByDouble(scaleFactor, scaleFactor, 1, 1);
  }

  /// Puts [scenePoint] in the middle of a [viewportSize] viewport at the
  /// current zoom — what a minimap tap does.
  void canvasJumpTo(Offset scenePoint, Size viewportSize) {
    final double zoom = canvasZoom;
    canvasTransform.value = canvasWorldMatrix(
      zoom: zoom,
      pan: centeredPanFor(scenePoint, zoom, viewportSize),
    );
  }

  /// Back to 1:1, origin-centred.
  void canvasResetViewport() {
    canvasTransform.value = canvasWorldMatrix(zoom: 1, pan: Offset.zero);
  }
}
