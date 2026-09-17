import 'package:flutter/material.dart';

class AkidaWeightMatrixPainter extends CustomPainter {
  const AkidaWeightMatrixPainter({
    required this.values,
    required this.inputs,
    required this.neurons,
    required this.maximum,
  });

  final List<double> values;
  final int inputs;
  final int neurons;
  final double maximum;

  @override
  void paint(Canvas canvas, Size size) {
    if (inputs == 0 || neurons == 0) return;
    final cellWidth = size.width / inputs;
    final cellHeight = size.height / neurons;
    final scale = maximum == 0 ? 1.0 : maximum;
    final paint = Paint();
    for (var input = 0; input < inputs; input++) {
      for (var neuron = 0; neuron < neurons; neuron++) {
        final value = values[input * neurons + neuron];
        paint.color = _rdbu(value, scale);
        canvas.drawRect(
          Rect.fromLTWH(
            input * cellWidth,
            neuron * cellHeight,
            cellWidth + 0.5,
            cellHeight + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant AkidaWeightMatrixPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.inputs != inputs ||
      oldDelegate.neurons != neurons ||
      oldDelegate.maximum != maximum;
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
