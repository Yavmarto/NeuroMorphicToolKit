import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';

enum SnnWorkflowPhase {
  selectData,
  defineModel,
  defineTrain,
  defineEval,
  trainingSandbox,
  run,
  deploy,
}

/// A specialized pipeline stepper for the NeuroMorphicToolKit SNN workflow.
///
/// Models the 7-step workflow for training and deploying an SNN:
/// 1. Setup        (selectData)
/// 2. Model        (defineModel)
/// 3. Training     (defineTrain)
/// 4. Eval         (defineEval)
/// 5. Notebook     (trainingSandbox / Jupyter/Python)
/// 6. Run          (run / GPU)
/// 7. Deploy       (deploy)
///
/// When [onOpenSandbox] is provided, tapping step 5 opens the training notebook
/// (e.g. via url_launcher in the consumer) in addition to navigating to that phase.
/// A "↗" affordance is appended to the step label to signal the action.
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

  /// Optional callback invoked when the user taps the Training Sandbox step.
  /// Intended for the consumer to launch Jupyter Lab (e.g. via url_launcher).
  final VoidCallback? onOpenSandbox;

  /// When set, this phase is also highlighted in the stepper (dual-pane view).
  final SnnWorkflowPhase? secondaryPhase;

  /// When true, renders only the inner scrollable row with no container border.
  /// Pass to embed inside a parent toolbar (mirrors [NmtkPipelineStepper.bare]).
  final bool bare;

  /// The set of phases that are locked (not yet accessible to the user).
  /// Locked phases are rendered with reduced opacity, no tap handler, and a
  /// tooltip explaining that the previous step must be completed first.
  final Set<SnnWorkflowPhase> lockedPhases;

  const SnnWorkflowStepper({
    super.key,
    required this.currentPhase,
    this.epochPulseTick = 0,
    this.runningPhase,
    this.onPhaseSelected,
    this.onOpenSandbox,
    this.secondaryPhase,
    this.bare = false,
    this.lockedPhases = const <SnnWorkflowPhase>{},
  });

  @override
  Widget build(BuildContext context) {
    return NmtkPipelineStepper(
      bare: bare,
      selectedStepId: currentPhase.name,
      secondarySelectedStepId: secondaryPhase?.name,
      disabledStepIds: lockedPhases.map((p) => p.name).toSet(),
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
          '1. Setup',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (dataset / tabular data)
          Icons.dataset_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.defineModel,
          '2. Model',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (architecture diagram)
          Icons.architecture_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.defineTrain,
          '3. Training',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (ML model training)
          Icons.model_training_outlined,
        ),
        _buildStepData(
          SnnWorkflowPhase.defineEval,
          '4. Eval',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (fact check / evaluation)
          Icons.fact_check_outlined,
        ),
        _buildSandboxStepData(),
        _buildStepData(
          SnnWorkflowPhase.run,
          '6. Run',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (play circle / run job)
          Icons.play_circle_outline,
          pulseTick: epochPulseTick,
        ),
        _buildStepData(
          SnnWorkflowPhase.deploy,
          '7. Deploy',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (rocket launch / deploy)
          Icons.rocket_launch_outlined,
        ),
      ],
    );
  }

  NmtkPipelineStepData _buildSandboxStepData() {
    const label = '5. Notebook';
    final status = _getStatusForPhase(SnnWorkflowPhase.trainingSandbox);
    VoidCallback? onTap;
    if (onPhaseSelected != null) {
      onTap = () => onPhaseSelected!(SnnWorkflowPhase.trainingSandbox);
    }
    return NmtkPipelineStepData(
      id: SnnWorkflowPhase.trainingSandbox.name,
      label: label,
      status: status,
      // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (flask / experiment sandbox)
      icon: Icons.science_outlined,
      onTap: onTap,
    );
  }

  NmtkPipelineStepData _buildStepData(
    SnnWorkflowPhase phase,
    String label,
    IconData icon, {
    int pulseTick = 0,
  }) {
    final status = _getStatusForPhase(phase);
    return NmtkPipelineStepData(
      id: phase.name,
      label: label,
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
