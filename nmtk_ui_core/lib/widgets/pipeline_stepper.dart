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
class NmtkPipelineStepper extends StatefulWidget {
  final List<NmtkPipelineStepData> steps;
  final String? selectedStepId;
  final ValueChanged<String>? onSelected;
  final bool bare;
  final Color stepAccentColor;

  final String? secondarySelectedStepId;

  const NmtkPipelineStepper({
    super.key,
    required this.steps,
    this.selectedStepId,
    this.secondarySelectedStepId,
    this.onSelected,
    this.bare = false,
    this.stepAccentColor = NmtkZetaTheme.primary,
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

    final stepLeft = stepBox.localToGlobal(Offset.zero, ancestor: rowContext.findRenderObject()).dx;
    final stepRight = stepLeft + stepBox.size.width;

    final visibleLeft = position.pixels;
    final visibleRight = position.pixels + viewportWidth;

    if (stepLeft >= visibleLeft && stepRight <= visibleRight) return;

    final tokens = NmtkShellTokens.of(context);
    final targetOffset = (stepLeft - 24)
        .clamp(0.0, position.maxScrollExtent);

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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _scrollController,
              child: Row(
                key: _rowKey,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: steps,
              ),
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
    for (int i = 0; i < widget.steps.length; i++) {
      final step = widget.steps[i];
      widgets.add(
        _PipelineStep(
          key: _stepKeys[step.id],
          data: step,
          selected: widget.selectedStepId == step.id ||
              widget.secondarySelectedStepId == step.id,
          accentColor: widget.stepAccentColor,
          onTap:
              step.onTap ??
              (widget.onSelected != null
                  ? () => widget.onSelected!(step.id)
                  : null),
        ),
      );
      if (i < widget.steps.length - 1) {
        widgets.add(
          _StepConnector(
            active: widget.steps[i].status == NmtkStepStatus.success,
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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
          const SizedBox(width: 8),
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
        iconData = widget.data.icon ?? Icons.circle_outlined;
        iconColor = widget.selected
            ? widget.accentColor
            : theme.colorScheme.onSurfaceVariant;
      case NmtkStepStatus.success:
        iconData = Icons.check_circle;
        iconColor = tokens.healthyColor;
      case NmtkStepStatus.error:
        iconData = Icons.error;
        iconColor = tokens.errorColor;
      default:
        iconData = widget.data.icon ?? Icons.circle_outlined;
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

  const _StepConnector({required this.active});

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Icon(
        Icons.arrow_forward_ios,
        size: 10,
        color: active
            ? tokens.healthyColor
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}
