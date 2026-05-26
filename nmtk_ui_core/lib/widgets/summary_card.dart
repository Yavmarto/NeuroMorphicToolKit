import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';

class NmtkSummaryCard extends StatelessWidget {
  const NmtkSummaryCard({
    super.key,
    required this.title,
    required this.description,
    required this.chips,
  });

  final String title;
  final String description;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    ZetaColors? colors;
    try {
      colors = Zeta.of(context).colors;
    } catch (_) {}

    final tokens = NmtkShellTokens.of(context);

    final bg = colors != null
        ? colors.surfacePrimarySubtle
        : tokens.runningColor.withOpacity(0.08);

    final border = colors != null
        ? colors.borderPrimary
        : tokens.runningColor.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ZetaTextStyles.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}
