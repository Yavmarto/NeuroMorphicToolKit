import 'package:flutter/material.dart';

class FramePainter extends CustomPainter {
  const FramePainter({
    required this.spikes,
    required this.side,
    required this.on,
    required this.off,
  });

  final List<int> spikes;
  final int side;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / side;
    canvas.drawRect(Offset.zero & size, Paint()..color = off);
    final paint = Paint()..color = on;
    for (var row = 0; row < side; row++) {
      for (var column = 0; column < side; column++) {
        final index = row * side + column;
        if (index >= spikes.length || spikes[index] <= 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(column * cell, row * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FramePainter oldDelegate) =>
      oldDelegate.spikes != spikes ||
      oldDelegate.side != side ||
      oldDelegate.on != on ||
      oldDelegate.off != off;
}
