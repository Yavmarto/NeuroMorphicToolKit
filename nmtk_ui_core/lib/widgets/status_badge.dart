import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class NmtkStatusBadge extends StatelessWidget {
  final String label;
  final NmtkTone tone;
  final IconData? icon;
  final String? semanticsLabel;

  const NmtkStatusBadge({
    super.key,
    required this.label,
    this.tone = NmtkTone.neutral,
    this.icon,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final status = switch (tone) {
      NmtkTone.neutral => ZetaWidgetStatus.neutral,
      NmtkTone.info => ZetaWidgetStatus.info,
      NmtkTone.success => ZetaWidgetStatus.positive,
      NmtkTone.warning => ZetaWidgetStatus.warning,
      NmtkTone.danger => ZetaWidgetStatus.negative,
    };

    return Semantics(
      label: semanticsLabel ?? label,
      child: ZetaStatusLabel(
        label: label,
        status: status,
        icon: icon,
        rounded: Zeta.of(context).rounded,
      ),
    );
  }
}
