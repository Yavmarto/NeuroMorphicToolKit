import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';

enum SnnWorkflowPhase {
  selectData,
  defineModel,
  defineTrain,
  defineEval,
  run,
  deploy,
}

/// Base step-name labels, shared between [SnnWorkflowStepper] (which
/// prefixes each with its 1-based step number) and `SnnMobileWorkflowStepper`
/// (which uses these bare). Single source of truth so the two steppers
/// cannot drift out of sync with each other.
const Map<SnnWorkflowPhase, String> kSnnStepLabels = {
  SnnWorkflowPhase.selectData: 'Setup',
  SnnWorkflowPhase.defineModel: 'Model',
  SnnWorkflowPhase.defineTrain: 'Training',
  SnnWorkflowPhase.defineEval: 'Eval',
  SnnWorkflowPhase.run: 'Run',
  SnnWorkflowPhase.deploy: 'Results',
};

/// A specialized pipeline stepper for the NeuroMorphicToolKit SNN workflow.
///
/// Models the 6-step workflow for training and deploying an SNN:
/// 1. Setup        (selectData)
/// 2. Model        (defineModel)
/// 3. Training     (defineTrain)
/// 4. Eval         (defineEval)
/// 5. Run          (run / GPU — also hosts the training notebook, opened
///                  on demand from the consumer's Run screen)
/// 6. Results      (deploy)
class SnnWorkflowStepper extends StatelessWidget {
  /// The currently active workflow phase.
  final SnnWorkflowPhase currentPhase;

  /// Monotonically increasing tick to pulse the "Run" step.
  ///
  /// Only fires an animation when [runningPhase] is [SnnWorkflowPhase.run].
  final int epochPulseTick;

  /// The phase that is ACTIVELY executing (shows spinner + pulse).
  /// Null = no step is running right now.
  ///
  /// Distinct from [currentPhase] (the selected/viewed panel). Use
  /// [SnnWorkflowPhase.run] while a training job is in progress.
  final SnnWorkflowPhase? runningPhase;

  /// Optional callback when a step is tapped.
  final ValueChanged<SnnWorkflowPhase>? onPhaseSelected;

  /// When set, this phase is also highlighted in the stepper (dual-pane view).
  final SnnWorkflowPhase? secondaryPhase;

  /// When true, renders only the inner scrollable row with no container border.
  /// Pass to embed inside a parent toolbar (mirrors [NmtkPipelineStepper.bare]).
  final bool bare;

  /// The set of phases that are locked (not yet accessible to the user).
  /// Locked phases are rendered with reduced opacity, no tap handler, and a
  /// tooltip explaining that the previous step must be completed first.
  final Set<SnnWorkflowPhase> lockedPhases;

  /// Custom tooltip shown when the user hovers over a locked phase.
  ///
  /// Defaults to `'Complete the previous step first'`. Override this to
  /// surface domain-appropriate messaging (e.g. "Upload a dataset first").
  final String disabledTooltip;

  /// The phase id of the second panel in split-pane mode. Null = single pane.
  final String? splitStep;

  /// Called when the user taps a + connector to open a split view.
  final void Function(String leftId, String rightId)? onSplitBetween;

  /// Called when the user taps a − connector to collapse a pane.
  /// [keepId] is the step that should remain as sole active.
  final void Function(String keepId)? onCollapseStep;

  /// Override for the step-name labels, keyed by phase. Defaults to
  /// [kSnnStepLabels]; each is prefixed with its 1-based step number.
  final Map<SnnWorkflowPhase, String> stepLabels;

  const SnnWorkflowStepper({
    super.key,
    required this.currentPhase,
    this.epochPulseTick = 0,
    this.runningPhase,
    this.onPhaseSelected,
    this.secondaryPhase,
    this.bare = false,
    this.lockedPhases = const <SnnWorkflowPhase>{},
    this.disabledTooltip = 'Complete the previous step first',
    this.splitStep,
    this.onSplitBetween,
    this.onCollapseStep,
    this.stepLabels = kSnnStepLabels,
  });

  @override
  Widget build(BuildContext context) {
    return NmtkPipelineStepper(
      bare: bare,
      selectedStepId: currentPhase.name,
      secondarySelectedStepId: secondaryPhase?.name,
      disabledStepIds: lockedPhases.map((p) => p.name).toSet(),
      disabledTooltip: disabledTooltip,
      splitStepId: splitStep,
      onSplitBetween: onSplitBetween,
      onCollapseStep: onCollapseStep,
      onSelected: onPhaseSelected != null
          ? (id) {
              final phase = SnnWorkflowPhase.values.firstWhere(
                (p) => p.name == id,
              );
              onPhaseSelected!(phase);
            }
          : null,
      steps: [
        _buildStepData(
          SnnWorkflowPhase.selectData,
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (dataset / tabular data)
          Icons.dataset_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.defineModel,
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (architecture diagram)
          Icons.architecture_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.defineTrain,
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (ML model training)
          Icons.model_training_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.defineEval,
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (fact check / evaluation)
          Icons.fact_check_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.run,
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (play circle / run job)
          Icons.play_circle_outline,
          pulseTick: epochPulseTick,
        ),
        _buildStepData(
          SnnWorkflowPhase.deploy,
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (results analysis)
          Icons.analytics_outlined,
        ),
      ],
    );
  }

  String _numberedLabel(SnnWorkflowPhase phase) =>
      '${phase.index + 1}. ${stepLabels[phase] ?? phase.name}';

  NmtkPipelineStepData _buildStepData(
    SnnWorkflowPhase phase,
    IconData icon, {
    int pulseTick = 0,
  }) {
    final status = _getStatusForPhase(phase);
    return NmtkPipelineStepData(
      id: phase.name,
      label: _numberedLabel(phase),
      status: status,
      icon: icon,
      pulseTick: pulseTick,
    );
  }

  NmtkStepStatus _getStatusForPhase(SnnWorkflowPhase phase) {
    if (phase == runningPhase) return NmtkStepStatus.running;
    if (phase.index < currentPhase.index) {
      return NmtkStepStatus.success;
    } else {
      return NmtkStepStatus.idle;
    }
  }
}
