import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/motion_tokens.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart'
    show
        SnnWorkflowPhase,
        SnnWorkflowStage,
        kSnnPhasesByStage,
        kSnnStageLabels,
        kSnnStepLabels,
        snnStageForPhase;
import 'package:zeta_flutter/zeta_flutter.dart';

/// Mobile-optimized stage-first stepper for the SNN workflow.
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

  /// Override for the step-name labels, keyed by phase. Defaults to the
  /// same [kSnnStepLabels] map used by the desktop `SnnWorkflowStepper`, so
  /// both steppers cannot drift out of sync with each other.
  final Map<SnnWorkflowPhase, String> stepLabels;

  /// Override for the three main workflow stage labels.
  final Map<SnnWorkflowStage, String> stageLabels;

  /// Optional trailing widget to display at the right end of the stepper.
  final Widget? trailing;

  const SnnMobileWorkflowStepper({
    super.key,
    required this.currentPhase,
    this.runningPhase,
    this.onPhaseSelected,
    this.lockedPhases = const <SnnWorkflowPhase>{},
    this.stepLabels = kSnnStepLabels,
    this.stageLabels = kSnnStageLabels,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final currentStage = snnStageForPhase(currentPhase);

    return Row(
      children: [
        // Current step title — left-aligned, bold.
        Expanded(
          child: AnimatedSwitcher(
            duration: NmtkMotionTokens.durationBase,
            switchInCurve: NmtkMotionTokens.easeEnter,
            switchOutCurve: NmtkMotionTokens.easeExit,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              '${stageLabels[currentStage] ?? currentStage.name} · '
              '${stepLabels[currentPhase] ?? currentPhase.name}',
              key: ValueKey(currentPhase),
              // P1-6 fix: Zeta text styles instead of Theme.of(context).textTheme
              style: Zeta.of(context).textStyles.titleSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.mainDefault,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Three stage destinations keep the hierarchy legible at narrow widths.
        AnimatedSwitcher(
          duration: NmtkMotionTokens.durationBase,
          switchInCurve: NmtkMotionTokens.easeEnter,
          switchOutCurve: NmtkMotionTokens.easeExit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(currentPhase),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stage in SnnWorkflowStage.values)
                _buildChip(context, stage, currentStage, colors),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }

  Widget _buildChip(
    BuildContext context,
    SnnWorkflowStage stage,
    SnnWorkflowStage currentStage,
    ZetaColors colors,
  ) {
    final stepNumber = stage.index + 1;
    final isCurrent = stage == currentStage;
    final isCompleted = stage.index < currentStage.index;
    final unlocked = kSnnPhasesByStage[stage]!
        .where((phase) => !lockedPhases.contains(phase))
        .toList(growable: false);
    final isLocked = unlocked.isEmpty;

    final Color chipColor;
    final Color bgColor;
    final VoidCallback? onTap;

    if (isCurrent) {
      // P1-7 fix: Zeta surfacePrimary token for text on a primary-coloured chip
      chipColor = Zeta.of(context).colors.surfacePrimary;
      bgColor = colors.mainPrimary;
      onTap = null;
    } else if (isLocked) {
      chipColor = colors.mainDefault;
      bgColor = Colors.transparent;
      onTap = null;
    } else if (isCompleted) {
      chipColor = colors.mainPrimary;
      bgColor = Colors.transparent;
      onTap = onPhaseSelected != null
          ? () => onPhaseSelected!(unlocked.last)
          : null;
    } else {
      chipColor = colors.mainSubtle;
      bgColor = Colors.transparent;
      onTap = onPhaseSelected != null
          ? () => onPhaseSelected!(unlocked.first)
          : null;
    }

    Widget chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Material(
          color: bgColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            // P0-4 fix: BorderRadius.circular(14) removed — CircleBorder on
            // Material already clips the InkWell splash to a circle shape.
            child: Center(
              child: Text(
                '$stepNumber',
                // P1-6 fix: Zeta text styles instead of Theme.of(context).textTheme
                style: Zeta.of(context).textStyles.bodySmall.copyWith(
                  color: chipColor,
                  fontWeight: FontWeight.w700,
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
