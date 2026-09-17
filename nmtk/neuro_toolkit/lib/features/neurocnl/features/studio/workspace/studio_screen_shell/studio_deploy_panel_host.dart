import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/deploy_workspace_panel.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

/// Deploy step panel with target-selection side effects kept out of [StudioScreen.build].
class StudioDeployPanelHost extends ConsumerWidget {
  const StudioDeployPanelHost({
    super.key,
    required this.selectedDeviceLabels,
    required this.selectedDeviceDataByTarget,
    required this.onSelectTarget,
    required this.onOpenInNeurosim,
    required this.onManageHardwareTarget,
    required this.onSyncSelectedHardware,
    required this.onScheduleDeployValidation,
    required this.onScheduleSimulatorPreflight,
  });

  final Map<String, String> selectedDeviceLabels;
  final Map<String, Object> selectedDeviceDataByTarget;
  final ValueChanged<String> onSelectTarget;
  final Future<void> Function() onOpenInNeurosim;
  final Future<void> Function(String targetId) onManageHardwareTarget;
  final void Function(String targetType) onSyncSelectedHardware;
  final void Function(String targetType) onScheduleDeployValidation;
  final void Function(String targetType) onScheduleSimulatorPreflight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTarget = ref.watch(
      workspaceProvider.select((workspace) => workspace.selectedDeployTarget),
    );
    onSyncSelectedHardware(selectedTarget);
    onScheduleDeployValidation(selectedTarget);
    onScheduleSimulatorPreflight(selectedTarget);
    return DeployWorkspacePanel(
      key: const ValueKey('deploy-workspace-panel'),
      selectedDeviceLabels: selectedDeviceLabels,
      selectedDeviceDataByTarget: selectedDeviceDataByTarget,
      onSelectTarget: onSelectTarget,
      onOpenInNeurosim: onOpenInNeurosim,
      onManageHardwareTarget: onManageHardwareTarget,
    );
  }
}
