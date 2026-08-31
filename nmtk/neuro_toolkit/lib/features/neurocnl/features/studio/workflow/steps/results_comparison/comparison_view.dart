import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/canvas/canvas_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/activity_comparison_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/platform_summary.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/comparison_sidebar.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/multi_platform_curve_chart.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_comparison/support.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

class ComparisonView extends StatelessWidget {
  const ComparisonView({
    super.key,
    required this.summaries,
    this.activityComparison,
  });

  final List<PlatformSummary> summaries;

  final ActivityComparisonData? activityComparison;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final hasAccuracy = summaries.any((s) => s.accuracyCurve.isNotEmpty);

    return Stack(
      children: [
        // ── Canvas background (dimmed) ───────────────────────────────
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.35),
              BlendMode.darken,
            ),
            child: const CanvasScreen(
              lockedTab: CanvasTab.architecture,
              disableInspectorOverlay: true,
              disableEditingChrome: true,
            ),
          ),
        ),

        // ── Charts (center) ──────────────────────────────────────────
        Positioned(
          top: 16,
          left: 16,
          right: 16 + 240 + 16, // leave room for sidebar
          bottom: 16,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
            color: AppTheme.surface.withValues(alpha: 0.97),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Training Comparison',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Color legend
                  Wrap(
                    spacing: 12,
                    children: [
                      for (var i = 0; i < summaries.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: platformColor(i, colors),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              targetLabel(summaries[i].platformId),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: hasAccuracy
                        ? Row(
                            children: [
                              Expanded(
                                child: MultiPlatformCurveChart(
                                  summaries: summaries,
                                  chartType: CurveChartType.loss,
                                  colors: colors,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MultiPlatformCurveChart(
                                  summaries: summaries,
                                  chartType: CurveChartType.accuracy,
                                  colors: colors,
                                ),
                              ),
                            ],
                          )
                        : MultiPlatformCurveChart(
                            summaries: summaries,
                            chartType: CurveChartType.loss,
                            colors: colors,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Comparison sidebar (right) ────────────────────────────────
        Positioned(
          top: 16,
          right: 16,
          bottom: 16,
          width: 240,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
            clipBehavior: Clip.antiAlias,
            child: ComparisonSidebar(
              summaries: summaries,
              colors: colors,
              activityComparison: activityComparison,
            ),
          ),
        ),
      ],
    );
  }
}
