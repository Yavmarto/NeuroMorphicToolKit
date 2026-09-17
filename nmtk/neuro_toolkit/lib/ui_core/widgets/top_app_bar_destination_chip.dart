part of 'top_app_bar.dart';

class _DestinationChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final Color accentContainer;
  final Color accentForeground;
  final VoidCallback onTap;

  const _DestinationChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.accentContainer,
    required this.accentForeground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return Material(
      color: Zeta.of(context).colors.surfaceDefault.withValues(alpha: 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? accentContainer
                : theme.colorScheme.surface.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(tokens.radiusChip),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.4)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? accentForeground
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? accentForeground
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
