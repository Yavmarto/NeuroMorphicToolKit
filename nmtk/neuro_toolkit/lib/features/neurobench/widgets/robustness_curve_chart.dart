import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

/// Robustness view — shows per-platform accuracy from baselines or run results.
class RobustnessCurveChart extends ConsumerWidget {
  const RobustnessCurveChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final activeId = ref.watch(activeBenchmarkIdProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);
    final baselinesAsync = ref.watch(baselinesProvider);

    if (activeBenchmark == null) {
      return const NmtkSection(
        title: 'Robustness',
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Select a benchmark to view robustness metrics.'),
        ),
      );
    }

    return NmtkSection(
      title: 'Robustness — ${activeBenchmark.name}',
      subtitle:
          'Accuracy across platforms. Run a fault sweep for degradation curves.',
      child: resultsAsync.when(
        data: (results) {
          final filtered =
              results.where((r) => r.benchmarkId == activeId).toList();

          if (filtered.isNotEmpty) {
            return _AccuracyBarChart(items: filtered, title: 'Run Results');
          }

          return baselinesAsync.when(
            data: (baselines) {
              final bFiltered =
                  baselines.where((b) => b.benchmarkId == activeId).toList();
              if (bFiltered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No results yet. Run a benchmark to populate.'),
                );
              }
              return _AccuracyBarChart(
                items: bFiltered,
                title: 'NeuroBench v1.0 Published Accuracy',
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error: $err'),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Text('Error: $err'),
      ),
    );
  }
}

class _AccuracyBarChart extends StatelessWidget {
  final List<BenchmarkResult> items;
  final String title;

  const _AccuracyBarChart({required this.items, required this.title});

  String _prettyTarget(String? raw) {
    const names = {
      'cpu_pytorch': 'CPU (PyTorch)',
      'loihi2': 'Loihi 2',
      'brainscales2': 'BrainScaleS-2',
      'spinnaker2': 'SpiNNaker2',
      'xylo_synsense': 'Xylo (SyNSense)',
      'simulation': 'Simulation',
      'neurosim': 'Neurosim',
      'neurochip': 'NeurochipHW',
    };
    return names[raw ?? ''] ?? raw ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sorted = [...items]..sort((a, b) {
        final aAcc = a.metrics['accuracy'] ?? 0;
        final bAcc = b.metrics['accuracy'] ?? 0;
        return bAcc.compareTo(aAcc);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
        ),
        const SizedBox(height: 12),
        for (final result in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AccuracyBar(
              label: _prettyTarget(result.targetId),
              accuracy: result.metrics['accuracy'],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Run a fault-injection sweep to see degradation curves per noise level.',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _AccuracyBar extends StatelessWidget {
  final String label;
  final double? accuracy;

  const _AccuracyBar({required this.label, this.accuracy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final pct = accuracy ?? 0.0;
    final displayText =
        accuracy != null ? '${(pct * 100).toStringAsFixed(1)}%' : '—';

    Color barColor = theme.colorScheme.primary;
    if (accuracy != null) {
      if (pct >= 0.90) {
        barColor = tokens.healthyColor;
      } else if (pct >= 0.80) {
        // ZETA-MIGRATION-TODO: verify degraded vs warning
        barColor = tokens.degradedColor;
      } else {
        barColor = tokens.errorColor;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            Text(
              displayText,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 12,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
