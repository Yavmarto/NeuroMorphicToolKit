import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/platform_summary.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/support.dart';

class MultiPlatformCurveChart extends StatelessWidget {
  const MultiPlatformCurveChart({
    super.key,
    required this.summaries,
    required this.chartType,
    required this.colors,
  });

  final List<PlatformSummary> summaries;
  final CurveChartType chartType;
  final ZetaColors colors;

  @override
  Widget build(BuildContext context) {
    final isLoss = chartType == CurveChartType.loss;
    final title = isLoss ? 'Loss' : 'Accuracy';

    // Build one LineChartBarData per platform.
    final lines = <LineChartBarData>[];
    for (var i = 0; i < summaries.length; i++) {
      final curve = isLoss
          ? summaries[i].lossCurve
          : summaries[i].accuracyCurve;
      if (curve.isEmpty) continue;
      lines.add(
        LineChartBarData(
          spots: curve.map((p) => FlSpot(p.$1.toDouble(), p.$2)).toList(),
          isCurved: true,
          color: platformColor(i, colors),
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    if (lines.isEmpty) {
      return Center(
        child: Text(
          'No $title data',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Y axis range
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (final l in lines) {
      for (final s in l.spots) {
        if (s.y < minY) minY = s.y;
        if (s.y > maxY) maxY = s.y;
      }
    }
    final double yPad = ((maxY - minY) * 0.1).clamp(0.01, double.maxFinite);
    // Accuracy axis is 0..1, loss axis uses data range.
    final axisMinY = isLoss ? (minY - yPad).clamp(0.0, double.maxFinite) : 0.0;
    final axisMaxY = isLoss ? maxY + yPad : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: axisMinY,
              maxY: axisMaxY,
              clipData: const FlClipData.all(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppTheme.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: AppTheme.border),
                  left: BorderSide(color: AppTheme.border),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text(
                    'Epoch',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (v, meta) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, meta) => Text(
                      isLoss ? v.toStringAsFixed(2) : '${(v * 100).toInt()}%',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
              ),
              lineBarsData: lines,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => touchedSpots
                      .map(
                        (s) => LineTooltipItem(
                          isLoss
                              ? s.y.toStringAsFixed(4)
                              : '${(s.y * 100).toStringAsFixed(1)}%',
                          TextStyle(
                            color: s.bar.color ?? Zeta.of(context).colors.mainInverse,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
