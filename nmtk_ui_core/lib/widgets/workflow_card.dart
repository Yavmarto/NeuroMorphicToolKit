import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/surface_card.dart';

enum NmtkWorkflowStageState { upcoming, active, done, error }

class NmtkWorkflowStage {
  const NmtkWorkflowStage({
    required this.title,
    required this.detail,
    required this.state,
  });

  final String title;
  final String detail;
  final NmtkWorkflowStageState state;
}

class NmtkWorkflowCard extends StatelessWidget {
  const NmtkWorkflowCard({
    super.key,
    required this.stages,
    this.title = 'Workflow',
    this.subtitle = 'Each stage stays visible so the next action is obvious.',
  });

  final List<NmtkWorkflowStage> stages;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: stages
            .map(
              (stage) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NmtkWorkflowStageTile(stage: stage),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _NmtkWorkflowStageTile extends StatelessWidget {
  const _NmtkWorkflowStageTile({required this.stage});

  final NmtkWorkflowStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final color = switch (stage.state) {
      NmtkWorkflowStageState.done => Zeta.of(context).colors.mainPositive,
      NmtkWorkflowStageState.active => theme.colorScheme.primary,
      NmtkWorkflowStageState.error => theme.colorScheme.error,
      NmtkWorkflowStageState.upcoming => theme.colorScheme.outlineVariant,
    };
    final icon = switch (stage.state) {
      NmtkWorkflowStageState.done => Icons.check_circle,
      NmtkWorkflowStageState.active => Icons.play_circle_fill,
      NmtkWorkflowStageState.error => Icons.error,
      NmtkWorkflowStageState.upcoming => Icons.radio_button_unchecked,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withOpacity(0.5)),
        color: color.withOpacity(0.08),
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
