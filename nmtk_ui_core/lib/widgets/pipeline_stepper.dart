import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import '../shell_tokens.dart';
import '../zeta_theme.dart';

enum NmtkStepStatus { idle, running, success, error }

class NmtkPipelineStepData {
  final String id;
  final String label;
  final NmtkStepStatus status;
  final String? detail;
  final IconData? icon;
  final VoidCallback? onTap;

  const NmtkPipelineStepData({
    required this.id,
    required this.label,
    required this.status,
    this.detail,
    this.icon,
    this.onTap,
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

  const NmtkPipelineStepper({
    super.key,
    required this.steps,
    this.selectedStepId,
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
    final rowBox = rowContext.findRenderObject() as RenderBox?;
    if (stepBox == null ||
        rowBox == null ||
        !stepBox.hasSize ||
        !rowBox.hasSize) {
      return;
    }

    final tokens = NmtkShellTokens.of(context);
    final targetOffset = stepBox
        .localToGlobal(Offset.zero, ancestor: rowBox)
        .dx;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if ((_scrollController.offset - clampedOffset).abs() < 1) return;

    unawaited(
      _scrollController.animateTo(
        clampedOffset,
        duration: tokens.standardMotion,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    final inner = Semantics(
      label: 'Pipeline status bar',
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(key: _rowKey, children: _buildSteps(context)),
        ),
      ),
    );

    if (widget.bare) return inner;

    return Container(
      height: tokens.workspaceBarHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: inner,
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
          selected: widget.selectedStepId == step.id,
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

class _PipelineStep extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final enabled = data.status != NmtkStepStatus.idle || data.onTap != null;

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _getBgColor(context, theme, tokens),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: _getBorderColor(context, theme, tokens),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(context, theme, tokens),
          const SizedBox(width: 8),
          Text(
            data.label,
            style: ZetaTextStyles.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Semantics(
        button: onTap != null,
        selected: selected,
        label:
            '${data.label} step, status: ${data.status.name}${data.detail != null ? ", ${data.detail}" : ""}',
        child: onTap == null
            ? child
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: onTap, child: child),
              ),
      ),
    );
  }

  Widget _buildIcon(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    if (data.status == NmtkStepStatus.running) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
      );
    }

    IconData iconData;
    Color iconColor;

    switch (data.status) {
      case NmtkStepStatus.idle:
        iconData = data.icon ?? Icons.circle_outlined;
        iconColor = selected ? accentColor : theme.colorScheme.onSurfaceVariant;
      case NmtkStepStatus.success:
        iconData = Icons.check_circle;
        iconColor = tokens.healthyColor;
      case NmtkStepStatus.error:
        iconData = Icons.error;
        iconColor = tokens.errorColor;
      default:
        iconData = data.icon ?? Icons.circle_outlined;
        iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return Icon(iconData, size: 14, color: iconColor);
  }

  Color _getBgColor(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    final base = switch (data.status) {
      NmtkStepStatus.idle => theme.colorScheme.surface,
      NmtkStepStatus.running => accentColor.withValues(alpha: 0.12),
      NmtkStepStatus.success => tokens.healthyColor.withOpacity(0.1),
      NmtkStepStatus.error => tokens.errorColor.withOpacity(0.1),
    };
    return selected
        ? Color.alphaBlend(accentColor.withOpacity(0.06), base)
        : base;
  }

  Color _getBorderColor(
    BuildContext context,
    ThemeData theme,
    NmtkShellTokens tokens,
  ) {
    if (selected) {
      return accentColor;
    }
    switch (data.status) {
      case NmtkStepStatus.idle:
        return theme.colorScheme.outlineVariant;
      case NmtkStepStatus.running:
        return accentColor;
      case NmtkStepStatus.success:
        return tokens.healthyColor.withOpacity(0.3);
      case NmtkStepStatus.error:
        return tokens.errorColor.withOpacity(0.3);
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
            : theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
      ),
    );
  }
}
