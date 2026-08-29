import 'dart:typed_data';

import 'package:flutter/material.dart';

class WeightTilePainter extends CustomPainter {
  final Float32List weights;
  final int side;
  final double vmax;

  const WeightTilePainter({
    required this.weights,
    required this.side,
    required this.vmax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.isEmpty || side <= 0) return;
    final pixelW = size.width / side;
    final pixelH = size.height / side;
    for (int row = 0; row < side; row++) {
      for (int col = 0; col < side; col++) {
        final idx = row * side + col;
        if (idx >= weights.length) break;
        final color = _rdbu(weights[idx], vmax.abs() > 0 ? vmax : 1.0);
        canvas.drawRect(
          Rect.fromLTWH(col * pixelW, row * pixelH, pixelW + 0.5, pixelH + 0.5),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant WeightTilePainter old) =>
      old.weights != weights || old.vmax != vmax;
}

Color _rdbu(double value, double maximum) {
  final normalized = (value / maximum).clamp(-1.0, 1.0);
  if (normalized >= 0) {
    return Color.fromARGB(
      255,
      255,
      (255 * (1 - normalized)).round(),
      (255 * (1 - normalized)).round(),
    );
  }
  final absolute = -normalized;
  return Color.fromARGB(
    255,
    (255 * (1 - absolute)).round(),
    (255 * (1 - absolute)).round(),
    255,
  );
}
