import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

/// Perturbation view — shows per-platform energy and latency from baselines.
class PerturbationCurveChart extends ConsumerWidget {
  const PerturbationCurveChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final activeId = ref.watch(activeBenchmarkIdProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);
    final baselinesAsync = ref.watch(baselinesProvider);

    if (activeBenchmark == null) {
      return const NmtkSection(
        title: 'Perturbation',
        subtitle: 'Noise tolerance across hardware platforms.',
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Select a benchmark to view perturbation metrics.'),
        ),
      );
    }

    return NmtkSection(
      title: 'Perturbation — ${activeBenchmark.name}',
      subtitle:
          'Energy and latency across platforms. Run a noise sweep for full curves.',
      child: resultsAsync.when(
        data: (results) {
          final filtered =
              results.where((r) => r.benchmarkId == activeId).toList();

          if (filtered.isNotEmpty) {
            return _EnergyLatencyChart(items: filtered, title: 'Run Results');
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
              return _EnergyLatencyChart(
                items: bFiltered,
                title: 'NeuroBench v1.0 Published Energy & Latency',
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

class _EnergyLatencyChart extends StatelessWidget {
  final List<BenchmarkResult> items;
  final String title;

  const _EnergyLatencyChart({required this.items, required this.title});

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
        final aE = a.metrics['energy_uj'] ?? a.metrics['latency_ms'] ?? 9999;
        final bE = b.metrics['energy_uj'] ?? b.metrics['latency_ms'] ?? 9999;
        return aE.compareTo(bE);
      });

    final maxEnergy = sorted
        .map((r) => r.metrics['energy_uj'] ?? 0)
        .fold<double>(0, (p, e) => e > p ? e : p);
    final maxLatency = sorted
        .map((r) => r.metrics['latency_ms'] ?? 0)
        .fold<double>(0, (p, e) => e > p ? e : p);

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
        // Column headers
        Row(
          children: [
            const Expanded(flex: 3, child: SizedBox()),
            Expanded(
              flex: 2,
              child: Text(
                'Energy (µJ)',
                textAlign: TextAlign.center,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Latency (ms)',
                textAlign: TextAlign.center,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final result in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    _prettyTarget(result.targetId),
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _MiniBar(
                    value: result.metrics['energy_uj'],
                    maxValue: maxEnergy,
                    color: theme.colorScheme.tertiary,
                    suffix: 'µJ',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _MiniBar(
                    value: result.metrics['latency_ms'],
                    maxValue: maxLatency,
                    color: theme.colorScheme.secondary,
                    suffix: 'ms',
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Lower energy and latency → more efficient platform.',
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

class _MiniBar extends StatelessWidget {
  final double? value;
  final double maxValue;
  final Color color;
  final String suffix;

  const _MiniBar({
    this.value,
    required this.maxValue,
    required this.color,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value == null) {
      return Text(
        '—',
        textAlign: TextAlign.center,
        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
      );
    }
    final fraction = maxValue > 0 ? (value! / maxValue).clamp(0.0, 1.0) : 0.0;
    final label = value! < 10
        ? '${value!.toStringAsFixed(2)} $suffix'
        : '${value!.toStringAsFixed(1)} $suffix';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
