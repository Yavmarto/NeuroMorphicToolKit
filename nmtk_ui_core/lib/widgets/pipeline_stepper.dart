import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/zeta_theme.dart';

enum NmtkStepStatus { idle, running, success, error }

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

/// A horizontally scrollable pipeline stepper with auto-alignment of the active step.
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

  const NmtkPipelineStepper({
    super.key,
    required this.steps,
    this.selectedStepId,
    this.secondarySelectedStepId,
    this.onSelected,
    this.bare = false,
    this.stepAccentColor = NmtkZetaTheme.primary,
    this.disabledStepIds = const <String>{},
    this.disabledTooltip = 'Complete the previous step first',
    this.splitStepId,
    this.onSplitBetween,
    this.onCollapseStep,
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

        final inner = Semantics(
          label: 'Pipeline status bar',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: constraints.maxWidth >= 840
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
    final leftSplitIdx = isSplit ? (selectedIdx < splitIdx ? selectedIdx : splitIdx) : -1;
    final rightSplitIdx = isSplit ? (selectedIdx < splitIdx ? splitIdx : selectedIdx) : -1;

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
              icon: Icons.remove,
              tooltip: 'Close left pane',
              onTap: () => widget.onCollapseStep!(keepId),
            );
          } else if (i == rightSplitIdx && widget.onCollapseStep != null) {
            final keepId = widget.steps[leftSplitIdx].id;
            slotKey = 'minus_right_$i';
            slotChild = _ConnectorSlotButton(
              key: ValueKey(slotKey),
              icon: Icons.remove,
              tooltip: 'Close right pane',
              onTap: () => widget.onCollapseStep!(keepId),
            );
          } else {
            slotKey = 'arrow_$i';
            slotChild = _StepConnector(key: ValueKey(slotKey), active: connectorActive);
          }
        } else if (
          widget.onSplitBetween != null &&
          selectedIdx >= 0 &&
          (i == selectedIdx || i + 1 == selectedIdx)
        ) {
          // Single pane: show + adjacent to the selected step.
          slotKey = 'plus_$i';
          slotChild = _ConnectorSlotButton(
            key: ValueKey(slotKey),
            icon: Icons.add,
            tooltip: 'Open split view',
            onTap: () => widget.onSplitBetween!(leftStep.id, rightStep.id),
          );
        } else {
          slotKey = 'arrow_$i';
          slotChild = _StepConnector(key: ValueKey(slotKey), active: connectorActive);
        }

        widgets.add(
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
                return FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(scale: curved, child: child),
                );
              },
              child: slotChild,
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _PipelineStep extends StatefulWidget {
  final NmtkPipelineStepData data;
  final bool selected;
  final VoidCallback? onTap;
  final Color accentColor;

  const _PipelineStep({
    super.key,
    required this.data,
    this.selected = false,
    this.onTap,
    required this.accentColor,
  });

  @override
  State<_PipelineStep> createState() => _PipelineStepState();
}

class _PipelineStepState extends State<_PipelineStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 60,
      ),
    ]).animate(_pulseCtrl);
  }

  @override
  void didUpdateWidget(covariant _PipelineStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fire a pulse whenever pulseTick increments on a running step, as long
    // as the user has not enabled reduced motion.
    final tickChanged = widget.data.pulseTick != oldWidget.data.pulseTick;
    final isRunning = widget.data.status == NmtkStepStatus.running;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (tickChanged && isRunning && !reduced) {
      _pulseCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final enabled =
        widget.data.status != NmtkStepStatus.idle || widget.onTap != null;

    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _getBgColor(context, theme, tokens),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: _getBorderColor(context, theme, tokens),
          width: widget.selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(context, theme, tokens),
          const SizedBox(width: 4),
          Text(
            widget.data.label,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 11,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    // Wrap in scale animation when running and pulseTick has ever been set.
    if (widget.data.status == NmtkStepStatus.running &&
        widget.data.pulseTick > 0) {
      chip = AnimatedBuilder(
        animation: _pulseScale,
        builder: (context, child) =>
            Transform.scale(scale: _pulseScale.value, child: child),
        child: chip,
      );
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Semantics(
        button: widget.onTap != null,
        selected: widget.selected,
        label:
            '${widget.data.label} step, '
            'status: ${widget.data.status.name}'
            '${widget.data.detail != null ? ", ${widget.data.detail}" : ""}',
        child: widget.onTap == null
            ? chip
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: widget.onTap, child: chip),
              ),
      ),
    );
  }

  Widget _buildIcon(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    if (widget.data.status == NmtkStepStatus.running) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: widget.accentColor,
        ),
      );
    }

    IconData iconData;
    Color iconColor;

    switch (widget.data.status) {
      case NmtkStepStatus.idle:
        iconData = widget.data.icon ?? ZetaIcons.radio_button_unchecked;
        iconColor = widget.selected
            ? widget.accentColor
            : theme.colorScheme.onSurfaceVariant;
      case NmtkStepStatus.success:
        iconData = ZetaIcons.check_circle;
        iconColor = tokens.healthyColor;
      case NmtkStepStatus.error:
        iconData = ZetaIcons.error;
        iconColor = tokens.errorColor;
      default:
        iconData = widget.data.icon ?? ZetaIcons.radio_button_unchecked;
        iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return Icon(iconData, size: 14, color: iconColor);
  }

  Color _getBgColor(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    final base = switch (widget.data.status) {
      NmtkStepStatus.idle => theme.colorScheme.surface,
      NmtkStepStatus.running => widget.accentColor.withValues(alpha: 0.12),
      NmtkStepStatus.success => tokens.healthyColor.withValues(alpha: 0.1),
      NmtkStepStatus.error => tokens.errorColor.withValues(alpha: 0.1),
    };
    return widget.selected
        ? Color.alphaBlend(widget.accentColor.withValues(alpha: 0.06), base)
        : base;
  }

  Color _getBorderColor(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    if (widget.selected) {
      return widget.accentColor;
    }
    switch (widget.data.status) {
      case NmtkStepStatus.idle:
        return theme.colorScheme.outlineVariant;
      case NmtkStepStatus.running:
        return widget.accentColor;
      case NmtkStepStatus.success:
        return tokens.healthyColor.withValues(alpha: 0.3);
      case NmtkStepStatus.error:
        return tokens.errorColor.withValues(alpha: 0.3);
    }
  }
}

class _StepConnector extends StatelessWidget {
  final bool active;

  const _StepConnector({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Icon(
        ZetaIcons.arrow_forward,
        size: 10,
        color: active
            ? tokens.healthyColor
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

// ── _ConnectorSlotButton ──────────────────────────────────────────────────────
// ponytail: tiny inline +/− button with hover/press animation in connector slots.

class _ConnectorSlotButton extends StatefulWidget {
  const _ConnectorSlotButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_ConnectorSlotButton> createState() => _ConnectorSlotButtonState();
}

class _ConnectorSlotButtonState extends State<_ConnectorSlotButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _pressed ? 0.88 : (_hovered ? 1.12 : 1.0);
    final bgColor = _hovered
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;
    final borderColor = _hovered
        ? theme.colorScheme.outlineVariant
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _hovered ? 0.18 : 0.10),
                    blurRadius: _hovered ? 6 : 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(widget.icon, size: 13, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
