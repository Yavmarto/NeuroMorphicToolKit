import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';
import 'package:nmtk_ui_core/zeta_theme.dart';

enum SnnWorkflowStage { setup, design, execute }

enum SnnWorkflowPhase { selectData, defineModel, defineTrain, defineEval, run, deployHardware, deployReview }

const Map<SnnWorkflowStage, String> kSnnStageLabels = {
  SnnWorkflowStage.setup: 'Setup',
  SnnWorkflowStage.design: 'Design',
  SnnWorkflowStage.execute: 'Execute',
};

const Map<SnnWorkflowStage, List<SnnWorkflowPhase>> kSnnPhasesByStage = {
  SnnWorkflowStage.setup: [SnnWorkflowPhase.selectData],
  SnnWorkflowStage.design: [SnnWorkflowPhase.defineModel, SnnWorkflowPhase.defineTrain, SnnWorkflowPhase.defineEval],
  SnnWorkflowStage.execute: [
    SnnWorkflowPhase.run,
    SnnWorkflowPhase.deployHardware,
    SnnWorkflowPhase.deployReview,
  ],
};

SnnWorkflowStage snnStageForPhase(SnnWorkflowPhase phase) => switch (phase) {
  SnnWorkflowPhase.selectData => SnnWorkflowStage.setup,
  SnnWorkflowPhase.defineModel ||
  SnnWorkflowPhase.defineTrain ||
  SnnWorkflowPhase.defineEval => SnnWorkflowStage.design,
  SnnWorkflowPhase.run ||
  SnnWorkflowPhase.deployHardware ||
  SnnWorkflowPhase.deployReview => SnnWorkflowStage.execute,
};

const double _kStageGap = 8;
const double _kPhasePillWidth = 110;

/// Horizontal inset shared by the stage row and the phase rail so both rows
/// start on the same x.
const double _kRowInset = 12;

/// Fixed width of a connector slot in [NmtkPipelineStepper] (arrow or +/−).
const double _kConnectorSlotWidth = 30;

/// Width reserved for the phase rail: the widest stage's rail. Reserving it for
/// every stage keeps the panel from resizing — and the single-phase Setup rail
/// from drifting to the centre — when the active stage changes.
final double _kPhaseRailWidth = (() {
  final maxPhases = kSnnPhasesByStage.values.map((phases) => phases.length).reduce((a, b) => a > b ? a : b);
  return maxPhases * _kPhasePillWidth + (maxPhases - 1) * _kConnectorSlotWidth;
})();

/// Base step-name labels shared by the desktop, compact, and drawer steppers.
const Map<SnnWorkflowPhase, String> kSnnStepLabels = {
  SnnWorkflowPhase.selectData: 'Prepare',
  SnnWorkflowPhase.defineModel: 'Model',
  SnnWorkflowPhase.defineTrain: 'Training',
  SnnWorkflowPhase.defineEval: 'Evaluation',
  SnnWorkflowPhase.run: 'Run',
  SnnWorkflowPhase.deployHardware: 'Deploy',
  SnnWorkflowPhase.deployReview: 'Review',
};

/// A floating Studio workflow header.
///
/// The three stages sit in a single row up top; the active stage's local
/// phases render in a shared row beneath it, keeping navigation available
/// without occupying a full canvas edge.
class SnnWorkflowStepper extends StatefulWidget {
  final SnnWorkflowPhase currentPhase;
  final int epochPulseTick;
  final SnnWorkflowPhase? runningPhase;
  final ValueChanged<SnnWorkflowPhase>? onPhaseSelected;
  final SnnWorkflowPhase? secondaryPhase;
  final bool bare;
  final Set<SnnWorkflowPhase> lockedPhases;
  final String disabledTooltip;
  final String? splitStep;
  final void Function(String leftId, String rightId)? onSplitBetween;
  final void Function(String keepId)? onCollapseStep;
  final Map<SnnWorkflowPhase, String> stepLabels;
  final Map<SnnWorkflowStage, String> stageLabels;

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
    this.stageLabels = kSnnStageLabels,
  });

  @override
  State<SnnWorkflowStepper> createState() => _SnnWorkflowStepperState();
}

class _SnnWorkflowStepperState extends State<SnnWorkflowStepper> {
  late final Map<SnnWorkflowStage, SnnWorkflowPhase> _lastVisitedByStage;

  @override
  void initState() {
    super.initState();
    _lastVisitedByStage = <SnnWorkflowStage, SnnWorkflowPhase>{};
    _seedVisitedStages(widget.currentPhase);
  }

  @override
  void didUpdateWidget(covariant SnnWorkflowStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPhase != widget.currentPhase) {
      _lastVisitedByStage[snnStageForPhase(widget.currentPhase)] = widget.currentPhase;
    }
  }

  void _seedVisitedStages(SnnWorkflowPhase current) {
    final currentStage = snnStageForPhase(current);
    for (final stage in SnnWorkflowStage.values) {
      if (stage.index < currentStage.index) {
        _lastVisitedByStage[stage] = kSnnPhasesByStage[stage]!.last;
      }
    }
    _lastVisitedByStage[currentStage] = current;
  }

  @override
  Widget build(BuildContext context) {
    final activeStage = snnStageForPhase(widget.currentPhase);
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kRowInset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final stage in SnnWorkflowStage.values) ...[
                if (stage != SnnWorkflowStage.values.first) const SizedBox(width: _kStageGap),
                SizedBox(
                  width: _kPhasePillWidth,
                  child: _StageDestination(
                    number: stage.index + 1,
                    label: widget.stageLabels[stage] ?? stage.name,
                    selected: stage == activeStage,
                    completed: _stageIsCompleted(stage),
                    running: _stageIsRunning(stage),
                    disabled: _stageIsLocked(stage),
                    disabledTooltip: widget.disabledTooltip,
                    onTap: () => _selectStage(stage),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: _kPhaseRailWidth + _kRowInset * 2,
          child: _SubstepRailSwitcher(
            stage: activeStage,
            perPhaseDuration: tokens.standardMotion,
            reducedMotion: reducedMotion,
            railBuilder: _buildChildRail,
          ),
        ),
      ],
    );

    if (widget.bare) {
      return Semantics(label: 'Workflow stages', child: inner);
    }
    return Container(
      key: const ValueKey<String>('snn-workflow-panel'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: tokens.subtleBorder),
      ),
      child: Semantics(label: 'Workflow stages', child: inner),
    );
  }

  Widget _buildChildRail(BuildContext context, SnnWorkflowStage stage) {
    final stagePhases = kSnnPhasesByStage[stage]!;
    final secondary = widget.secondaryPhase;
    final localSecondary = secondary != null && snnStageForPhase(secondary) == stage ? secondary : null;
    final localSplitStep = localSecondary == null ? null : widget.splitStep;
    final colors = Zeta.of(context).colors;

    return NmtkPipelineStepper(
      key: ValueKey<SnnWorkflowStage>(stage),
      bare: true,
      shrinkWrap: true,
      wrapOnCompact: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: _kRowInset),
      stepAccentColor: colors.mainPrimary,
      stepStyle: NmtkPipelineStepStyle.destination,
      stepWidth: _kPhasePillWidth,
      statusBarSemanticsLabel: '${widget.stageLabels[stage] ?? stage.name} steps',
      selectedStepId: widget.currentPhase.name,
      secondarySelectedStepId: localSecondary?.name,
      disabledStepIds: widget.lockedPhases.map((p) => p.name).toSet(),
      disabledTooltip: widget.disabledTooltip,
      splitStepId: localSplitStep,
      onSplitBetween: widget.onSplitBetween == null
          ? null
          : (leftId, rightId) {
              final left = SnnWorkflowPhase.values.firstWhere((phase) => phase.name == leftId);
              final right = SnnWorkflowPhase.values.firstWhere((phase) => phase.name == rightId);
              if (snnStageForPhase(left) == snnStageForPhase(right)) {
                widget.onSplitBetween!(leftId, rightId);
              }
            },
      onCollapseStep: widget.onCollapseStep,
      onSelected: widget.onPhaseSelected == null
          ? null
          : (id) => widget.onPhaseSelected!(SnnWorkflowPhase.values.firstWhere((p) => p.name == id)),
      steps: [for (final phase in stagePhases) _buildStepData(phase)],
    );
  }

  bool _stageIsLocked(SnnWorkflowStage stage) => kSnnPhasesByStage[stage]!.every(widget.lockedPhases.contains);

  bool _stageIsCompleted(SnnWorkflowStage stage) => kSnnPhasesByStage[stage]!.last.index < widget.currentPhase.index;

  bool _stageIsRunning(SnnWorkflowStage stage) =>
      widget.runningPhase != null && snnStageForPhase(widget.runningPhase!) == stage;

  void _selectStage(SnnWorkflowStage stage) {
    if (widget.onPhaseSelected == null || _stageIsLocked(stage)) return;
    final unlocked = kSnnPhasesByStage[stage]!
        .where((phase) => !widget.lockedPhases.contains(phase))
        .toList(growable: false);
    if (unlocked.isEmpty) return;
    final remembered = _lastVisitedByStage[stage];
    widget.onPhaseSelected!(remembered != null && unlocked.contains(remembered) ? remembered : unlocked.first);
  }

  NmtkPipelineStepData _buildStepData(SnnWorkflowPhase phase) {
    return NmtkPipelineStepData(
      id: phase.name,
      label: widget.stepLabels[phase] ?? phase.name,
      status: _getStatusForPhase(phase),
      pulseTick: phase == SnnWorkflowPhase.run ? widget.epochPulseTick : 0,
    );
  }

  NmtkStepStatus _getStatusForPhase(SnnWorkflowPhase phase) {
    if (phase == widget.runningPhase) return NmtkStepStatus.running;
    if (widget.lockedPhases.contains(phase)) return NmtkStepStatus.idle;
    if (phase.index < widget.currentPhase.index) {
      return NmtkStepStatus.success;
    }
    return NmtkStepStatus.idle;
  }
}

class _StageDestination extends StatelessWidget {
  const _StageDestination({
    required this.number,
    required this.label,
    required this.selected,
    required this.completed,
    required this.running,
    required this.disabled,
    required this.disabledTooltip,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool selected;
  final bool completed;
  final bool running;
  final bool disabled;
  final String disabledTooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final tokens = NmtkShellTokens.of(context);
    final foreground = running
        ? tokens.runningColor
        : selected
        ? colors.mainPrimary
        : completed
        ? tokens.healthyColor
        : colors.mainSubtle;
    final status = disabled
        ? 'Locked'
        : running
        ? 'Running'
        : completed
        ? 'Completed'
        : selected
        ? 'Current'
        : 'Available';
    final destination = Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: 'Stage $number, $label',
      value: status,
      excludeSemantics: true,
      child: Material(
        key: ValueKey<String>('workflow-stage-$number'),
        color: selected ? colors.surfacePrimarySubtle : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          side: BorderSide(color: selected ? colors.borderPrimary : Colors.transparent),
        ),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Zeta.of(context).textStyles.bodySmall.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!disabled) return destination;
    return Tooltip(
      message: disabledTooltip,
      child: Opacity(opacity: 0.38, child: destination),
    );
  }
}

/// Shows the active stage's phase rail in a single slot below the stage row.
///
/// On a stage switch, the outgoing rail slides/fades upward as if pulled into
/// the stage row above, then the incoming rail slides/fades down out of it —
/// a sequential two-phase transition, not a crossfade.
class _SubstepRailSwitcher extends StatefulWidget {
  const _SubstepRailSwitcher({
    required this.stage,
    required this.perPhaseDuration,
    required this.reducedMotion,
    required this.railBuilder,
  });

  final SnnWorkflowStage stage;
  final Duration perPhaseDuration;
  final bool reducedMotion;
  final Widget Function(BuildContext, SnnWorkflowStage) railBuilder;

  @override
  State<_SubstepRailSwitcher> createState() => _SubstepRailSwitcherState();
}

class _SubstepRailSwitcherState extends State<_SubstepRailSwitcher> with SingleTickerProviderStateMixin {
  static const double _travel = 36;

  late AnimationController _controller;
  late CurvedAnimation _outCurve;
  late CurvedAnimation _inCurve;
  SnnWorkflowStage? _outgoingStage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.perPhaseDuration * 2, value: 1);
    _buildCurves();
  }

  void _buildCurves() {
    _outCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _inCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant _SubstepRailSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.perPhaseDuration != widget.perPhaseDuration) {
      _controller.duration = widget.perPhaseDuration * 2;
    }
    if (widget.reducedMotion) {
      _controller.value = 1;
      _outgoingStage = null;
      return;
    }
    if (oldWidget.stage != widget.stage) {
      _outgoingStage = oldWidget.stage;
      _controller.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && _controller.isCompleted) {
          setState(() => _outgoingStage = null);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedMotion || _outgoingStage == null) {
      return ClipRect(child: widget.railBuilder(context, widget.stage));
    }

    final outgoing = widget.railBuilder(context, _outgoingStage!);
    final incoming = widget.railBuilder(context, widget.stage);

    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _outCurve,
            builder: (context, child) => IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 1 - _outCurve.value,
                  child: Transform.translate(offset: Offset(0, -_outCurve.value * _travel), child: child),
                ),
              ),
            ),
            child: outgoing,
          ),
          AnimatedBuilder(
            animation: _inCurve,
            builder: (context, child) {
              final settled = _inCurve.value >= 1;
              return IgnorePointer(
                ignoring: !settled,
                child: ExcludeSemantics(
                  excluding: !settled,
                  child: Opacity(
                    opacity: _inCurve.value,
                    child: Transform.translate(offset: Offset(0, -(1 - _inCurve.value) * _travel), child: child),
                  ),
                ),
              );
            },
            child: incoming,
          ),
        ],
      ),
    );
  }
}
