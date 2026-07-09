import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

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
    this.pinnedTooltip = 'Pinned workspace',
    this.pinTooltip = 'Pin workspace',
    this.closeTooltip = 'Close workspace',
  });

  /// Tooltip shown on the pin toggle when [NmtkWorkspaceChipData.pinned] is true.
  final String pinnedTooltip;

  /// Tooltip shown on the pin toggle when the workspace is not pinned.
  final String pinTooltip;

  /// Tooltip shown on the close button.
  final String closeTooltip;

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
        color: Zeta.of(context).colors.surfaceDefault.withValues(alpha: 0),
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
                    ? palette.accent.withValues(alpha: 0.55)
                    : tokens.subtleBorder,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIconStack(theme, tokens, palette),
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
                    _buildBadge(theme, tokens, palette),
                  ],
                  if (onPinned != null) ...[
                    const SizedBox(width: 4),
                    _buildPinButton(theme, palette),
                  ],
                  if (onClosed != null) ...[
                    const SizedBox(width: 2),
                    _buildCloseButton(theme, palette),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconStack(
    ThemeData theme,
    NmtkShellTokens tokens,
    NmtkShellModePalette palette,
  ) {
    return Stack(
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
    );
  }

  Widget _buildBadge(
    ThemeData theme,
    NmtkShellTokens tokens,
    NmtkShellModePalette palette,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
    );
  }

  Widget _buildPinButton(ThemeData theme, NmtkShellModePalette palette) {
    return SizedBox.square(
      dimension: 44,
      // ZETA-MIGRATION-EXEMPT: icon color must track
      // palette.accentForeground (per-mode accent) for legibility against
      // the active chip's accent background; ZetaIconButton's fixed type
      // enum can't express that.
      child: IconButton(
        tooltip: data.pinned ? pinnedTooltip : pinTooltip,
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPinned,
        icon: Icon(
          data.pinned ? ZetaIcons.push_pin : ZetaIcons.push_pin_outline,
          size: 16,
          color: isActive
              ? palette.accentForeground
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildCloseButton(ThemeData theme, NmtkShellModePalette palette) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: closeTooltip,
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onClosed,
        icon: Icon(
          ZetaIcons.close,
          size: 16,
          color: isActive
              ? palette.accentForeground
              : theme.colorScheme.onSurfaceVariant,
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
