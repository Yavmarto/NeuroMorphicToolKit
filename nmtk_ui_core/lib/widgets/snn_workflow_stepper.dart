import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

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

/// Mobile-optimized workflow stepper for the SNN 7-step pipeline.
///
/// Shows the current step name as a bold title on the left, with the other
/// 6 steps as compact tappable number chips on the right.
///
/// Step chip visual states:
/// - Current step: shown only as the title text (no chip).
/// - Completed steps (index < current): [mainPrimary] color, tappable.
/// - Locked steps: dim (opacity 0.3), no tap handler.
/// - Unlocked future steps: [mainSubtle] color, tappable.
class SnnMobileWorkflowStepper extends StatelessWidget {
  /// The currently active workflow phase.
  final SnnWorkflowPhase currentPhase;

  /// The phase that is ACTIVELY executing (shows pulse on desktop stepper).
  /// Carried through for API symmetry; not used in the compact mobile chip.
  final SnnWorkflowPhase? runningPhase;

  /// Optional callback when a step chip is tapped.
  final ValueChanged<SnnWorkflowPhase>? onPhaseSelected;

  /// The set of phases that are locked (not yet accessible to the user).
  final Set<SnnWorkflowPhase> lockedPhases;

  static const _stepLabels = {
    SnnWorkflowPhase.selectData: 'Setup',
    SnnWorkflowPhase.defineModel: 'Model',
    SnnWorkflowPhase.defineTrain: 'Training',
    SnnWorkflowPhase.defineEval: 'Eval',
    SnnWorkflowPhase.trainingSandbox: 'Notebook',
    SnnWorkflowPhase.run: 'Run',
    SnnWorkflowPhase.deploy: 'Deploy',
  };

  const SnnMobileWorkflowStepper({
    super.key,
    required this.currentPhase,
    this.runningPhase,
    this.onPhaseSelected,
    this.lockedPhases = const <SnnWorkflowPhase>{},
  });

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final allPhases = SnnWorkflowPhase.values;

    return Row(
      children: [
        // Current step title — left-aligned, bold.
        Expanded(
          child: Text(
            _stepLabels[currentPhase] ?? currentPhase.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.mainDefault,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        // Number chips for every phase except the current one.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final phase in allPhases)
              if (phase != currentPhase) _buildChip(context, phase, colors),
          ],
        ),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context,
    SnnWorkflowPhase phase,
    ZetaColors colors,
  ) {
    final stepNumber = phase.index + 1;
    final isCompleted = phase.index < currentPhase.index;
    final isLocked = lockedPhases.contains(phase);

    final Color chipColor;
    final VoidCallback? onTap;

    if (isLocked) {
      chipColor = colors.mainDefault;
      onTap = null;
    } else if (isCompleted) {
      chipColor = colors.mainPrimary;
      onTap = onPhaseSelected != null ? () => onPhaseSelected!(phase) : null;
    } else {
      chipColor = colors.mainSubtle;
      onTap = onPhaseSelected != null ? () => onPhaseSelected!(phase) : null;
    }

    Widget chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(
                '$stepNumber',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: chipColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
    );

    if (isLocked) {
      chip = Opacity(opacity: 0.3, child: chip);
    }

    return chip;
  }
}
