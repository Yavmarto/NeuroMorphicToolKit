import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/zeta_theme.dart';

part 'pipeline_stepper_parts.dart';

enum NmtkStepStatus { idle, running, success, error }

/// Visual treatment for an individual pipeline step.
enum NmtkPipelineStepStyle {
  /// Status-forward chip with an icon and status-tinted surfaces.
  status,

  /// Text-only destination matching the primary selection treatment.
  destination,
}

class NmtkPipelineStepData {
  final String id;
  final String label;
  final NmtkStepStatus status;
  final String? detail;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Monotonically increasing counter — increment this to trigger a brief
  /// scale-pulse on the step chip while it is in [NmtkStepStatus.running].
  /// Zero (the default) means "no pulse ever". Incrementing while the step
  /// is in any other status is safe and silently ignored.
  ///
  /// Intended use: wire to a training `epochTick` counter so the chip
  /// visually heartbeats each time a training epoch completes.
  final int pulseTick;

  const NmtkPipelineStepData({
    required this.id,
    required this.label,
    required this.status,
    this.detail,
    this.icon,
    this.onTap,
    this.pulseTick = 0,
  });
}

/// NeuroCNL's horizontally scrollable pipeline stepper with auto-alignment of the active step.
///
/// Set [bare] to true to embed just the scrollable row content inside a
/// parent toolbar without the standalone container/border wrapper.
///
/// Pass [splitStepId] to indicate a second active step (split-pane mode).
/// Provide [onSplitBetween] and [onCollapseStep] to enable animated +/−
/// connector-slot controls for opening and closing split panes.
class NmtkPipelineStepper extends StatefulWidget {
  final List<NmtkPipelineStepData> steps;
  final String? selectedStepId;
  final ValueChanged<String>? onSelected;
  final bool bare;
  final Color stepAccentColor;

  /// Visual treatment applied to every step.
  final NmtkPipelineStepStyle stepStyle;

  /// Optional fixed width shared by every step.
  final double? stepWidth;

  final String? secondarySelectedStepId;
  final Set<String> disabledStepIds;
  final String disabledTooltip;

  /// The step id of the second panel in split-pane mode. Null = single pane.
  final String? splitStepId;

  /// Called when the user taps a + connector between two steps.
  /// [leftId] is the step to the left of the connector, [rightId] to the right.
  final void Function(String leftId, String rightId)? onSplitBetween;

  /// Called when the user taps a − connector to collapse a pane.
  /// [keepId] is the step that should remain as the sole active step.
  final void Function(String keepId)? onCollapseStep;

  /// Tooltip for the − connector that closes the left split pane.
  final String closeLeftPaneTooltip;

  /// Tooltip for the − connector that closes the right split pane.
  final String closeRightPaneTooltip;

  /// Tooltip for the + connector that opens a split pane.
  final String openSplitViewTooltip;

  /// Semantics label announced for the whole stepper.
  final String statusBarSemanticsLabel;

  /// Whether steps wrap onto multiple lines below the compact breakpoint.
  ///
  /// Disable this when the stepper is embedded in a narrow horizontal
  /// accordion so its children stay on one scrollable line.
  final bool wrapOnCompact;

  /// Whether the stepper should use its natural horizontal content width.
  ///
  /// The width remains capped by the incoming constraints, so overflowing
  /// steps still scroll horizontally. The default keeps the existing
  /// full-width toolbar behavior.
  final bool shrinkWrap;

  /// Padding around the step row.
  ///
  /// Embedded controls may remove vertical padding so the row does not make
  /// its parent destination taller. Standalone steppers keep the existing
  /// toolbar padding by default.
  final EdgeInsetsGeometry contentPadding;

  /// Whether the step row may scroll horizontally on overflow.
  ///
  /// Disable this when embedding the stepper inside a widget that already
  /// provides its own horizontal scroll (or reflow) for overflow — nesting
  /// two horizontal scrollables causes unbounded-width layout errors.
  final bool scrollable;

  const NmtkPipelineStepper({
    super.key,
    required this.steps,
    this.selectedStepId,
    this.secondarySelectedStepId,
    this.onSelected,
    this.bare = false,
    this.stepAccentColor = NmtkZetaTheme.primary,
    this.stepStyle = NmtkPipelineStepStyle.status,
    this.stepWidth,
    this.disabledStepIds = const <String>{},
    this.disabledTooltip = 'Complete the previous step first',
    this.splitStepId,
    this.onSplitBetween,
    this.onCollapseStep,
    this.closeLeftPaneTooltip = 'Close left pane',
    this.closeRightPaneTooltip = 'Close right pane',
    this.openSplitViewTooltip = 'Open split view',
    this.statusBarSemanticsLabel = 'Pipeline status bar',
    this.wrapOnCompact = true,
    this.shrinkWrap = false,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
    this.scrollable = true,
  });

  @override
  State<NmtkPipelineStepper> createState() => _NmtkPipelineStepperState();
}

class _NmtkPipelineStepperState extends State<NmtkPipelineStepper> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _rowKey = GlobalKey(debugLabel: 'pipeline-stepper-row');
  late Map<String, GlobalKey> _stepKeys;

  @override
  void initState() {
    super.initState();
    _updateStepKeys();
    _scheduleActiveStepAlignment();
  }

  @override
  void didUpdateWidget(covariant NmtkPipelineStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.steps != oldWidget.steps) {
      _updateStepKeys();
    }
    if (oldWidget.selectedStepId != widget.selectedStepId) {
      _scheduleActiveStepAlignment();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateStepKeys() {
    _stepKeys = {
      for (final step in widget.steps) step.id: GlobalKey(debugLabel: step.id),
    };
  }

  void _scheduleActiveStepAlignment() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _alignActiveStepToLeadingEdge();
    });
  }

  void _alignActiveStepToLeadingEdge() {
    final selectedStepId = widget.selectedStepId;
    if (selectedStepId == null || !_scrollController.hasClients) return;

    final stepContext = _stepKeys[selectedStepId]?.currentContext;
    final rowContext = _rowKey.currentContext;
    if (stepContext == null || rowContext == null) return;

    final stepBox = stepContext.findRenderObject() as RenderBox?;
    if (stepBox == null || !stepBox.hasSize) return;

    final position = _scrollController.position;
    final viewportWidth = position.viewportDimension;

    final stepLeft = stepBox
        .localToGlobal(Offset.zero, ancestor: rowContext.findRenderObject())
        .dx;
    final stepRight = stepLeft + stepBox.size.width;

    final visibleLeft = position.pixels;
    final visibleRight = position.pixels + viewportWidth;

    if (stepLeft >= visibleLeft && stepRight <= visibleRight) return;

    final tokens = NmtkShellTokens.of(context);
    final targetOffset = (stepLeft - 24).clamp(0.0, position.maxScrollExtent);

    if ((position.pixels - targetOffset).abs() < 1) return;

    unawaited(
      _scrollController.animateTo(
        targetOffset,
        duration: tokens.standardMotion,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final steps = _buildSteps(context);

        Widget inner = Semantics(
          label: widget.statusBarSemanticsLabel,
          child: Padding(
            padding: widget.contentPadding,
            child: !widget.scrollable
                ? Row(
                    key: _rowKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: steps,
                  )
                : !widget.wrapOnCompact || constraints.maxWidth >= 840
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _scrollController,
                    child: Row(
                      key: _rowKey,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: steps,
                    ),
                  )
                : Wrap(
                    key: _rowKey,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    spacing: 0,
                    children: steps,
                  ),
          ),
        );

        if (widget.shrinkWrap) {
          inner = Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: inner,
          );
        }

        if (widget.bare) return inner;

        return Container(
          constraints: BoxConstraints(minHeight: tokens.workspaceBarHeight),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: inner,
        );
      },
    );
  }

  List<Widget> _buildSteps(BuildContext context) {
    final widgets = <Widget>[];

    // Pre-compute split indices for connector logic.
    final selectedId = widget.selectedStepId;
    final splitId = widget.splitStepId;
    int selectedIdx = -1;
    int splitIdx = -1;
    if (selectedId != null) {
      selectedIdx = widget.steps.indexWhere((s) => s.id == selectedId);
    }
    if (splitId != null) {
      splitIdx = widget.steps.indexWhere((s) => s.id == splitId);
    }
    final isSplit = splitId != null && selectedIdx >= 0 && splitIdx >= 0;
    final leftSplitIdx = isSplit
        ? (selectedIdx < splitIdx ? selectedIdx : splitIdx)
        : -1;
    final rightSplitIdx = isSplit
        ? (selectedIdx < splitIdx ? splitIdx : selectedIdx)
        : -1;

    for (int i = 0; i < widget.steps.length; i++) {
      final step = widget.steps[i];
      final disabled = widget.disabledStepIds.contains(step.id);
      if (disabled) {
        widgets.add(
          Tooltip(
            message: widget.disabledTooltip,
            child: Opacity(
              opacity: 0.38,
              child: _PipelineStep(
                key: _stepKeys[step.id],
                data: step,
                selected: false,
                accentColor: widget.stepAccentColor,
                style: widget.stepStyle,
                width: widget.stepWidth,
                onTap: null,
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          _PipelineStep(
            key: _stepKeys[step.id],
            data: step,
            selected:
                widget.selectedStepId == step.id ||
                widget.secondarySelectedStepId == step.id,
            accentColor: widget.stepAccentColor,
            style: widget.stepStyle,
            width: widget.stepWidth,
            onTap:
                step.onTap ??
                (widget.onSelected != null
                    ? () => widget.onSelected!(step.id)
                    : null),
          ),
        );
      }

      if (i < widget.steps.length - 1) {
        final leftStep = widget.steps[i];
        final rightStep = widget.steps[i + 1];
        final connectorActive = leftStep.status == NmtkStepStatus.success;

        // Determine which widget goes in this connector slot.
        Widget slotChild;
        String slotKey;

        if (isSplit) {
          // Split mode: show − before left split step and after right split step.
          if (i == leftSplitIdx - 1 && widget.onCollapseStep != null) {
            final keepId = widget.steps[rightSplitIdx].id;
            slotKey = 'minus_left_$i';
            slotChild = _ConnectorSlotButton(
              key: ValueKey(slotKey),
              icon: ZetaIcons.remove,
              tooltip: widget.closeLeftPaneTooltip,
              onTap: () => widget.onCollapseStep!(keepId),
            );
          } else if (i == rightSplitIdx && widget.onCollapseStep != null) {
            final keepId = widget.steps[leftSplitIdx].id;
            slotKey = 'minus_right_$i';
            slotChild = _ConnectorSlotButton(
              key: ValueKey(slotKey),
              icon: ZetaIcons.remove,
              tooltip: widget.closeRightPaneTooltip,
              onTap: () => widget.onCollapseStep!(keepId),
            );
          } else {
            slotKey = 'arrow_$i';
            slotChild = _StepConnector(
              key: ValueKey(slotKey),
              active: connectorActive,
            );
          }
        } else if (widget.onSplitBetween != null &&
            selectedIdx >= 0 &&
            (i == selectedIdx || i + 1 == selectedIdx)) {
          // Single pane: show + adjacent to the selected step.
          slotKey = 'plus_$i';
          slotChild = _ConnectorSlotButton(
            key: ValueKey(slotKey),
            icon: ZetaIcons.add,
            tooltip: widget.openSplitViewTooltip,
            onTap: () => widget.onSplitBetween!(leftStep.id, rightStep.id),
          );
        } else {
          slotKey = 'arrow_$i';
          slotChild = _StepConnector(
            key: ValueKey(slotKey),
            active: connectorActive,
          );
        }

        widgets.add(
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              );
            },
            child: slotChild,
          ),
        );
      }
    }

    // The interior loop above only places a − button in a connector slot
    // between two steps. When the split's left pane is the very first step
    // (or the right pane is the very last), there is no connector slot on
    // that outer side to hold one, so that pane could never be closed —
    // only the other side could. Add a boundary button for that edge so
    // either side of a split can always be collapsed.
    if (isSplit && widget.onCollapseStep != null) {
      if (leftSplitIdx == 0) {
        final keepId = widget.steps[rightSplitIdx].id;
        widgets.insert(
          0,
          _ConnectorSlotButton(
            key: const ValueKey('minus_left_boundary'),
            icon: ZetaIcons.remove,
            tooltip: widget.closeLeftPaneTooltip,
            onTap: () => widget.onCollapseStep!(keepId),
          ),
        );
      }
      if (rightSplitIdx == widget.steps.length - 1) {
        final keepId = widget.steps[leftSplitIdx].id;
        widgets.add(
          _ConnectorSlotButton(
            key: const ValueKey('minus_right_boundary'),
            icon: ZetaIcons.remove,
            tooltip: widget.closeRightPaneTooltip,
            onTap: () => widget.onCollapseStep!(keepId),
          ),
        );
      }
    }
    return widgets;
  }
}
