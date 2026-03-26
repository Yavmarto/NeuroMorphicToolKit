import 'package:flutter/material.dart';

enum NmtkStepStatus { idle, running, success, error }

class NmtkPipelineStepData {
  final String label;
  final NmtkStepStatus status;
  final String? detail;
  final IconData? icon;
  final VoidCallback? onTap;

  const NmtkPipelineStepData({
    required this.label,
    required this.status,
    this.detail,
    this.icon,
    this.onTap,
  });
}

class NmtkPipelineStepper extends StatelessWidget {
  final List<NmtkPipelineStepData> steps;

  const NmtkPipelineStepper({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _buildSteps(context)),
      ),
    );
  }

  List<Widget> _buildSteps(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < steps.length; i++) {
      widgets.add(_PipelineStep(data: steps[i]));
      if (i < steps.length - 1) {
        widgets.add(
          _StepConnector(active: steps[i].status == NmtkStepStatus.success),
        );
      }
    }
    return widgets;
  }
}

class _PipelineStep extends StatelessWidget {
  final NmtkPipelineStepData data;

  const _PipelineStep({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = data.status != NmtkStepStatus.idle || data.onTap != null;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: data.onTap,
        child: MouseRegion(
          cursor: data.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getBgColor(theme),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _getBorderColor(theme), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIcon(theme),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.label,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (data.detail != null)
                      Text(
                        data.detail!,
                        style: TextStyle(
                          color: _getDetailColor(theme),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    if (data.status == NmtkStepStatus.running) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    IconData iconData;
    Color iconColor;

    switch (data.status) {
      case NmtkStepStatus.idle:
        iconData = data.icon ?? Icons.circle_outlined;
        iconColor = theme.colorScheme.onSurfaceVariant;
      case NmtkStepStatus.success:
        iconData = Icons.check_circle;
        iconColor = Colors.green;
      case NmtkStepStatus.error:
        iconData = Icons.error;
        iconColor = theme.colorScheme.error;
      default:
        iconData = data.icon ?? Icons.circle_outlined;
        iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return Icon(iconData, size: 16, color: iconColor);
  }

  Color _getBgColor(ThemeData theme) {
    switch (data.status) {
      case NmtkStepStatus.idle:
        return theme.colorScheme.surfaceContainerHighest;
      case NmtkStepStatus.running:
        return theme.colorScheme.primary.withOpacity(0.1);
      case NmtkStepStatus.success:
        return Colors.green.withOpacity(0.1);
      case NmtkStepStatus.error:
        return theme.colorScheme.error.withOpacity(0.1);
    }
  }

  Color _getBorderColor(ThemeData theme) {
    switch (data.status) {
      case NmtkStepStatus.idle:
        return theme.colorScheme.outlineVariant;
      case NmtkStepStatus.running:
        return theme.colorScheme.primary;
      case NmtkStepStatus.success:
        return Colors.green.withOpacity(0.3);
      case NmtkStepStatus.error:
        return theme.colorScheme.error.withOpacity(0.3);
    }
  }

  Color _getDetailColor(ThemeData theme) {
    switch (data.status) {
      case NmtkStepStatus.success:
        return Colors.green;
      case NmtkStepStatus.error:
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}

class _StepConnector extends StatelessWidget {
  final bool active;

  const _StepConnector({required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.arrow_forward_ios,
        size: 12,
        color: active
            ? Colors.green
            : theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
      ),
    );
  }
}
