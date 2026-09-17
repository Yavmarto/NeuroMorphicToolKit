import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One stop in a radial glow sprite — [offset] in `0..1`, [alpha] in `0..1`.
class GlowStop {
  const GlowStop(this.offset, this.alpha);

  final double offset;
  final double alpha;
}

/// Soft radial-gradient glow sprites with additive blending.
///
/// AIS-OS builds these as canvas textures for Three.js point maps; here the
/// same falloff is expressed as a [ui.Gradient.radial] on a [Paint] with
/// [BlendMode.plus]. Pure function of its arguments — no texture cache needed
/// at network-view scale.
class GlowSprite {
  GlowSprite._();

  static const List<GlowStop> _discStops = <GlowStop>[
    GlowStop(0.0, 1.0),
    GlowStop(0.45, 0.35),
    GlowStop(1.0, 0.0),
  ];

  /// Returns a fill [Paint] for a soft radial disc.
  static Paint radial({
    required Offset center,
    required double radius,
    required Color color,
    Iterable<GlowStop> stops = _discStops,
    double intensity = 1.0,
    BlendMode blendMode = BlendMode.plus,
  }) {
    final resolvedStops = <Color>[];
    final offsets = <double>[];
    for (final stop in stops) {
      resolvedStops.add(
        color.withValues(alpha: (stop.alpha * intensity).clamp(0.0, 1.0)),
      );
      offsets.add(stop.offset.clamp(0.0, 1.0));
    }
    return Paint()
      ..blendMode = blendMode
      ..shader = ui.Gradient.radial(center, radius, resolvedStops, offsets);
  }

  /// Draws one additive orbit ring — blurred underlay plus a crisp stroke.
  static void ring(
    Canvas canvas, {
    required double radiusX,
    required double radiusY,
    required Color color,
    double alpha = 0.2,
    double strokeWidth = 1.5,
    BlendMode blendMode = BlendMode.plus,
  }) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: radiusX * 2,
      height: radiusY * 2,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..blendMode = blendMode
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 5
        ..color = color.withValues(alpha: (alpha * 0.45).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..blendMode = blendMode
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }
}
