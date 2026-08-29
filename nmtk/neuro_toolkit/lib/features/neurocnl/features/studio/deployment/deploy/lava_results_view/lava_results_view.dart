import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_lava_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';

class LavaResultsView extends ConsumerWidget {
  const LavaResultsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runResult = ref.watch(
      studioLavaDeployProvider.select((state) => state.runResult),
    );
    if (runResult == null) return const SizedBox.shrink();
    final spikes =
        (runResult['spikes'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return NmtkSection(
      title: 'Lava run result',
      subtitle: 'Output of the last NeuroCNL Lava simulator run.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StudioPhaseBanner(
            label: 'Simulator run completed.',
            tone: NmtkTone.success,
          ),
          const SizedBox(height: 16),
          NmtkKeyValueRow(
            label: 'Run status',
            value: (runResult['status'] as String?) ?? 'unknown',
          ),
          NmtkKeyValueRow(
            label: 'Spiking neurons',
            value: spikes.entries
                .map((entry) => '${entry.key}: ${entry.value}')
                .join(', '),
          ),
          if (runResult['execution_time_ms'] != null)
            NmtkKeyValueRow(
              label: 'Exec ms',
              value: '${runResult['execution_time_ms']}',
            ),
        ],
      ),
    );
  }
}
