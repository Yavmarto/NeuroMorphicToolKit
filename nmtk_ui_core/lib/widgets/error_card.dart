import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/section_card.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkErrorCard extends StatelessWidget {
  const NmtkErrorCard({
    super.key,
    required this.message,
    this.title = 'Workflow Error',
    this.subtitle = 'The workflow stopped before completion.',
    this.action,
    this.prefix,
  });

  final String message;
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    final errColor = NmtkShellTokens.of(context).errorColor;
    final card = NmtkSectionCard(
      title: title,
      subtitle: subtitle,
      tone: NmtkTone.danger,
      leading: Icon(ZetaIcons.error_outline, color: errColor),
      trailing: action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prefix != null) ...[prefix!, const SizedBox(height: 8)],
          Text(
            message,
            style: Zeta.of(
              context,
            ).textStyles.bodyMedium.copyWith(color: errColor),
          ),
        ],
      ),
    );

    return card;
  }
}
