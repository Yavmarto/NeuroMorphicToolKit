import 'package:flutter/material.dart';

class NmtkKeyValueRow extends StatelessWidget {
  const NmtkKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.padding = const EdgeInsets.only(bottom: 6),
    this.valueColor,
  });

  final String label;
  final String value;
  final EdgeInsetsGeometry padding;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
