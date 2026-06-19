import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/motion_tokens.dart';
import 'package:nmtk_ui_core/widgets/snn_workflow_stepper.dart'
    show SnnWorkflowPhase;

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
          child: AnimatedSwitcher(
            duration: NmtkMotionTokens.durationBase,
            switchInCurve: NmtkMotionTokens.easeEnter,
            switchOutCurve: NmtkMotionTokens.easeExit,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              _stepLabels[currentPhase] ?? currentPhase.name,
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
        // Number chips for every phase except the current one.
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
              for (final phase in allPhases) _buildChip(context, phase, colors),
            ],
          ),
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
    final isCurrent = phase == currentPhase;
    final isCompleted = phase.index < currentPhase.index;
    final isLocked = lockedPhases.contains(phase);

    final Color chipColor;
    final Color bgColor;
    final VoidCallback? onTap;

    if (isCurrent) {
      // P1-7 fix: use colorScheme.onPrimary instead of hardcoded Colors.white
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
      onTap = onPhaseSelected != null ? () => onPhaseSelected!(phase) : null;
    } else {
      chipColor = colors.mainSubtle;
      bgColor = Colors.transparent;
      onTap = onPhaseSelected != null ? () => onPhaseSelected!(phase) : null;
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
