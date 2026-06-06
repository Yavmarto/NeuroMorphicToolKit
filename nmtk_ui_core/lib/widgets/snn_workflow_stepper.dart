import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';

enum SnnWorkflowPhase {
  selectData,
  defineArchitecture,
  trainingSandbox,
  trainAndExport,
  deploy,
}

/// A specialized pipeline stepper for the NeuroMorphicToolKit SNN workflow.
///
/// Models the 5-step workflow for training and deploying an SNN:
/// 1. Select Data
/// 2. Define Architecture (CNL/NIR)
/// 3. Training Sandbox (Jupyter/Python)
/// 4. Train & Export (GPU)
/// 5. Deploy
///
/// When [onOpenSandbox] is provided, tapping step 3 opens the training notebook
/// (e.g. via url_launcher in the consumer) in addition to navigating to that phase.
/// A "↗" affordance is appended to the step label to signal the action.
class SnnWorkflowStepper extends StatelessWidget {
  /// The currently active workflow phase.
  final SnnWorkflowPhase currentPhase;

  /// Monotonically increasing tick to pulse the "Train & Export" step.
  ///
  /// Only fires an animation when [runningPhase] is [SnnWorkflowPhase.trainAndExport].
  final int epochPulseTick;

  /// The phase that is ACTIVELY executing (shows spinner + pulse).
  /// Null = no step is running right now.
  ///
  /// Distinct from [currentPhase] (the selected/viewed panel). Use
  /// [SnnWorkflowPhase.trainAndExport] while a training job is in progress.
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

  const SnnWorkflowStepper({
    super.key,
    required this.currentPhase,
    this.epochPulseTick = 0,
    this.runningPhase,
    this.onPhaseSelected,
    this.onOpenSandbox,
    this.secondaryPhase,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    return NmtkPipelineStepper(
      bare: bare,
      selectedStepId: currentPhase.name,
      secondarySelectedStepId: secondaryPhase?.name,
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
          SnnWorkflowPhase.defineArchitecture,
          '2. Architecture',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (architecture diagram)
          Icons.architecture_outlined,
        ),
        _buildSandboxStepData(),
        _buildStepData(
          SnnWorkflowPhase.trainAndExport,
          '4. Train & Export',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (ML model training)
          Icons.model_training_outlined,
          pulseTick: epochPulseTick,
        ),
        _buildStepData(
          SnnWorkflowPhase.deploy,
          '5. Deploy',
          // ZETA-MIGRATION-EXEMPT: no Zeta equivalent (rocket launch / deploy)
          Icons.rocket_launch_outlined,
        ),
      ],
    );
  }

  NmtkPipelineStepData _buildSandboxStepData() {
    const label = '3. Notebook';
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
