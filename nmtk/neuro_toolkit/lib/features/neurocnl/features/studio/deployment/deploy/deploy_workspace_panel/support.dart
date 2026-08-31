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
                  const Expanded(
                    child: Text(
                      'Compiled Artifacts',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Material's default 48×48 tap target: this is the dialog's
                  // only dismissal control, and 36×36 was under the minimum.
                  IconButton(
                    icon: const Icon(ZetaIcons.close, size: 18),
                    onPressed: () => Navigator.of(ctx).pop(),
                    tooltip: 'Close',
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
