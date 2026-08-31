import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

class PynqRunComplete extends ConsumerWidget {
  const PynqRunComplete({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NmtkStatusBanner(
      title: 'Finished on the board',
      content: const Text(
        'Output spikes, timing and verification steps are ready in the Review '
        'step.',
      ),
      tone: NmtkTone.success,
      actions: [
        ZetaButton.primary(
          key: const Key('pynq-view-results'),
          label: 'View results',
          leadingIcon: ZetaIcons.analytics,
          onPressed: () => ref
              .read(workspaceProvider.notifier)
              .setActivePipelineStep('deployReview'),
        ),
      ],
    );
  }
}
