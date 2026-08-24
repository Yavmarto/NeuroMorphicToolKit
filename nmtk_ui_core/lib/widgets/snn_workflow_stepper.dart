import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/pipeline_stepper.dart';
import 'package:nmtk_ui_core/zeta_theme.dart';

enum SnnWorkflowStage { setup, design, execute }

enum SnnWorkflowPhase {
  selectData,
  defineModel,
  defineTrain,
  defineEval,
  run,
  deployHardware,
  deployReview,
}

const Map<SnnWorkflowStage, String> kSnnStageLabels = {
  SnnWorkflowStage.setup: 'Setup',
  SnnWorkflowStage.design: 'Design',
  SnnWorkflowStage.execute: 'Execute',
};

const Map<SnnWorkflowStage, List<SnnWorkflowPhase>> kSnnPhasesByStage = {
  SnnWorkflowStage.setup: [SnnWorkflowPhase.selectData],
  SnnWorkflowStage.design: [
    SnnWorkflowPhase.defineModel,
    SnnWorkflowPhase.defineTrain,
    SnnWorkflowPhase.defineEval,
  ],
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

/// Width of the stage pill's label segment (present whether or not it's the
/// active/expanded stage).
const double _kPhasePillWidth = 110;

/// Width of the inline sub-step destination pills nested inside the active
/// stage's pill. They stay smaller than the stage label they're nested under.
const double _kSubstepPillWidth = 96;

/// Horizontal inset around the whole stage row.
const double _kRowInset = 12;

/// Fixed width of a connector slot in [NmtkPipelineStepper] (arrow or +/−).
const double _kConnectorSlotWidth = 30;

/// Gap between a stage's label and its nested sub-step segment when expanded.
const double _kLabelToSubstepGap = 8;

/// Width reserved for the nested sub-step segment: the widest stage's set of
/// sub-steps. Reserving the same width for every stage — rather than sizing to
/// however many sub-steps the active stage actually has — keeps the panel from
/// resizing, and the single-substep Setup pill from drifting to the centre,
/// when the active stage changes.
final double _kPhaseRailWidth = (() {
  final maxPhases = kSnnPhasesByStage.values
      .map((phases) => phases.length)
      .reduce((a, b) => a > b ? a : b);
  return maxPhases * _kSubstepPillWidth +
      (maxPhases - 1) * _kConnectorSlotWidth;
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
/// The three stages sit in a single row. The active stage's local phases
/// nest inline inside its own pill; the other two stages stay collapsed to
/// just their label — keeping navigation available without occupying a
/// second row.
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
      _lastVisitedByStage[snnStageForPhase(widget.currentPhase)] =
          widget.currentPhase;
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

    // Only the active stage carries its sub-steps, nested inline inside its
    // own pill; the other two stages render as a plain label. Because exactly
    // one stage is always active and every stage reserves the same sub-step
    // width (see `_kPhaseRailWidth`), the row's total width never changes as
    // the active stage moves — `AnimatedSize` on each pill just makes that
    // handoff read as a smooth grow/shrink instead of a jump cut.
    final stageRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kRowInset),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final stage in SnnWorkflowStage.values) ...[
            if (stage != SnnWorkflowStage.values.first)
              const SizedBox(width: _kStageGap),
            _StageCell(
              number: stage.index + 1,
              label: widget.stageLabels[stage] ?? stage.name,
              selected: stage == activeStage,
              completed: _stageIsCompleted(stage),
              running: _stageIsRunning(stage),
              disabled: _stageIsLocked(stage),
              disabledTooltip: widget.disabledTooltip,
              onTap: () => _selectStage(stage),
              substeps: stage == activeStage
                  ? _buildChildRail(context, stage)
                  : null,
              duration: tokens.standardMotion,
              reducedMotion: reducedMotion,
            ),
          ],
        ],
      ),
    );

    final inner = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: stageRow,
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
    final localSecondary =
        secondary != null && snnStageForPhase(secondary) == stage
        ? secondary
        : null;
    final localSplitStep = localSecondary == null ? null : widget.splitStep;
    final colors = Zeta.of(context).colors;

    return NmtkPipelineStepper(
      key: ValueKey<SnnWorkflowStage>(stage),
      bare: true,
      shrinkWrap: true,
      // The stage rail has a fixed-width viewport inside the horizontally
      // scrollable workflow bar. Let its substeps scroll within that viewport
      // instead of forcing their row to overflow during split-pane layouts.
      scrollable: true,
      wrapOnCompact: false,
      contentPadding: EdgeInsets.zero,
      stepAccentColor: colors.mainPrimary,
      stepStyle: NmtkPipelineStepStyle.destination,
      stepWidth: _kSubstepPillWidth,
      statusBarSemanticsLabel:
          '${widget.stageLabels[stage] ?? stage.name} steps',
      selectedStepId: widget.currentPhase.name,
      secondarySelectedStepId: localSecondary?.name,
      disabledStepIds: widget.lockedPhases.map((p) => p.name).toSet(),
      disabledTooltip: widget.disabledTooltip,
      splitStepId: localSplitStep,
      onSplitBetween: widget.onSplitBetween == null
          ? null
          : (leftId, rightId) {
              final left = SnnWorkflowPhase.values.firstWhere(
                (phase) => phase.name == leftId,
              );
              final right = SnnWorkflowPhase.values.firstWhere(
                (phase) => phase.name == rightId,
              );
              if (snnStageForPhase(left) == snnStageForPhase(right)) {
                widget.onSplitBetween!(leftId, rightId);
              }
            },
      onCollapseStep: widget.onCollapseStep,
      onSelected: widget.onPhaseSelected == null
          ? null
          : (id) => widget.onPhaseSelected!(
              SnnWorkflowPhase.values.firstWhere((p) => p.name == id),
            ),
      steps: [for (final phase in stagePhases) _buildStepData(phase)],
    );
  }

  bool _stageIsLocked(SnnWorkflowStage stage) =>
      kSnnPhasesByStage[stage]!.every(widget.lockedPhases.contains);

  bool _stageIsCompleted(SnnWorkflowStage stage) =>
      kSnnPhasesByStage[stage]!.last.index < widget.currentPhase.index;

  bool _stageIsRunning(SnnWorkflowStage stage) =>
      widget.runningPhase != null &&
      snnStageForPhase(widget.runningPhase!) == stage;

  void _selectStage(SnnWorkflowStage stage) {
    if (widget.onPhaseSelected == null || _stageIsLocked(stage)) return;
    final unlocked = kSnnPhasesByStage[stage]!
        .where((phase) => !widget.lockedPhases.contains(phase))
        .toList(growable: false);
    if (unlocked.isEmpty) return;
    final remembered = _lastVisitedByStage[stage];
    widget.onPhaseSelected!(
      remembered != null && unlocked.contains(remembered)
          ? remembered
          : unlocked.first,
    );
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

/// A stage pill that shows just its label when collapsed, and — when
/// [selected] and [substeps] is non-null — grows to nest that stage's
/// sub-step chips inline, inside the same pill border.
///
/// `AnimatedSize` on the appended segment turns the swap between stages into
/// a smooth grow/shrink instead of a jump cut; because every stage reserves
/// the same sub-step width regardless of how many sub-steps it actually has
/// (see `_kPhaseRailWidth`), the row's total width never changes as the
/// segment moves from one pill to another.
class _StageCell extends StatelessWidget {
  const _StageCell({
    required this.number,
    required this.label,
    required this.selected,
    required this.completed,
    required this.running,
    required this.disabled,
    required this.disabledTooltip,
    required this.onTap,
    required this.substeps,
    required this.duration,
    required this.reducedMotion,
  });

  final int number;
  final String label;
  final bool selected;
  final bool completed;
  final bool running;
  final bool disabled;
  final String disabledTooltip;
  final VoidCallback onTap;
  final Widget? substeps;
  final Duration duration;
  final bool reducedMotion;

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

    final expanded = selected && substeps != null;
    final labelWidget = SizedBox(
      width: _kPhasePillWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    final segmentChild = expanded
        ? Padding(
            key: const ValueKey<String>('expanded'),
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1.5,
                  height: 20,
                  color: colors.borderPrimary.withValues(alpha: 0.4),
                ),
                const SizedBox(width: _kLabelToSubstepGap),
                // Every stage reserves the same width here regardless of
                // how many sub-steps it actually has, so the row's total
                // width stays constant across which stage is active.
                SizedBox(
                  width: _kPhaseRailWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: substeps!,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink(key: ValueKey<String>('collapsed'));

    // `AnimatedSize` does not tolerate a zero duration (it re-dirties itself
    // mid-layout), so reduced motion skips it entirely rather than feeding
    // it `Duration.zero`.
    final segment = reducedMotion
        ? segmentChild
        : AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: segmentChild,
          );

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
          side: BorderSide(
            color: selected ? colors.borderPrimary : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [labelWidget, segment],
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
