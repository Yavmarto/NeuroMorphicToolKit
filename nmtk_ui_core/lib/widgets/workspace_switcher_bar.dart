import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

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

class NmtkWorkspaceChip extends StatelessWidget {
  final NmtkWorkspaceChipData data;
  final bool isActive;
  final VoidCallback onSelected;
  final VoidCallback? onClosed;
  final VoidCallback? onPinned;
  final NmtkShellMode mode;

  const NmtkWorkspaceChip({
    super.key,
    required this.data,
    required this.isActive,
    required this.onSelected,
    this.onClosed,
    this.onPinned,
    this.mode = NmtkShellMode.command,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final palette = tokens.paletteForMode(mode);

    return Semantics(
      label: '${data.semanticsLabel ?? data.label}, status: ${data.state.name}',
      selected: isActive,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusChip),
          onTap: onSelected,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? palette.accentContainer
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(tokens.radiusChip),
              border: Border.all(
                color: isActive
                    ? palette.accent.withOpacity(0.55)
                    : tokens.subtleBorder,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        data.icon,
                        size: 18,
                        color: isActive
                            ? palette.accentForeground
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _statusColor(tokens, data.state),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isActive
                                  ? palette.accentContainer
                                  : theme.colorScheme.surface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    data.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive
                          ? palette.accentForeground
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (data.statusText != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      data.statusText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isActive
                            ? palette.accentForeground.withValues(alpha: 0.78)
                            : tokens.metadataForeground,
                      ),
                    ),
                  ],
                  if (data.badgeCount != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? palette.accent.withValues(alpha: 0.15)
                            : tokens.shellBackground,
                        borderRadius: BorderRadius.circular(tokens.radiusChip),
                      ),
                      child: Text(
                        '${data.badgeCount}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? palette.accentForeground
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                  if (onPinned != null) ...[
                    const SizedBox(width: 4),
                    SizedBox.square(
                      dimension: 44,
                      child: IconButton(
                        tooltip: data.pinned
                            ? 'Pinned workspace'
                            : 'Pin workspace',
                        style: IconButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onPinned,
                        icon: Icon(
                          data.pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 16,
                          color: isActive
                              ? palette.accentForeground
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (onClosed != null) ...[
                    const SizedBox(width: 2),
                    SizedBox.square(
                      dimension: 44,
                      child: IconButton(
                        tooltip: 'Close workspace',
                        style: IconButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onClosed,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: isActive
                              ? palette.accentForeground
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(NmtkShellTokens tokens, NmtkWorkspaceVisualState state) {
    return switch (state) {
      NmtkWorkspaceVisualState.active => tokens.runningColor,
      NmtkWorkspaceVisualState.idle => tokens.metadataForeground,
      NmtkWorkspaceVisualState.starting => tokens.warningColor,
      NmtkWorkspaceVisualState.degraded => tokens.degradedColor,
      NmtkWorkspaceVisualState.error => tokens.errorColor,
    };
  }
}
