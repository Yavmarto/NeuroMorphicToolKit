import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';

class BenchmarkHeaderCard extends ConsumerWidget {
  const BenchmarkHeaderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final benchmark = ref.watch(activeBenchmarkProvider);
    final latestResult = ref.watch(latestResultProvider);

    if (benchmark == null) {
      return const SizedBox.shrink();
    }

    final subtitle = [
      benchmark.taskType,
      benchmark.inputSpec.type,
      'Primary metric: ${benchmark.scoring.primaryMetric}',
    ].join('  •  ');

    return NmtkSection(
      title: benchmark.name,
      subtitle: subtitle,
      trailing: _HeaderMetricChip(latestResult: latestResult),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(benchmark.description),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetadataPill(
                icon: benchmark.builtin ? ZetaIcons.verified : ZetaIcons.build,
                label: benchmark.builtin
                    ? 'Built-in benchmark'
                    : 'Custom benchmark',
              ),
              _MetadataPill(
                icon: Icons
                    .rule_folder_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: '${benchmark.assertions.length} assertions',
              ),
              _MetadataPill(
                icon: ZetaIcons.flag,
                label:
                    'Pass threshold ${benchmark.scoring.passThreshold.toStringAsFixed(2)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetricChip extends StatelessWidget {
  const _HeaderMetricChip({required this.latestResult});

  final BenchmarkResult? latestResult;

  @override
  Widget build(BuildContext context) {
    final latest = latestResult;
    if (latest == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Latest run', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            latest.id.substring(
              0,
              latest.id.length < 12 ? latest.id.length : 12,
            ),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
