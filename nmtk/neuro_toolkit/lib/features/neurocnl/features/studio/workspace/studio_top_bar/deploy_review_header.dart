import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';

class DeployReviewHeader extends ConsumerWidget {
  const DeployReviewHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTarget = ref.watch(
      workspaceProvider.select((workspace) => workspace.selectedDeployTarget),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DeployReviewTargetDropdown(selectedTarget: selectedTarget),
          const SizedBox(width: 8),
          const DeployReviewCompareChip(),
          const SizedBox(width: 16),
          DeployReviewProvenance(target: selectedTarget),
          const SizedBox(width: 16),
          const ReviewPublishAction(),
        ],
      ),
    );
  }
}
