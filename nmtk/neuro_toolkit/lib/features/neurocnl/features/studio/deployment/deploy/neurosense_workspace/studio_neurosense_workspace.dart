library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_execution_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_sensor_config_form.dart';
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
class StudioNeuroSenseWorkspace extends ConsumerStatefulWidget {
  const StudioNeuroSenseWorkspace({super.key, this.isCompact = false});

  final bool isCompact;

  @override
  ConsumerState<StudioNeuroSenseWorkspace> createState() =>
      _StudioNeuroSenseWorkspaceState();
}

class _StudioNeuroSenseWorkspaceState
    extends ConsumerState<StudioNeuroSenseWorkspace> {
  Future<void> _openConfigDialog() async {
    final current = ref.read(neuroSenseSourceProvider);
    final result = await showDialog<NeuroSenseSensorConfig>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: NmtkDialogSurface.insetPadding(dialogContext),
        shape: RoundedRectangleBorder(
          borderRadius: NmtkDesignTokens.dialogShape,
        ),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: NmtkDialogSurface.constraints(
              dialogContext,
              maxWidth: 480,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: NeurosenseSensorConfigForm(
                  initialConfig: current,
                  onCancel: () => Navigator.of(dialogContext).pop(),
                  onSave: (config) => Navigator.of(dialogContext).pop(config),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      ref.read(neuroSenseSourceProvider.notifier).setConfig(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(neuroSenseSourceProvider);

    return StudioStandardDeployPage(
      title: 'NeuroSense live sensor',
      isCompact: widget.isCompact,
      setup: NeurosenseSetupPane(
        config: config,
        onConfigureSource: _openConfigDialog,
      ),
      inference: NeurosenseExecutionPane(config: config),
    );
  }
}
