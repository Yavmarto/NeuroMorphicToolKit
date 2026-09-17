import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/deploy_review_step.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/run_step/run_step.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/setup_step.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/canvas_screen.dart';

/// Dispatches pipeline step index → step widget without routing by raw index.
class StudioPipelineStepContent extends StatelessWidget {
  const StudioPipelineStepContent({
    super.key,
    required this.index,
    required this.setupStepKey,
    required this.runResultView,
    required this.onRunResultViewChanged,
    required this.onManageHardwareTarget,
    required this.deployPanel,
    this.showSetupWorkspaceActions = false,
  });

  final int index;
  final GlobalKey<SetupStepState> setupStepKey;
  final StudioResultView runResultView;
  final ValueChanged<StudioResultView> onRunResultViewChanged;
  final Future<void> Function(String targetId) onManageHardwareTarget;
  final Widget deployPanel;
  final bool showSetupWorkspaceActions;

  @override
  Widget build(BuildContext context) {
    final stepName = index >= 0 && index < kStudioPipelineStepNames.length
        ? kStudioPipelineStepNames[index]
        : kDefaultStudioPipelineStep;
    return switch (stepName) {
      'selectData' => SetupStep(
        key: setupStepKey,
        showWorkspaceActions: showSetupWorkspaceActions,
        onManageHardwareTarget: onManageHardwareTarget,
      ),
      'defineModel' => const KeepAliveWrapper(
        child: CanvasScreen(lockedTab: CanvasTab.architecture),
      ),
      'defineTrain' => const KeepAliveWrapper(
        child: CanvasScreen(lockedTab: CanvasTab.pipelineTrain),
      ),
      'defineEval' => const KeepAliveWrapper(
        child: CanvasScreen(lockedTab: CanvasTab.pipelineEval),
      ),
      'run' => KeepAliveWrapper(
        child: RunStep(
          view: runResultView,
          onViewChanged: onRunResultViewChanged,
        ),
      ),
      'deployReview' => const DeployReviewStep(),
      _ => DeployHardwareStep(child: deployPanel),
    };
  }
}
