// ignore_for_file: depend_on_referenced_packages
import 'package:zeta_flutter/zeta_flutter.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' show NmtkShellTokens;

/// Palette shared by the time-series chart and animated playback painters.
///
/// Eight semantically-distinct colors, cycling when there are more traces than
/// colours.  Matches the swatches painted by [_VoltageLegend] in
/// `snn_dynamics_view.dart` so the legend and the chart stay in sync.
List<Color> traceColorPalette(BuildContext context) {
  final colors = Zeta.of(context).colors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    colors.mainPrimary,
    colors.mainPositive,
    colors.mainNegative,
    colors.mainWarning,
    colors.mainInfo,
    colors.primitives.primary.shade20,
    colors.mainPrimary.withValues(alpha: isDark ? 0.6 : 0.5),
    colors.mainPositive.withValues(alpha: isDark ? 0.6 : 0.5),
  ];
}

/// Bordered time-series chart for membrane-potential traces.
///
/// Rendered inside a bordered container matching the old simulation dashboard
/// style. Each trace uses a distinct colour from [traceColorPalette]; Y-axis
/// labels show the voltage range in mV.
class TimeSeriesChart extends StatelessWidget {
  final List<List<double>>
  traces; // Outer list for traces, inner list for time-series values
  final List<double> time; // Corresponding time points
  final List<String> labels;
  final String title;

  const TimeSeriesChart({
    super.key,
    required this.traces,
    required this.time,
    required this.labels,
    this.title = 'Voltage Traces (mV)',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            title,
            style: Zeta.of(
              context,
            ).textStyles.labelSmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
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
                  if (time.isEmpty || traces.isEmpty) {
                    return Center(
                      child: Text(
                        'No traces to display.',
                        style: Zeta.of(context).textStyles.bodyMedium,
                      ),
                    );
                  }

                  return CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: ChartPainter(
                      bodySmallStyle: Zeta.of(context).textStyles.bodySmall,
                      traces: traces,
                      time: time,
                      colors: traceColorPalette(context),
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

class ChartPainter extends CustomPainter {
  final TextStyle bodySmallStyle;
  final List<List<double>> traces;
  final List<double> time;
  final List<Color> colors;

  ChartPainter({
    required this.bodySmallStyle,
    required this.traces,
    required this.time,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (time.isEmpty || traces.isEmpty) return;

    const leftMargin = 40.0;
    const bottomMargin = 24.0;
    const topMargin = 8.0;
    const rightMargin = 8.0;

    final plotW = size.width - leftMargin - rightMargin;
    final plotH = size.height - topMargin - bottomMargin;
    if (plotW <= 0 || plotH <= 0) return;

    final double minX = time.first;
    final double maxX = time.last;
    final double rangeX = maxX - minX;
    if (rangeX <= 0) return;

    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (var trace in traces) {
      for (var v in trace) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }

    if (minY == maxY) {
      minY -= 1.0;
      maxY += 1.0;
    }

    final double paddingY = (maxY - minY) * 0.1;
    minY -= paddingY;
    maxY += paddingY;
    final double rangeY = maxY - minY;

    final xStep = plotW / rangeX;

    // Grid
    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal Y-axis grid lines + labels (5 ticks)
    const yTicks = 5;
    for (int i = 0; i <= yTicks; i++) {
      final frac = i / yTicks;
      final yVal = maxY - frac * rangeY;
      final y = topMargin + frac * plotH;

      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      final yLabel = TextPainter(
        text: TextSpan(
          text: yVal.toStringAsFixed(1),
          style: bodySmallStyle.copyWith(
            color: AppTheme.textSecondary,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftMargin - 4);
      yLabel.paint(
        canvas,
        Offset(leftMargin - yLabel.width - 4, y - yLabel.height / 2),
      );
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
          text: (maxX * i / 5).toStringAsFixed(2),
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

    // Per-trace colored lines; sample every Nth point for performance.
    final step = math.max(1, traces.first.length ~/ 500);

    for (int ti = 0; ti < traces.length; ti++) {
      final trace = traces[ti];
      final color = colors[ti % colors.length];
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final path = Path();
      var first = true;
      for (int i = 0; i < trace.length; i += step) {
        final double x = leftMargin + (time[i] - minX) * xStep;
        final double y =
            topMargin + plotH - ((trace[i] - minY) / rangeY) * plotH;

        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) {
    return oldDelegate.traces != traces ||
        oldDelegate.time != time ||
        oldDelegate.colors != colors;
  }
}
