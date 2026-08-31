// ignore_for_file: depend_on_referenced_packages
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show NmtkShellTokens;

/// Bordered spike raster plot with synSubject-colored spikes.
///
/// Displays spike times per neuron as vertical tick marks on a time axis.
/// Each plot is wrapped in a bordered container matching the old simulation
/// dashboard style (border radius 8, AppTheme.border, AppTheme.surface bg).
class SpikeRasterPlot extends StatelessWidget {
  final List<List<double>>
  spikes; // Outer list for neurons, inner list for spike times
  final double duration; // Total duration in milliseconds
  final String title;

  const SpikeRasterPlot({
    super.key,
    required this.spikes,
    required this.duration,
    this.title = 'Spike Raster Plot',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          const SizedBox(
            width: 4,
          ), // horizontal spacing if needed, but this was left: 4
          Text(
            title,
            style: Zeta.of(
              context,
            ).textStyles.labelSmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8), // 8px grid spacing
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(
                NmtkShellTokens.of(context).radiusSm,
              ),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                NmtkShellTokens.of(context).radiusSm,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final nNeurons = spikes.length;
                  if (nNeurons == 0) {
                    return Center(
                      child: Text(
                        'No spikes recorded.',
                        style: Zeta.of(context).textStyles.bodyMedium,
                      ),
                    );
                  }

                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: RasterPainter(
                      bodySmallStyle: Zeta.of(context).textStyles.bodySmall,
                      spikes: spikes,
                      duration: duration,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RasterPainter extends CustomPainter {
  final TextStyle bodySmallStyle;
  final List<List<double>> spikes;
  final double duration;

  RasterPainter({
    required this.bodySmallStyle,
    required this.spikes,
    required this.duration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (duration <= 0) return;

    const leftMargin = 40.0;
    const bottomMargin = 24.0;
    const topMargin = 8.0;
    const rightMargin = 8.0;

    final plotW = size.width - leftMargin - rightMargin;
    final plotH = size.height - topMargin - bottomMargin;

    final nNeurons = spikes.length;
    if (nNeurons == 0 || plotW <= 0 || plotH <= 0) return;

    final rowHeight = plotH / nNeurons;
    final pixelPerMs = plotW / duration;

    final spikePaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Background grid lines for neurons + Y-axis neuron-index labels.
    // Only label every Nth row when there are many neurons to avoid clutter.
    final labelEvery = nNeurons > 20 ? ((nNeurons / 20).ceil()) : 1;
    for (int i = 0; i <= nNeurons; i++) {
      final y = topMargin + i * rowHeight;
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      // Label the midpoint of each visible row.
      if (i < nNeurons && i % labelEvery == 0) {
        final labelY = topMargin + (i + 0.5) * rowHeight;
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: bodySmallStyle.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: leftMargin - 4);
        tp.paint(
          canvas,
          Offset(leftMargin - tp.width - 4, labelY - tp.height / 2),
        );
      }
    }

    // Vertical time grid (5 ticks)
    for (int i = 0; i <= 5; i++) {
      final x = leftMargin + plotW * i / 5;
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, size.height - bottomMargin),
        gridPaint,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: (duration * i / 5).toStringAsFixed(2),
          style: bodySmallStyle.copyWith(
            color: AppTheme.textSecondary,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, size.height - bottomMargin + 4),
      );
    }

    // Axis label
    final xLabel = TextPainter(
      text: TextSpan(
        text: 'Time (ms)',
        style: bodySmallStyle.copyWith(
          color: AppTheme.textSecondary,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabel.paint(
      canvas,
      Offset(leftMargin + plotW / 2 - xLabel.width / 2, size.height - 4),
    );

    // Draw spikes as small circles (old style)
    for (int i = 0; i < nNeurons; i++) {
      final y = topMargin + (i + 0.5) * rowHeight;
      final neuronSpikes = spikes[i];
      for (final t in neuronSpikes) {
        final x = leftMargin + t * pixelPerMs;
        if (x >= leftMargin && x <= size.width - rightMargin) {
          canvas.drawCircle(Offset(x, y), 1.2, spikePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant RasterPainter oldDelegate) {
    return oldDelegate.spikes != spikes || oldDelegate.duration != duration;
  }
}
