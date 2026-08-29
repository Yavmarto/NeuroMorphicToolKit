import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/dismissed_job_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/execution_provider.dart';

class ActiveJobsBar extends ConsumerStatefulWidget {
  const ActiveJobsBar({super.key});

  @override
  ConsumerState<ActiveJobsBar> createState() => _ActiveJobsBarState();
}

class _ActiveJobsBarState extends ConsumerState<ActiveJobsBar> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final executionState = ref.watch(benchmarkExecutionProvider);
    final activeBenchmark = ref.watch(activeBenchmarkProvider);
    final job = executionState.activeJob;
    final dismissedId = ref.watch(dismissedActiveJobBarIdProvider);

    if (job == null || job.id == dismissedId) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final tone = switch (job.status) {
      BenchmarkJobStatus.failed => tokens.errorColor.withValues(alpha: 0.12),
      BenchmarkJobStatus.completed => tokens.healthyColor.withValues(
          alpha: 0.12,
        ),
      BenchmarkJobStatus.cancelled => theme.colorScheme.surfaceContainerHighest,
      BenchmarkJobStatus.pending ||
      BenchmarkJobStatus.running =>
        tokens.runningColor.withValues(alpha: 0.12),
    };

    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        job.status.isTerminal
                            ? (job.status == BenchmarkJobStatus.failed
                                ? ZetaIcons.error_outline
                                : ZetaIcons.check_circle_outline)
                            : ZetaIcons.sync,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Background run • ${job.id}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(job.status.label, style: theme.textTheme.labelLarge),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded
                            ? ZetaIcons.expand_more
                            : ZetaIcons.expand_less,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activeBenchmark != null)
                        Text(
                          activeBenchmark.name,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 8),
                      _JobDetailRow(label: 'Network', value: job.networkPath),
                      if (job.resultId != null) ...[
                        const SizedBox(height: 6),
                        _JobDetailRow(label: 'Result', value: job.resultId!),
                      ],
                      if (job.error != null && job.error!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _JobDetailRow(label: 'Error', value: job.error!),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!job.status.isTerminal &&
                              !executionState.cancelling)
                            TextButton.icon(
                              onPressed: () => ref
                                  .read(benchmarkExecutionProvider.notifier)
                                  .cancelActiveJob(),
                              icon: const Icon(ZetaIcons.stop_circle),
                              label: const Text('Cancel'),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              ref
                                  .read(
                                    dismissedActiveJobBarIdProvider.notifier,
                                  )
                                  .set(job.id);
                            },
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobDetailRow extends StatelessWidget {
  const _JobDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
