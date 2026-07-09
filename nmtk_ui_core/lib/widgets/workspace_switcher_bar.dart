import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/workspace_chip.dart';

class NmtkWorkspaceSwitcherBar extends StatelessWidget {
  final List<NmtkWorkspaceChipData> workspaces;
  final String activeWorkspaceId;
  final ValueChanged<String> onWorkspaceSelected;
  final ValueChanged<String>? onWorkspaceClosed;
  final ValueChanged<String>? onWorkspacePinned;
  final NmtkShellMode mode;
  final Widget? trailing;

  const NmtkWorkspaceSwitcherBar({
    super.key,
    required this.workspaces,
    required this.activeWorkspaceId,
    required this.onWorkspaceSelected,
    this.onWorkspaceClosed,
    this.onWorkspacePinned,
    this.mode = NmtkShellMode.command,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);

    return Container(
      height: tokens.workspaceBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.workspaceBarBackground,
        border: Border(bottom: BorderSide(color: tokens.subtleBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: workspaces.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final workspace = workspaces[index];
                return NmtkWorkspaceChip(
                  data: workspace,
                  isActive: workspace.id == activeWorkspaceId,
                  mode: mode,
                  onSelected: () => onWorkspaceSelected(workspace.id),
                  onClosed: workspace.closable && onWorkspaceClosed != null
                      ? () => onWorkspaceClosed!(workspace.id)
                      : null,
                  onPinned: onWorkspacePinned != null
                      ? () => onWorkspacePinned!(workspace.id)
                      : null,
                );
              },
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}
