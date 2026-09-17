import 'package:flutter/material.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class CnlPatchCard extends StatelessWidget {
  const CnlPatchCard({super.key, required this.artifact});

  final StudioAgentArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final patchText = artifact.cnlPatchText;
    if (patchText == null || patchText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ZetaIcons.edit, size: 18, color: colors.mainPrimary),
                const SizedBox(width: 8),
                Text(
                  artifact.title ?? 'CNL patch',
                  style: Zeta.of(context).textStyles.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              patchText,
              style: Zeta.of(
                context,
              ).textStyles.bodySmall.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
