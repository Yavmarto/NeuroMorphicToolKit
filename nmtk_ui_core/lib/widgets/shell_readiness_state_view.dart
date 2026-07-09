import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/widgets/shell_status_badge.dart';
import 'package:nmtk_ui_core/widgets/surface_card.dart';

class NmtkShellReadinessStateView extends StatelessWidget {
  final NmtkShellStatusSpec status;
  final String title;
  final String message;
  final Widget? action;

  const NmtkShellReadinessStateView({
    super.key,
    required this.status,
    required this.title,
    required this.message,
    this.action,
  });

  factory NmtkShellReadinessStateView.fromState(
    NmtkShellReadinessState state, {
    String? message,
    Widget? action,
  }) {
    final status = NmtkShellStatusSpec.fromReadinessState(state);
    final title = switch (state) {
      NmtkShellReadinessState.opening => 'Opening workspace',
      NmtkShellReadinessState.warmingUp => 'Warming services',
      NmtkShellReadinessState.ready => 'Workspace ready',
      NmtkShellReadinessState.degraded => 'Running with degraded capability',
      NmtkShellReadinessState.error => 'Workspace failed to become ready',
    };
    final body = switch (state) {
      NmtkShellReadinessState.opening =>
        message ?? 'The shell is mounting the workspace and restoring chrome.',
      NmtkShellReadinessState.warmingUp =>
        message ??
            'The workspace is visible while module services keep loading.',
      NmtkShellReadinessState.ready =>
        message ?? 'The shell is ready for normal interaction.',
      NmtkShellReadinessState.degraded =>
        message ??
            'Some features are unavailable, but the workspace is still usable.',
      NmtkShellReadinessState.error =>
        message ??
            'The shell could not finish startup and needs recovery action.',
    };

    return NmtkShellReadinessStateView(
      status: status,
      title: title,
      message: body,
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NmtkSurfaceCard(
      title: title,
      subtitle: message,
      leading: Icon(
        status.icon ?? ZetaIcons.info,
        size: 20,
        color: theme.colorScheme.primary,
      ),
      trailing: NmtkShellStatusBadge(status: status),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status.detailText ?? message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 16), action!],
        ],
      ),
    );
  }
}
