import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';

/// Inline sensor setup for the Studio Setup step (and reused by
/// [StudioNeuroSenseWorkspace] when both setup + execution are shown).
class NeurosenseSetupSection extends ConsumerWidget {
  const NeurosenseSetupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(neuroSenseSourceProvider);
    return NeurosenseSetupPane(
      config: config,
      onConfigureSource: () => showNeurosenseConfigDialog(context, ref),
    );
  }
}
