library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_targets_overview/deploy_targets_overview.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action_dock.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/mobile_deploy_action_scope.dart';

class DeployWorkspacePanel extends ConsumerStatefulWidget {
  const DeployWorkspacePanel({
    super.key,
    required this.selectedDeviceLabels,
    required this.selectedDeviceDataByTarget,
    required this.onSelectTarget,
    required this.onOpenInNeurosim,
    this.onManageHardwareTarget,
  });

  /// Paired-device display label per hardware target id.
  final Map<String, String> selectedDeviceLabels;

  /// Raw paired-device data per hardware target id.
  final Map<String, Object> selectedDeviceDataByTarget;
  final ValueChanged<String> onSelectTarget;
  final Future<void> Function() onOpenInNeurosim;

  /// Opens the pair/select-host dialog for a hardware target — the same one
  /// Setup's "Manage Targets" uses.
  final ValueChanged<String>? onManageHardwareTarget;

  @override
  ConsumerState<DeployWorkspacePanel> createState() =>
      _DeployWorkspacePanelState();
}

class _DeployWorkspacePanelState extends ConsumerState<DeployWorkspacePanel> {
  MobileDeployAction? _mobileAction;

  void _reportMobileAction(MobileDeployAction action) {
    final current = _mobileAction;
    if (current != null && current.matchesPresentation(action)) {
      _mobileAction = action;
      return;
    }
    setState(() => _mobileAction = action);
  }

  void _clearMobileAction(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mobileAction?.id != id) return;
      setState(() => _mobileAction = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isCompact =
            constraints.maxWidth < NmtkShellTokens.compactBreakpoint;
        const horizontalPadding = 16.0;
        final targetsOverview = DeployTargetsOverview(
          selectedDeviceLabels: widget.selectedDeviceLabels,
          selectedDeviceData: widget.selectedDeviceDataByTarget,
          onSelectTarget: widget.onSelectTarget,
          onManageHardwareTarget: widget.onManageHardwareTarget,
        );

        final Widget scrollable = ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 16,
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                targetsOverview,
                if (isCompact && _mobileAction != null)
                  const SizedBox(height: 16),
              ],
            ),
          ],
        );

        return MobileDeployActionScope(
          report: _reportMobileAction,
          clear: _clearMobileAction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: scrollable),
              if (isCompact && _mobileAction != null)
                MobileDeployActionDock(action: _mobileAction!),
            ],
          ),
        );
      },
    );
  }
}
