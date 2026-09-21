library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_body.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_compare_body.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_compare_chip.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_empty_state.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_provenance.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_target_dropdown.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/review_publish_action.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/support.dart';

class DeployReviewStep extends ConsumerWidget {
  const DeployReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTarget = ref.watch(
      workspaceProvider.select((workspace) => workspace.selectedDeployTarget),
    );
    // Akida layers its hardware activity onto the source run, so it has
    // something to show as soon as a training snapshot exists — the hardware
    // overlay is additive, not a precondition.
    final hasSourceRun =
        selectedTarget == 'akida' &&
        ref.watch(
              studioResultSessionProvider.select(
                (session) => session.persistableSnapshot,
              ),
            ) !=
            null;
    final hasResult =
        ref.watch(deployTargetHasResultProvider(selectedTarget)) ||
        hasSourceRun;
    final targetsWithResults = ref.watch(deployTargetsWithResultsProvider);
    final compareMode = ref.watch(reviewCompareModeProvider);
    final compareTargets = ref.watch(reviewCompareTargetsProvider);
    final activeCompareTargets = compareMode
        ? compareTargets
              .where(targetsWithResults.contains)
              .toList(growable: false)
        : const <String>[];
    final showCompareBody = activeCompareTargets.length >= 2;

    // Matches StudioLayoutMetrics' mobile-shell boundary, not the
    // desktop-only "below stepper header row" threshold: StudioMobileShell
    // never renders that header row, so this inline header is the only place
    // the platform dropdown appears for the whole mobile-shell width range.
    final showInlineHeader =
        MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showInlineHeader) ...[
            Row(
              children: [
                Expanded(
                  child: DeployReviewTargetDropdown(
                    selectedTarget: selectedTarget,
                  ),
                ),
                const SizedBox(width: 8),
                const DeployReviewCompareChip(),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: DeployReviewProvenance(target: selectedTarget)),
              ],
            ),
            const SizedBox(height: 12),
            const ReviewPublishAction(showDisabledReason: true),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: showCompareBody
                ? DeployReviewCompareBody(targets: activeCompareTargets)
                : hasResult
                ? DeployReviewBody(selectedTarget: selectedTarget)
                : DeployReviewEmptyState(
                    selectedTarget: selectedTarget,
                    targetsWithResults: targetsWithResults
                        .where((target) => target != selectedTarget)
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}
