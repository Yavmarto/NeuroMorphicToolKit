import 'package:flutter/material.dart';

/// Displays recent values as a sparkline using [CustomPaint].
class NmtkSparklineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  final String? label;

  const NmtkSparklineChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 48,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No data',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
        ],
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size(double.infinity, height),
            painter: _SparklinePainter(values: values, color: color),
          ),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;
    final effectiveRange = range == 0 ? 1.0 : range;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y =
          size.height - ((values[i] - minVal) / effectiveRange) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
