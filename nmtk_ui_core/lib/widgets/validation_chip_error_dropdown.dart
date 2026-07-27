part of 'validation_chip.dart';

class _ErrorDropdown extends StatelessWidget {
  const _ErrorDropdown({required this.errors});

  final List<NmtkValidationError> errors;

  @override
  Widget build(BuildContext context) {
    ZetaColors? colors;
    try {
      colors = Zeta.of(context).colors;
    } catch (_) {
      // ZetaProvider is not in the tree; fall back gracefully to
      // NmtkShellTokens.
    }

    final tokens = NmtkShellTokens.of(context);

    final bg = colors != null
        ? colors.surfaceNegativeSubtle
        : tokens.errorColor.withValues(alpha: 0.12);

    final border = colors != null
        ? colors.borderNegative
        : tokens.errorColor.withValues(alpha: 0.5);

    final fg = colors != null ? colors.mainNegative : tokens.errorColor;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: errors.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: border),
        itemBuilder: (context, index) {
          final error = errors[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error.line != null) ...[
                  Text(
                    'L${error.line}',
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: fg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    error.message,
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
