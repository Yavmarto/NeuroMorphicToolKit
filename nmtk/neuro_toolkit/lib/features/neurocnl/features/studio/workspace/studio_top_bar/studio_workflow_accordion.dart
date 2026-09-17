import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';

class StudioWorkflowAccordion extends ConsumerWidget {
  const StudioWorkflowAccordion({
    super.key,
    required this.activeStep,
    required this.onStepSelected,
    required this.onSplitLeft,
    required this.onSplitRight,
    required this.onCollapse,
    this.splitStep,
  });

  final String activeStep;
  final ValueChanged<SnnWorkflowPhase> onStepSelected;
  final ValueChanged<String> onSplitLeft;
  final ValueChanged<String> onSplitRight;
  final ValueChanged<String> onCollapse;
  final String? splitStep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainingState = ref.watch(trainingProvider);
    final currentPhase = SnnWorkflowPhase.values.firstWhere(
      (p) => p.name == activeStep,
      orElse: () => SnnWorkflowPhase.defineModel,
    );
    final secondaryPhase = splitStep != null
        ? SnnWorkflowPhase.values.firstWhere(
            (p) => p.name == splitStep,
            orElse: () => SnnWorkflowPhase.defineModel,
          )
        : null;
    final runningPhase = switch (trainingState.status) {
      TrainingProviderStatus.submitting ||
      TrainingProviderStatus.polling => SnnWorkflowPhase.run,
      _ => null,
    };

    final lockedPhaseNames = ref.watch(lockedPhasesProvider);
    final lockedPhases = SnnWorkflowPhase.values
        .where((p) => lockedPhaseNames.contains(p.name))
        .toSet();

    return KeyedSubtree(
      key: const Key('studio-workflow-accordion'),
      child: SnnWorkflowStepper(
        currentPhase: currentPhase,
        secondaryPhase: secondaryPhase,
        runningPhase: runningPhase,
        lockedPhases: lockedPhases,
        epochPulseTick: trainingState.epochTick,
        onPhaseSelected: onStepSelected,
        splitStep: splitStep,
        onSplitBetween: (leftId, rightId) {
          if (rightId == activeStep) {
            onSplitLeft(activeStep);
          } else {
            onSplitRight(activeStep);
          }
        },
        onCollapseStep: onCollapse,
      ),
    );
  }
}
