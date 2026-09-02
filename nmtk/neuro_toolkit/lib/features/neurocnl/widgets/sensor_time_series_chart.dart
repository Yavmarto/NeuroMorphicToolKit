import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sensor_frame.dart';

/// Displays recent sensor frame values as a sparkline using [CustomPaint].
///
/// Shows the latest [maxPoints] EMG channel values as small line charts,
/// one per channel.
class SensorTimeSeriesChart extends StatelessWidget {
  final List<SensorFrame> frames;
  final int maxPoints;

  const SensorTimeSeriesChart({
    super.key,
    required this.frames,
    this.maxPoints = 60,
  });

  @override
  Widget build(BuildContext context) {
    if (frames.isEmpty) {
      return Center(
        child: Text(
          'No sensor data yet',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: NmtkShellTokens.of(context).metadataForeground,
          ),
        ),
      );
    }

    final recent = frames.length > maxPoints
        ? frames.sublist(frames.length - maxPoints)
        : frames;
    final channelCount = recent.first.emgChannels.length;
    final channelPalette = NmtkShellTokens.instrumentChannelPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int ch = 0; ch < channelCount; ch++) ...[
          Text(
            'EMG Channel ${ch + 1}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: CustomPaint(
              size: const Size(double.infinity, 48),
              painter: _SparklinePainter(
                values: recent.map((f) => f.emgChannels[ch]).toList(),
                color: channelPalette[ch % channelPalette.length],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
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
