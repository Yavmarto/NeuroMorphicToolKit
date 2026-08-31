part of 'command_palette.dart';

class _ShortcutHint extends StatelessWidget {
  final String keyLabel;
  final String actionLabel;

  const _ShortcutHint({required this.keyLabel, required this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _KeyCap(label: keyLabel),
        const SizedBox(width: 4),
        Text(
          actionLabel,
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(fontSize: 10),
        ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;

  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
