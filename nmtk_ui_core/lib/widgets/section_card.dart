import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/widgets/surface_card.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkSectionCard extends StatelessWidget {
  const NmtkSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.trailing,
    this.tone = NmtkTone.neutral,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final NmtkTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      tone: tone,
      padding: padding,
      child: child,
    );
  }
}
