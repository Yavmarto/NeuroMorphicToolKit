import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';

class MetricDiffTable extends ConsumerWidget {
  const MetricDiffTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diffAsync = ref.watch(activeDiffProvider);
    final tokens = NmtkShellTokens.of(context);

    return diffAsync.when(
      data: (diff) {
        if (diff == null) {
          return const NmtkSection(
            title: 'Baseline Diff',
            subtitle:
                'Comparison appears after a baseline and a current run exist.',
            child: Text('No comparison data available'),
          );
        }

        return NmtkSection(
          title: 'Baseline Diff',
          subtitle:
              'Stable comparison table backed by existing diff payloads and baseline semantics.',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Metric')),
                DataColumn(label: Text('Baseline (avg ± std)')),
                DataColumn(label: Text('Current (avg ± std)')),
                DataColumn(label: Text('Diff %')),
                DataColumn(label: Text('Significance')),
                DataColumn(label: Text('Status')),
              ],
              rows: diff.metrics.map((metric) {
                final color = metric.status == MetricStatus.improved
                    ? tokens.healthyColor
                    : (metric.status == MetricStatus.regressed
                        ? tokens.errorColor
                        : tokens.metadataForeground);

                final isSignificant = metric.isSignificant ?? false;
                final rowColor = isSignificant
                    ? (metric.status == MetricStatus.improved
                        ? tokens.healthyColor.withValues(alpha: 0.05)
                        : (metric.status == MetricStatus.regressed
                            ? tokens.errorColor.withValues(alpha: 0.05)
                            : null))
                    : null;

                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>(
                    (states) => rowColor,
                  ),
                  cells: [
                    DataCell(Text(metric.name)),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metric.baselineValue.toStringAsFixed(2)),
                          if (metric.baselineStd != null)
                            Text(
                              '±${metric.baselineStd!.toStringAsFixed(2)}',
                              style: Zeta.of(context)
                                  .textStyles
                                  .bodyMedium
                                  .copyWith(
                                    fontSize: 10,
                                    color: tokens.metadataForeground,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metric.currentValue.toStringAsFixed(2)),
                          if (metric.currentStd != null)
                            Text(
                              '±${metric.currentStd!.toStringAsFixed(2)}',
                              style: Zeta.of(context)
                                  .textStyles
                                  .bodyMedium
                                  .copyWith(
                                    fontSize: 10,
                                    color: tokens.metadataForeground,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        '${metric.deltaPct > 0 ? "+" : ""}${metric.deltaPct.toStringAsFixed(1)}%',
                        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSignificant ? 'SIGNIFICANT' : 'Insignificant',
                            style:
                                Zeta.of(context).textStyles.bodyMedium.copyWith(
                                      fontSize: 10,
                                      fontWeight: isSignificant
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSignificant
                                          ? color
                                          : tokens.metadataForeground,
                                    ),
                          ),
                          if (metric.pValueTtest != null)
                            Text(
                              'p=${metric.pValueTtest!.toStringAsExponential(2)}',
                              style: Zeta.of(context)
                                  .textStyles
                                  .bodyMedium
                                  .copyWith(
                                    fontSize: 9,
                                    color: tokens.metadataForeground,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          Icon(
                            metric.thresholdViolated
                                ? ZetaIcons.error_outline
                                : ZetaIcons.check_circle_outline,
                            color: color,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            metric.status.name.toUpperCase(),
                            style: Zeta.of(context)
                                .textStyles
                                .bodyMedium
                                .copyWith(color: color, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const NmtkSection(
        title: 'Baseline Diff',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => NmtkSurfaceCard(
        title: 'Baseline Diff',
        tone: NmtkTone.danger,
        child: Text('Error: $err'),
      ),
    );
  }
}
