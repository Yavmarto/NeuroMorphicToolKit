import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

/// Mapping from target ID to human-readable display name.
/// Single source of truth used by both the table and mobile list renderers.
const _kTargetPrettyNames = <String, String>{
  'cpu_pytorch': 'CPU (PyTorch)',
  'loihi2': 'Loihi 2',
  'brainscales2': 'BrainScaleS-2',
  'spinnaker2': 'SpiNNaker2',
  'xylo_synsense': 'Xylo (SyNSense)',
  'simulation': 'Simulation',
  'neurosim': 'Neurosim',
  'neurochip': 'NeurochipHW',
};

/// Grid comparing hardware target metrics side-by-side.
///
/// Shows run results when available; falls back to the seeded NeuroBench 1.0
/// published baselines so there is always something to compare on first open.
class TargetComparisonGrid extends ConsumerWidget {
  const TargetComparisonGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeBenchmarkIdProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);
    final baselinesAsync = ref.watch(baselinesProvider);

    return NmtkSection(
      title: 'Platform Comparison',
      subtitle: 'Metrics across hardware targets.',
      child: resultsAsync.when(
        data: (results) {
          final filtered = results
              .where((r) => activeId == null || r.benchmarkId == activeId)
              .toList();

          if (filtered.isNotEmpty) {
            return _ComparisonTable(items: filtered);
          }

          // No run results — fall back to published baselines
          return baselinesAsync.when(
            data: (baselines) {
              final baselineFiltered = baselines
                  .where((b) => activeId == null || b.benchmarkId == activeId)
                  .toList();

              if (baselineFiltered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select a benchmark to see platform comparisons.',
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons
                              .science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'NeuroBench v1.0 Published Results',
                          style: Zeta.of(context)
                              .textStyles
                              .bodyMedium
                              .copyWith(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _ComparisonTable(items: baselineFiltered),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error loading baselines: $err'),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Text('Error loading results: $err'),
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  final List<BenchmarkResult> items;

  const _ComparisonTable({required this.items});

  String _fmtMetric(String key, double? value) {
    if (value == null) return '—';
    switch (key) {
      case 'accuracy':
        return '${(value * 100).toStringAsFixed(1)}%';
      case 'latency_ms':
        return '${value.toStringAsFixed(2)} ms';
      case 'power_mw':
        return '${value.toStringAsFixed(1)} mW';
      case 'memory_kb':
        return '${value.toStringAsFixed(0)} KB';
      case 'energy_uj':
        return '${value.toStringAsFixed(2)} µJ';
      default:
        return value.toStringAsFixed(3);
    }
  }

  String _metricLabel(String key) {
    const labels = {
      'accuracy': 'Accuracy',
      'latency_ms': 'Latency',
      'power_mw': 'Power',
      'memory_kb': 'Memory',
      'energy_uj': 'Energy',
      'spike_fidelity': 'Fidelity',
    };
    return labels[key] ?? key;
  }

  List<String> _metricKeys() {
    const preferred = [
      'accuracy',
      'latency_ms',
      'energy_uj',
      'power_mw',
      'memory_kb',
    ];
    final seen = <String>{};
    for (final r in items) {
      seen.addAll(r.metrics.keys);
    }
    final ordered = preferred.where(seen.contains).toList();
    for (final k in seen) {
      if (!ordered.contains(k)) ordered.add(k);
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final metricKeys = _metricKeys();
    final sorted = [...items]..sort((a, b) {
        final aAcc = a.metrics['accuracy'] ?? -1;
        final bAcc = b.metrics['accuracy'] ?? -1;
        return bAcc.compareTo(aAcc);
      });

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return _buildTable(context, sorted, metricKeys);
        }
        return _buildMobileList(context, sorted, metricKeys);
      },
    );
  }

  Widget _buildTable(
    BuildContext context,
    List<BenchmarkResult> sorted,
    List<String> metricKeys,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(NmtkShellTokens.of(context).radiusSm)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Platform',
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                ),
              ),
              for (final key in metricKeys)
                Expanded(
                  flex: 2,
                  child: Text(
                    _metricLabel(key),
                    textAlign: TextAlign.right,
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                  ),
                ),
            ],
          ),
        ),
        // Rows
        for (int i = 0; i < sorted.length; i++)
          _DataRow(
            result: sorted[i],
            metricKeys: metricKeys,
            isEven: i.isEven,
            formatMetric: _fmtMetric,
          ),
      ],
    );
  }

  Widget _buildMobileList(
    BuildContext context,
    List<BenchmarkResult> sorted,
    List<String> metricKeys,
  ) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final result = sorted[i];
        final rawTarget = result.targetId ?? result.id;
        final targetName = _kTargetPrettyNames[rawTarget] ?? rawTarget;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetName,
                  style: Zeta.of(
                    context,
                  ).textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final key in metricKeys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _metricLabel(key),
                          style: Zeta.of(context).textStyles.bodySmall,
                        ),
                        Text(
                          _fmtMetric(key, result.metrics[key]),
                          style: Zeta.of(context).textStyles.bodySmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DataRow extends StatelessWidget {
  final BenchmarkResult result;
  final List<String> metricKeys;
  final bool isEven;
  final String Function(String, double?) formatMetric;

  const _DataRow({
    required this.result,
    required this.metricKeys,
    required this.isEven,
    required this.formatMetric,
  });

  String _prettyTarget(String raw) {
    return _kTargetPrettyNames[raw] ?? raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetName = _prettyTarget(result.targetId ?? result.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isEven
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  targetName,
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (result.params['framework'] != null)
                  Text(
                    result.params['framework'].toString(),
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          for (final key in metricKeys)
            Expanded(
              flex: 2,
              child: _MetricCell(
                metricKey: key,
                value: result.metrics[key],
                formatMetric: formatMetric,
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String metricKey;
  final double? value;
  final String Function(String, double?) formatMetric;

  const _MetricCell({
    required this.metricKey,
    required this.value,
    required this.formatMetric,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final text = formatMetric(metricKey, value);
    final isAccuracy = metricKey == 'accuracy';

    Color textColor = theme.colorScheme.onSurface;
    if (isAccuracy && value != null) {
      if (value! >= 0.90) {
        textColor = tokens.healthyColor;
      } else if (value! >= 0.80) {
        // ZETA-MIGRATION-TODO: verify degraded vs warning
        textColor = tokens.degradedColor;
      } else {
        textColor = tokens.errorColor;
      }
    }

    return Text(
      text,
      textAlign: TextAlign.right,
      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            fontSize: 13,
            fontWeight: isAccuracy ? FontWeight.w600 : FontWeight.w400,
            color: textColor,
          ),
    );
  }
}
