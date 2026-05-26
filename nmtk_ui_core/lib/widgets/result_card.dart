import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/widgets/section_card.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkResultCard extends StatelessWidget {
  const NmtkResultCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.leading,
    required this.child,
  });

  final String title;
  final String subtitle;
  final NmtkTone tone;
  final Widget leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NmtkSectionCard(
      title: title,
      subtitle: subtitle,
      tone: tone,
      leading: leading,
      child: child,
    );
  }
}
