library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/support.dart';

class DeployReviewTargetDropdown extends ConsumerWidget {
  const DeployReviewTargetDropdown({super.key, required this.selectedTarget});

  final String selectedTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Zeta.of(context).colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Only expand when the parent hands us a finite width. The mobile
        // inline header wraps this in Expanded; the desktop top bar sits in a
        // horizontal scroll Row (unbounded width) where isExpanded would assert.
        final expandToParent =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite;
        return DropdownButton<String>(
          value: selectedTarget,
          isDense: true,
          isExpanded: expandToParent,
          underline: const SizedBox.shrink(),
          style: Zeta.of(
            context,
          ).textStyles.titleLarge.copyWith(fontWeight: FontWeight.w700),
          items: [
            for (final id in reviewableTargets)
              DropdownMenuItem<String>(
                value: id,
                enabled: ref.watch(deployTargetHasResultProvider(id)),
                child: Builder(
                  builder: (context) {
                    final hasResult = ref.watch(
                      deployTargetHasResultProvider(id),
                    );
                    return Text(
                      hasResult
                          ? targetLabel(id)
                          : '${targetLabel(id)} (not run yet)',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: hasResult
                          ? null
                          : Zeta.of(context).textStyles.bodyMedium.copyWith(
                              color: colors.mainSubtle,
                            ),
                    );
                  },
                ),
              ),
            // The currently selected target might not be in reviewableTargets
            // (e.g. workspace state predates this list, or points at a
            // codegen/FPGA target) — DropdownButton requires its value to match
            // an item, so add a synthetic one rather than crash.
            if (!reviewableTargets.contains(selectedTarget))
              DropdownMenuItem<String>(
                value: selectedTarget,
                child: Text(
                  targetLabel(selectedTarget),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
          ],
          onChanged: (target) {
            if (target != null) {
              ref
                  .read(workspaceProvider.notifier)
                  .setSelectedDeployTarget(target);
            }
          },
        );
      },
    );
  }
}
