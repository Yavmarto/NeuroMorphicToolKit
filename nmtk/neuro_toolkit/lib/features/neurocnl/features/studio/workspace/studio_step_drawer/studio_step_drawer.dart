import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';

class StudioStepDrawer extends ConsumerWidget {
  const StudioStepDrawer({
    super.key,
    required this.workspaceName,
    required this.currentPhase,
    required this.lockedPhases,
    required this.onPhaseSelected,
    this.onEditServer,
  });

  final String workspaceName;
  final SnnWorkflowPhase currentPhase;
  final Set<SnnWorkflowPhase> lockedPhases;
  final ValueChanged<SnnWorkflowPhase> onPhaseSelected;

  /// Launcher-owned action that opens the suite server connection popup.
  final Future<void> Function()? onEditServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Zeta.of(context).colors;
    final tokens = NmtkShellTokens.of(context);
    final serverConfig = ref.watch(serverConfigProvider);
    final isConnected = serverConfig.isConnected;
    final address = isConnected
        ? (serverConfig.backendUri.host.isNotEmpty
              ? serverConfig.backendUri.host
              : 'Connected')
        : 'Not connected';

    return Drawer(
      backgroundColor: colors.surfaceDefault,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => _showRenameDialog(context, ref, workspaceName),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        workspaceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Zeta.of(context).textStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(ZetaIcons.edit, size: 18, color: colors.mainSubtle),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final stage in SnnWorkflowStage.values) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                      child: Text(
                        kSnnStageLabels[stage] ?? stage.name,
                        style: Zeta.of(context).textStyles.bodySmall.copyWith(
                          color: colors.mainSubtle,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (final phase in kSnnPhasesByStage[stage]!)
                      _buildStepTile(context, phase, colors),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            InkWell(
              onTap: () => _handleEditServerTap(ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    NmtkStatusDot(
                      color: isConnected
                          ? tokens.healthyColor
                          : tokens.errorColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Zeta.of(context).textStyles.bodySmall.copyWith(
                          color: colors.mainSubtle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) {
    // ponytail: not disposed — the dialog's exit transition can still touch
    // the controller for a frame after the dialog Future resolves, so an
    // eager dispose() here throws "used after being disposed". This is a
    // short-lived controller for an infrequently-opened dialog; the leak is
    // negligible.
    final controller = TextEditingController(text: currentName);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Workspace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Workspace name'),
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Cancel',
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(workspaceProvider.notifier)
                  .setWorkspaceName(controller.text);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  // The root popup reports its own outcome. Re-check locally after it closes
  // so the Studio connection dot follows the root host state immediately.
  Future<void> _handleEditServerTap(WidgetRef ref) async {
    final editServer = onEditServer;
    if (editServer == null) return;
    await editServer();
    await _recheckCurrentUrl(ref);
  }

  /// Re-checks the root-selected server URL after the popup closes.
  Future<void> _recheckCurrentUrl(WidgetRef ref) async {
    final notifier = ref.read(serverConfigProvider.notifier);
    await notifier.checkConnection();
  }

  Widget _buildStepTile(
    BuildContext context,
    SnnWorkflowPhase phase,
    ZetaColors colors,
  ) {
    final isCurrent = phase == currentPhase;
    final isLocked = lockedPhases.contains(phase);

    return ZetaListItem(
      leading: CircleAvatar(
        radius: 12,
        backgroundColor: isCurrent ? colors.mainPrimary : Colors.transparent,
        child: Text(
          '${phase.index + 1}',
          style: Zeta.of(context).textStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w700,
            color: isCurrent
                ? colors.surfacePrimary
                : (isLocked ? colors.mainDisabled : colors.mainSubtle),
          ),
        ),
      ),
      title: Text(
        kSnnStepLabels[phase] ?? phase.name,
        style: isCurrent
            ? Zeta.of(context).textStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.mainPrimary,
              )
            : Zeta.of(context).textStyles.bodyMedium.copyWith(
                color: isLocked ? colors.mainDisabled : null,
              ),
      ),
      onTap: isLocked
          ? null
          : () {
              Navigator.of(context).pop();
              onPhaseSelected(phase);
            },
    );
  }
}
