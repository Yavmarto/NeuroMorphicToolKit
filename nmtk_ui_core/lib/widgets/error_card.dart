import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/section_card.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkErrorCard extends StatelessWidget {
  const NmtkErrorCard({
    super.key,
    required this.message,
    this.title = 'Workflow Error',
    this.subtitle = 'The workflow stopped before completion.',
    this.action,
    this.selectable = false,
    this.prefix,
  });

  final String message;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool selectable;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    return NmtkSectionCard(
      title: title,
      subtitle: subtitle,
      tone: NmtkTone.danger,
      leading: const Icon(Icons.error_outline, color: Colors.red),
      trailing: action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prefix != null) ...[prefix!, const SizedBox(height: 8)],
          selectable
              ? SelectableText(
                  message,
                  style: const TextStyle(color: Colors.red),
                )
              : Text(message, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}
