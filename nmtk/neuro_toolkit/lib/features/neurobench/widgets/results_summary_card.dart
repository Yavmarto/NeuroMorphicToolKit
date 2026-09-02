import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

class ResultsSummaryCard extends ConsumerWidget {
  const ResultsSummaryCard({super.key});

  String _getMetricTooltip(String metric) {
    switch (metric) {
      case 'accuracy':
        return 'Percentage of correctly classified samples.';
      case 'latency_ms':
        return 'Time taken from input to network response in milliseconds.';
      case 'power_mw':
        return 'Estimated power consumption of the SNN in milliwatts.';
      case 'memory_kb':
        return 'Peak memory usage during benchmark execution in kilobytes.';
      case 'spike_fidelity':
        return 'Similarity between target and actual spike trains (0.0 to 1.0).';
      case 'stopping_distance':
        return 'Distance moved by the prosthetic before stabilization.';
      case 'assertions_passed':
        return 'Number of CNL assertions that were satisfied during simulation.';
      case 'assertions_failed':
        return 'Number of CNL assertions that were violated during simulation.';
      case 'simulation_duration':
        return 'Total simulated time in seconds.';
      default:
        return 'Performance metric for this benchmark.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);
    final tokens = NmtkShellTokens.of(context);

    if (activeBenchmark == null) {
      return const NmtkSection(
        title: 'Results Summary',
        child: Text('No benchmark selected'),
      );
    }

    return resultsAsync.when(
      data: (results) {
        if (results.isEmpty) {
          return const NmtkSection(
            title: 'Results Summary',
            subtitle: 'Run the benchmark to populate the latest metrics.',
            child: Text('No results available for this benchmark'),
          );
        }

        final latestResult = results.last;
        final primaryMetric = activeBenchmark.scoring.primaryMetric;
        final primaryValue = latestResult.metrics[primaryMetric];

        return NmtkSection(
          title: 'Results Summary',
          subtitle:
              'Latest result snapshot and metric breakdown from the existing benchmark payload.',
          trailing: _SummaryStatusChip(
            label: latestResult.metricProvenance == 'on_device'
                ? 'On-Device'
                : 'CPU Estimated',
            // ZETA-MIGRATION-EXEMPT: no outlined memory/chip variant in ZetaIcons (only round)
            icon: latestResult.metricProvenance == 'on_device'
                ? ZetaIcons.memory
                // ZETA-MIGRATION-EXEMPT: no Zeta equivalent for generic desktop/CPU computer icon
                : Icons.computer_outlined,
            tone: latestResult.metricProvenance == 'on_device'
                ? NmtkTone.success
                : NmtkTone.warning,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox.shrink(),
                  Tooltip(
                    message: 'How to read these metrics',
                    child: ZetaIconButton(
                      icon: ZetaIcons.help_outline,
                      size: ZetaWidgetSize.small,
                      semanticLabel: 'How to read these metrics',
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Result Interpretation Guide'),
                            content: const SingleChildScrollView(
                              child: Text(
                                'NeuroBench metrics provide insights into the efficiency and accuracy of your SNN.\n\n'
                                '• Primary Metrics: The main focus of the benchmark (e.g., accuracy for classification).\n'
                                '• Latency: Lower is better for real-time applications.\n'
                                '• Power/Memory: Crucial for edge deployment.\n'
                                '• Assertions: Validate functional correctness of the neural dynamics.',
                              ),
                            ),
                            actions: [
                              ZetaButton.text(
                                onPressed: () => Navigator.pop(context),
                                label: 'Close',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Benchmark: ${activeBenchmark.name}'),
              Text('Timestamp: ${latestResult.timestamp}'),
              const SizedBox(height: 16),
              Tooltip(
                message: _getMetricTooltip(primaryMetric),
                child: Row(
                  children: [
                    Text(
                      '$primaryMetric: ',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      primaryValue?.toStringAsFixed(2) ?? 'N/A',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      ZetaIcons.info,
                      size: 16,
                      color: tokens.metadataForeground,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              ...latestResult.metrics.entries
                  .where((e) => e.key != primaryMetric)
                  .map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Tooltip(
                        message: _getMetricTooltip(entry.key),
                        child: Row(
                          children: [
                            Text(
                              '${entry.key}: ',
                              style: Zeta.of(context).textStyles.bodyMedium
                                  .copyWith(fontWeight: FontWeight.w500),
                            ),
                            Text(entry.value.toStringAsFixed(2)),
                            const SizedBox(width: 4),
                            Icon(
                              ZetaIcons.info,
                              size: 14,
                              color: tokens.metadataForeground,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
            ],
          ),
        );
      },
      loading: () => const NmtkSection(
        title: 'Results Summary',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => NmtkSurfaceCard(
        title: 'Results Summary',
        tone: NmtkTone.danger,
        child: Text('Error: $err'),
      ),
    );
  }
}

class _SummaryStatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final NmtkTone tone;

  const _SummaryStatusChip({
    required this.label,
    required this.icon,
    this.tone = NmtkTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return NmtkStatusBadge(label: label, icon: icon, tone: tone);
  }
}
