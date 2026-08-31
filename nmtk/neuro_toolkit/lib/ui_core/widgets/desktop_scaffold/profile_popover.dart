part of '../desktop_scaffold.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE POPOVER CONTENT
// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePopover extends StatelessWidget {
  const _ProfilePopover({required this.profile, required this.onClose});

  final NmtkUserProfile profile;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Profile header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                if (profile.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    profile.email!,
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Actions ───────────────────────────────────────────────
          for (final action in profile.actions)
            if (action.isDivider)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              )
            else
              _ProfileActionRow(action: action, onClose: onClose),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ProfileActionRow extends StatefulWidget {
  const _ProfileActionRow({required this.action, required this.onClose});

  final NmtkUserProfileAction action;
  final VoidCallback onClose;

  @override
  State<_ProfileActionRow> createState() => _ProfileActionRowState();
}

class _ProfileActionRowState extends State<_ProfileActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final action = widget.action;
    final fgColor = action.isDestructive ? scheme.error : scheme.onSurface;

    return Semantics(
      label: action.label,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            widget.onClose();
            action.onPressed?.call();
          },
          onHover: (hovered) => setState(() => _hovered = hovered),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: _hovered ? scheme.secondary.withValues(alpha: 0.12) : null,
            child: Row(
              children: [
                if (action.icon != null) ...[
                  Icon(
                    action.icon,
                    size: 15,
                    color: fgColor.withValues(alpha: 0.80),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  action.label ?? '',
                  style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: fgColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
