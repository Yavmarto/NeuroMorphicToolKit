import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/pipeline_stage_area.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/workspace_tab_view_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_layout_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_top_bar/deploy_review_header.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_top_bar/setup_header_actions.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_top_bar/studio_utility_pill.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_top_bar/studio_workflow_accordion.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/setup_step.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/studio_overlay_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';

class StudioDesktopShell extends StatelessWidget {
  const StudioDesktopShell({
    super.key,
    required this.layoutConstraints,
    required this.activeStep,
    required this.unlockedSteps,
    required this.workspaceTabs,
    required this.splitPipelineStep,
    required this.metrics,
    required this.setupStepKey,
    required this.stepBuilder,
    required this.frameBuilder,
    required this.onPhaseSelected,
    required this.onSplitLeft,
    required this.onSplitRight,
    required this.onCollapseSplit,
    required this.onActiveFileSelected,
    required this.onFileClosed,
    required this.onSaveWorkspace,
    required this.onShareToNeurohub,
    this.workspaceHeaderAction,
  });

  final BoxConstraints layoutConstraints;
  final String activeStep;
  final Set<String> unlockedSteps;
  final WorkspaceTabViewData workspaceTabs;
  final String? splitPipelineStep;
  final StudioLayoutMetrics metrics;
  final GlobalKey<SetupStepState> setupStepKey;
  final Widget Function(int index) stepBuilder;
  final Widget Function({required Widget child}) frameBuilder;
  final ValueChanged<SnnWorkflowPhase> onPhaseSelected;
  final ValueChanged<String> onSplitLeft;
  final ValueChanged<String> onSplitRight;
  final ValueChanged<String> onCollapseSplit;
  final ValueChanged<String> onActiveFileSelected;
  final ValueChanged<String> onFileClosed;
  final Future<void> Function() onSaveWorkspace;
  final Future<void> Function() onShareToNeurohub;
  final Widget? workspaceHeaderAction;

  static const _kCanvasSteps = {
    'defineModel',
    'defineTrain',
    'defineEval',
    'run',
  };

  @override
  Widget build(BuildContext context) {
    void handleStepNameSelected(String name) {
      final phase = SnnWorkflowPhase.values.firstWhere(
        (candidate) => candidate.name == name,
      );
      onPhaseSelected(phase);
    }

    final workflowAccordion = StudioWorkflowAccordion(
      activeStep: activeStep,
      splitStep: splitPipelineStep,
      onStepSelected: onPhaseSelected,
      onSplitLeft: onSplitLeft,
      onSplitRight: onSplitRight,
      onCollapse: onCollapseSplit,
    );
    final utilityPill = StudioUtilityPill(
      files: workspaceTabs.files,
      activeFileId: workspaceTabs.activeFileId,
      workspaceName: workspaceTabs.workspaceName,
      workspaceHeaderAction: workspaceHeaderAction,
      onSelected: onActiveFileSelected,
      onClosed: onFileClosed,
      onSaveActiveFile: () => unawaited(onSaveWorkspace()),
      onShareToNeurohub: () => unawaited(onShareToNeurohub()),
    );

    final stageArea = PipelineStageArea(
      activeStep: activeStep,
      splitStep: splitPipelineStep,
      stepCount: kStudioPipelineStepNames.length,
      stepBuilder: stepBuilder,
      frameBuilder: frameBuilder,
      canvasStepNames: _kCanvasSteps,
      unlockedStepNames: unlockedSteps,
      topInset: metrics.topInset,
      contentTopPad: metrics.contentTopPad,
      onStepChanged: handleStepNameSelected,
      onCollapse: onCollapseSplit,
    );

    final safeInsets = MediaQuery.paddingOf(context);
    final stepperMargin = metrics.stepperMargin;
    final top = safeInsets.top + stepperMargin;
    final utilityWidth = (layoutConstraints.maxWidth * 0.42).clamp(
      248.0,
      560.0,
    );
    final availableWorkflowWidth =
        (layoutConstraints.maxWidth - utilityWidth - (stepperMargin * 3)).clamp(
          0.0,
          layoutConstraints.maxWidth * 0.48,
        );
    final stepperBottom = top + metrics.stepperHeight + stepperMargin;
    final belowStepperHeaderTop = top + metrics.stepperHeight;
    final Widget? belowStepperHeaderChild = switch (activeStep) {
      'selectData' => SetupHeaderActions(
        onLoadFromHub: () => setupStepKey.currentState?.openWorkspaceFromHub(),
        onLoadFromDisk: () =>
            setupStepKey.currentState?.loadWorkspaceFromDevice(),
        onLoadFromServer: () =>
            setupStepKey.currentState?.openWorkspaceFromServer(),
      ),
      'deployReview' => const DeployReviewHeader(),
      _ => null,
    };

    return StudioOverlayMetrics(
      stepperBottom: stepperBottom,
      readableContentBottom: metrics.contentTopPad,
      belowStepperHeaderTop: belowStepperHeaderTop,
      child: Stack(
        children: [
          Positioned.fill(child: stageArea),
          Positioned(
            top: top,
            left: safeInsets.left + stepperMargin,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: availableWorkflowWidth),
              child: workflowAccordion,
            ),
          ),
          Positioned(
            top: top,
            right: safeInsets.right + stepperMargin,
            width: utilityWidth,
            child: Align(alignment: Alignment.topRight, child: utilityPill),
          ),
          if (metrics.showBelowStepperHeaderRow &&
              belowStepperHeaderChild != null)
            Positioned(
              top: belowStepperHeaderTop,
              left: safeInsets.left + stepperMargin + 20,
              right: safeInsets.right + stepperMargin,
              height: metrics.belowStepperRowHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: belowStepperHeaderChild,
              ),
            ),
        ],
      ),
    );
  }
}
