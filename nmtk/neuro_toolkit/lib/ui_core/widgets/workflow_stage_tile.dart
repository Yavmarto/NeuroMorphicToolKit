part of 'workflow_card.dart';

class _NmtkWorkflowStageTile extends StatelessWidget {
  const _NmtkWorkflowStageTile({required this.stage});

  final NmtkWorkflowStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final color = switch (stage.state) {
      NmtkWorkflowStageState.done => tokens.healthyColor,
      NmtkWorkflowStageState.active => tokens.runningColor,
      NmtkWorkflowStageState.error => tokens.errorColor,
      // Not a status color — "upcoming" is a neutral not-yet-started state,
      // so it stays on the theme's neutral outline rather than a semantic
      // NmtkShellTokens color.
      NmtkWorkflowStageState.upcoming => theme.colorScheme.outlineVariant,
    };
    final icon = switch (stage.state) {
      NmtkWorkflowStageState.done => ZetaIcons.check_circle,
      NmtkWorkflowStageState.active => ZetaIcons.play_circle,
      NmtkWorkflowStageState.error => ZetaIcons.error,
      NmtkWorkflowStageState.upcoming => ZetaIcons.radio_button_unchecked,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(stage.detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
