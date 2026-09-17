import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class ToolCallCard extends StatelessWidget {
  const ToolCallCard({super.key, required this.entry});

  final StudioAgentTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final status = entry.toolStatus ?? StudioAgentToolStatus.running;
    final statusColor = switch (status) {
      StudioAgentToolStatus.running => colors.mainSubtle,
      StudioAgentToolStatus.succeeded => colors.mainPositive,
      StudioAgentToolStatus.failed => colors.mainNegative,
    };
    final statusLabel = switch (status) {
      StudioAgentToolStatus.running => 'Running',
      StudioAgentToolStatus.succeeded => 'Done',
      StudioAgentToolStatus.failed => 'Failed',
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ZetaIcons.build, size: 18, color: colors.mainPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.toolName ?? 'tool',
                    style: Zeta.of(context).textStyles.labelLarge,
                  ),
                ),
                Text(
                  statusLabel,
                  style: Zeta.of(context).textStyles.bodySmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (entry.toolResult != null) ...[
              const SizedBox(height: 8),
              Text(
                entry.toolResult!.summary,
                style: Zeta.of(context).textStyles.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
