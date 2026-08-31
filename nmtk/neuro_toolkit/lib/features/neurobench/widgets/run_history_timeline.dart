import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

/// Timeline widget displaying past benchmark runs with status.
class RunHistoryTimeline extends ConsumerWidget {
  const RunHistoryTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(activeBenchmarkResultsProvider);

    return NmtkSection(
      title: 'Run History',
      subtitle: 'Recent benchmark runs preserved as stable result packets.',
      child: resultsAsync.when(
        data: (results) {
          if (results.isEmpty) {
            return const Text('No past runs for this benchmark.');
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final result = results[results.length - 1 - index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      ZetaIcons.history,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Run ID: ${result.id.substring(0, 8)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text('Date: ${result.timestamp}'),
                          Text(
                            'Wall time: ${result.wallTimeSeconds.toStringAsFixed(2)} s',
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      ZetaIcons.check_circle,
                      color: NmtkShellTokens.of(context).healthyColor,
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Text('Error: $err'),
      ),
    );
  }
}
