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
  review,
  deployHardware,
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
    SnnWorkflowPhase.review,
    SnnWorkflowPhase.deployHardware,
  ],
};

SnnWorkflowStage snnStageForPhase(SnnWorkflowPhase phase) => switch (phase) {
  SnnWorkflowPhase.selectData => SnnWorkflowStage.setup,
  SnnWorkflowPhase.defineModel ||
  SnnWorkflowPhase.defineTrain ||
  SnnWorkflowPhase.defineEval => SnnWorkflowStage.design,
  SnnWorkflowPhase.run ||
  SnnWorkflowPhase.review ||
  SnnWorkflowPhase.deployHardware => SnnWorkflowStage.execute,
};

/// Base step-name labels shared by the desktop, compact, and drawer steppers.
const Map<SnnWorkflowPhase, String> kSnnStepLabels = {
  SnnWorkflowPhase.selectData: 'Data & Targets',
  SnnWorkflowPhase.defineModel: 'Model',
  SnnWorkflowPhase.defineTrain: 'Training',
  SnnWorkflowPhase.defineEval: 'Evaluation',
  SnnWorkflowPhase.run: 'Run',
  SnnWorkflowPhase.review: 'Review',
  SnnWorkflowPhase.deployHardware: 'Deploy',
};

/// A floating Studio workflow accordion.
///
/// The three durable stages remain vertically visible. Only the active stage
/// reveals its local phases, keeping navigation available without occupying a
/// full canvas edge.
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

    final inner = LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 720.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final stage in SnnWorkflowStage.values) ...[
              _StageAccordionRow(
                stage: stage,
                active: stage == activeStage,
                maxWidth: availableWidth,
                duration: reducedMotion ? Duration.zero : tokens.standardMotion,
                stageDestination: _StageDestination(
                  number: stage.index + 1,
                  label: widget.stageLabels[stage] ?? stage.name,
                  selected: stage == activeStage,
                  completed: _stageIsCompleted(stage),
                  running: _stageIsRunning(stage),
                  disabled: _stageIsLocked(stage),
                  disabledTooltip: widget.disabledTooltip,
                  onTap: () => _selectStage(stage),
                ),
                child: _buildChildRail(context, stage),
              ),
              if (stage != SnnWorkflowStage.values.last)
                const SizedBox(height: 4),
            ],
          ],
        );
      },
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
      wrapOnCompact: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      stepAccentColor: colors.mainPrimary,
      stepStyle: NmtkPipelineStepStyle.destination,
      stepWidth: _StageAccordionRow.stageWidth,
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
          side: BorderSide(
            color: selected ? colors.borderPrimary : Colors.transparent,
          ),
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
                    '$number. $label',
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

class _StageAccordionRow extends StatelessWidget {
  const _StageAccordionRow({
    required this.stage,
    required this.active,
    required this.maxWidth,
    required this.duration,
    required this.stageDestination,
    required this.child,
  });

  static const double stageWidth = 136;
  static const double childGap = 8;

  final SnnWorkflowStage stage;
  final bool active;
  final double maxWidth;
  final Duration duration;
  final Widget stageDestination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final childWidth = (maxWidth - stageWidth - childGap).clamp(
      0.0,
      double.infinity,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: stageWidth, child: stageDestination),
        if (childWidth > 0) ...[
          const SizedBox(width: childGap),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: childWidth),
            child: ClipRect(
              child: TweenAnimationBuilder<double>(
                key: ValueKey<String>('${stage.name}-children'),
                duration: duration,
                curve: Curves.easeOutCubic,
                tween: Tween<double>(
                  begin: active ? 1 : 0,
                  end: active ? 1 : 0,
                ),
                builder: (context, progress, animatedChild) => IgnorePointer(
                  ignoring: !active,
                  child: ExcludeSemantics(
                    excluding: !active,
                    child: Opacity(
                      opacity: progress,
                      child: FractionalTranslation(
                        translation: Offset(progress - 1, 0),
                        child: animatedChild,
                      ),
                    ),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
