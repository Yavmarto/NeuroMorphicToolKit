import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/compiled_artifacts_panel.dart';

void showCompiledArtifactsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 740),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Compiled Artifacts',
                      overflow: TextOverflow.ellipsis,
                      style: Zeta.of(context).textStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: ZetaIconButton.text(
                      icon: ZetaIcons.close,
                      size: ZetaWidgetSize.small,
                      semanticLabel: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Expanded(child: CompiledArtifactsPanel()),
          ],
        ),
      ),
    ),
  );
}

// end of file
