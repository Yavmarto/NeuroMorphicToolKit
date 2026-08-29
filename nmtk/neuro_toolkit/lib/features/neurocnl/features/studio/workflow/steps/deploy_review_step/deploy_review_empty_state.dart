library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';

class DeployReviewEmptyState extends ConsumerWidget {
  const DeployReviewEmptyState({
    super.key,
    required this.selectedTarget,
    required this.targetsWithResults,
  });

  final String selectedTarget;
  final List<String> targetsWithResults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final producesResults =
        kSimulatorDeployBackends.contains(selectedTarget) ||
        const <String>{'akida', 'lava', 'pynq'}.contains(selectedTarget);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ZetaIcons.analytics, size: 32, color: colors.mainSubtle),
          const SizedBox(height: 12),
          Text(
            producesResults
                ? 'No ${targetLabel(selectedTarget)} results yet.'
                : '${targetLabel(selectedTarget)} produces no run results.',
            style: textStyles.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            producesResults
                ? 'Run this target in the Deploy step to see its results here.'
                : 'This target is preview/verdict only — its output is shown in '
                      'the Deploy step.',
            textAlign: TextAlign.center,
            style: textStyles.bodyMedium.copyWith(color: colors.mainSubtle),
          ),
          // No second "Back to Deploy" here: the step header always renders one.
          if (targetsWithResults.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Results are available for:',
              style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final target in targetsWithResults)
                  NmtkOutlinedButton(
                    onPressed: () => ref
                        .read(workspaceProvider.notifier)
                        .setSelectedDeployTarget(target),
                    label: targetLabel(target),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
