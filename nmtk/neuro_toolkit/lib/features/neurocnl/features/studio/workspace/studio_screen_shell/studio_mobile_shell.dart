import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_assistant_host.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/pipeline_stage_area/pipeline_stage_area.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/workspace_tab_view_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_screen_shell/studio_layout_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/studio_step_drawer/studio_step_drawer.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/studio_overlay_metrics.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class StudioMobileShell extends ConsumerWidget {
  const StudioMobileShell({
    super.key,
    required this.activeStep,
    required this.unlockedSteps,
    required this.workspaceTabs,
    required this.splitPipelineStep,
    required this.metrics,
    required this.stepBuilder,
    required this.onPhaseSelected,
    required this.onCollapseSplit,
    required this.onSaveWorkspace,
    required this.onShareToNeurohub,
    this.onEditServer,
  });

  final String activeStep;
  final Set<String> unlockedSteps;
  final WorkspaceTabViewData workspaceTabs;
  final String? splitPipelineStep;
  final StudioLayoutMetrics metrics;
  final Widget Function(int index) stepBuilder;
  final ValueChanged<SnnWorkflowPhase> onPhaseSelected;
  final ValueChanged<String> onCollapseSplit;
  final Future<void> Function() onSaveWorkspace;
  final Future<void> Function() onShareToNeurohub;
  final Future<void> Function()? onEditServer;

  static const _kCanvasSteps = {
    'defineModel',
    'defineTrain',
    'defineEval',
    'run',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPhase = SnnWorkflowPhase.values.firstWhere(
      (p) => p.name == activeStep,
      orElse: () => SnnWorkflowPhase.defineModel,
    );
    final lockedPhaseNames = ref.watch(lockedPhasesProvider);
    final lockedPhases = SnnWorkflowPhase.values
        .where((p) => lockedPhaseNames.contains(p.name))
        .toSet();

    void handleStepNameSelected(String name) {
      final phase = SnnWorkflowPhase.values.firstWhere(
        (candidate) => candidate.name == name,
      );
      onPhaseSelected(phase);
    }

    final mobileStageArea = PipelineStageArea(
      activeStep: activeStep,
      splitStep: splitPipelineStep,
      stepCount: kStudioPipelineStepNames.length,
      stepBuilder: stepBuilder,
      frameBuilder: ({required Widget child}) => child,
      canvasStepNames: _kCanvasSteps,
      unlockedStepNames: unlockedSteps,
      topInset: metrics.topInset,
      contentTopPad: metrics.contentTopPad,
      onStepChanged: handleStepNameSelected,
      onCollapse: onCollapseSplit,
    );

    final prevPhase = currentPhase.index > 0
        ? SnnWorkflowPhase.values[currentPhase.index - 1]
        : null;
    final nextPhase = currentPhase.index < kStudioPipelineStepNames.length - 1
        ? SnnWorkflowPhase.values[currentPhase.index + 1]
        : null;

    final shellProvidesChrome = NmtkShellChromeScope.of(context);
    final openAssistant = StudioAssistantScope.maybeOf(context);

    return StudioOverlayMetrics(
      stepperBottom: 0,
      child: Scaffold(
        appBar: AppBar(
          // ZETA-MIGRATION-EXEMPT: no Zeta app bar exists; this is the same
          // rationale nmtk_ui_core's own mobile scaffold uses.
          automaticallyImplyLeading: !shellProvidesChrome,
          title: Text(
            '${kSnnStageLabels[snnStageForPhase(currentPhase)]} · '
            '${kSnnStepLabels[currentPhase] ?? currentPhase.name}',
            style: Zeta.of(context).textStyles.titleLarge,
          ),
          actions: [
            Tooltip(
              message: 'Studio assistant',
              child: ZetaIconButton.text(
                icon: ZetaIcons.chat,
                semanticLabel: 'Studio assistant',
                onPressed: openAssistant,
              ),
            ),
            Tooltip(
              message: prevPhase != null ? 'Previous step' : 'No previous step',
              child: ZetaIconButton.text(
                icon: Icons.arrow_back,
                semanticLabel: 'Previous step',
                onPressed: prevPhase != null
                    ? () => onPhaseSelected(prevPhase)
                    : null,
              ),
            ),
            Tooltip(
              message: nextPhase != null ? 'Next step' : 'No next step',
              child: ZetaIconButton.text(
                icon: Icons.arrow_forward,
                semanticLabel: 'Next step',
                onPressed: nextPhase != null
                    ? () => onPhaseSelected(nextPhase)
                    : null,
              ),
            ),
            Tooltip(
              message: 'Save workspace',
              child: ZetaIconButton.text(
                icon: ZetaIcons.save,
                semanticLabel: 'Save workspace',
                onPressed: () => unawaited(onSaveWorkspace()),
              ),
            ),
            Tooltip(
              message: 'Save to Neurohub',
              child: ZetaIconButton.text(
                icon: ZetaIcons.cloud_upload,
                semanticLabel: 'Save to Neurohub',
                onPressed: () => unawaited(onShareToNeurohub()),
              ),
            ),
          ],
        ),
        drawer: shellProvidesChrome
            ? null
            : StudioStepDrawer(
                workspaceName: workspaceTabs.workspaceName,
                currentPhase: currentPhase,
                lockedPhases: lockedPhases,
                onPhaseSelected: onPhaseSelected,
                onEditServer: onEditServer,
              ),
        body: mobileStageArea,
      ),
    );
  }
}
