import 'dart:math' as math;

import 'package:flutter/material.dart';

class AkidaRasterPainter extends CustomPainter {
  const AkidaRasterPainter({
    required this.values,
    required this.samples,
    required this.neurons,
    required this.color,
  });

  final List<double> values;
  final int samples;
  final int neurons;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples == 0 || neurons == 0) return;
    final paint = Paint()..color = color;
    final radius = math.max(0.7, math.min(2.0, size.width / samples / 3));
    for (var sample = 0; sample < samples; sample++) {
      for (var neuron = 0; neuron < neurons; neuron++) {
        if (values[sample * neurons + neuron] == 0) continue;
        canvas.drawCircle(
          Offset(
            (sample + 0.5) * size.width / samples,
            (neuron + 0.5) * size.height / neurons,
          ),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AkidaRasterPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.samples != samples ||
      oldDelegate.neurons != neurons ||
      oldDelegate.color != color;
}
