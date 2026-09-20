library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_execution_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_setup_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_standard_deploy_page/studio_standard_deploy_page.dart';

/// Studio's live sensor source workspace for NeuroSense.
///
/// Unlike the compute deploy targets (Akida/PYNQ/Lava/SC-NeuroCore FPGA), a
/// sensor doesn't get paired with an SSH host — it's configured with a
/// device id, channel, and sample rate via [NeurosenseSensorConfigForm], held
/// in this widget's own [neuroSenseSourceProvider] rather than the shared
/// hardware-target pairing state.
class StudioNeuroSenseWorkspace extends ConsumerWidget {
  const StudioNeuroSenseWorkspace({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(neuroSenseSourceProvider);

    return StudioStandardDeployPage(
      title: 'NeuroSense live sensor',
      isCompact: isCompact,
      setup: const NeurosenseSetupSection(),
      inference: NeurosenseExecutionPane(config: config),
    );
  }
}
