import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

class AkidaRunComplete extends ConsumerWidget {
  const AkidaRunComplete({super.key, required this.kind});

  final StudioAkidaResultKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = kind == StudioAkidaResultKind.benchmark
        ? 'Benchmark finished'
        : 'Sample inference finished';
    return NmtkStatusBanner(
      title: label,
      content: const Text(
        'Charts and per-class accuracy are ready in the Review step.',
      ),
      tone: NmtkTone.success,
      actions: [
        ZetaButton.primary(
          key: const Key('akida-view-results'),
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
