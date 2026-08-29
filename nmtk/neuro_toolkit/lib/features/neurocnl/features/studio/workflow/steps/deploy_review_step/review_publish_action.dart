library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/hub/publish_results_dialog/support.dart';

class ReviewPublishAction extends ConsumerWidget {
  const ReviewPublishAction({super.key, this.showDisabledReason = false});

  final bool showDisabledReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Matches the rest of Review's result-gating (see the target dropdown
    // above): a run's outcome lives in the per-target deploy providers, not
    // in `workspace.benchmarkResultSummary` (never populated) or the
    // single-shot `pipelineProvider` simulate/generate result.
    final hasResults = ref.watch(deployResultsAvailableProvider);
    final button = Tooltip(
      message: hasResults
          ? 'Publish this workspace and its latest result to Hub'
          : 'Run the workspace before publishing results',
      child: OutlinedButton.icon(
        onPressed: hasResults ? () => showPublishResultsDialog(context) : null,
        icon: const Icon(ZetaIcons.cloud_upload, size: 18),
        label: const Text('Publish'),
      ),
    );
    if (hasResults || !showDisabledReason) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 4),
        Text(
          'Available after a run finishes.',
          style: Zeta.of(context).textStyles.bodySmall.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
      ],
    );
  }
}
