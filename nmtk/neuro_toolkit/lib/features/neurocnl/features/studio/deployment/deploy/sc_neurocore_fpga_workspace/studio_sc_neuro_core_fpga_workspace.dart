library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/studio_standard_deploy_page/studio_standard_deploy_page.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/sc_neurocore_fpga_workspace/sc_neuro_core_execution_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/sc_neurocore_fpga_workspace/sc_neuro_core_setup_pane.dart';

class StudioScNeuroCoreFpgaWorkspace extends ConsumerWidget {
  const StudioScNeuroCoreFpgaWorkspace({
    super.key,
    this.selectedDeviceLabel,
    this.selectedDeviceData,
  });

  /// Display name of the currently selected synthesis target, or null when no
  /// target has been chosen yet.
  final String? selectedDeviceLabel;

  /// Raw [ScNeuroCoreTarget] data for the selected target, or null when unset.
  final Object? selectedDeviceData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = selectedDeviceData is ScNeuroCoreTarget
        ? selectedDeviceData! as ScNeuroCoreTarget
        : null;

    return StudioStandardDeployPage(
      title: 'SC-NeuroCore FPGA RTL',
      inference: ScNeuroCoreExecutionPane(hasTarget: target != null),
      setup: ScNeuroCoreSetupPane(target: target),
    );
  }
}
