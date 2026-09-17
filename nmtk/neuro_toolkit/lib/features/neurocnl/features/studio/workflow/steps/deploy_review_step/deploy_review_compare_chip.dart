library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/compare_targets_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/support.dart';

class DeployReviewCompareChip extends ConsumerWidget {
  const DeployReviewCompareChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetsWithResults = ref.watch(deployTargetsWithResultsProvider);
    final canCompare = targetsWithResults.length >= 2;
    final compareMode = ref.watch(reviewCompareModeProvider);
    final activeCount = compareMode
        ? ref
              .watch(reviewCompareTargetsProvider)
              .where(targetsWithResults.contains)
              .length
        : 0;

    return Tooltip(
      message: canCompare
          ? 'View multiple targets side by side'
          : 'Needs results from at least 2 targets',
      child: FilterChip(
        avatar: const Icon(ZetaIcons.columns, size: 16),
        label: Text(compareMode ? 'Comparing $activeCount' : 'Compare'),
        selected: compareMode,
        onSelected: canCompare
            ? (_) async {
                final initial = ref.read(reviewCompareTargetsProvider);
                final selection = await showDialog<Set<String>>(
                  context: context,
                  builder: (_) =>
                      CompareTargetsDialog(initialSelection: initial),
                );
                if (selection == null) return;
                ref.read(reviewCompareTargetsProvider.notifier).set(selection);
                ref
                    .read(reviewCompareModeProvider.notifier)
                    .set(selection.length >= 2);
              }
            : null,
      ),
    );
  }
}
