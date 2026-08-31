import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class NmtkPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NmtkTone tone;

  const NmtkPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = NmtkTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final type = switch (tone) {
      NmtkTone.danger => ZetaButtonType.negative,
      NmtkTone.success => ZetaButtonType.positive,
      NmtkTone.neutral => ZetaButtonType.outlineSubtle,
      NmtkTone.info => ZetaButtonType.primary,
      NmtkTone.warning => ZetaButtonType.primary,
    };
    return ZetaButton(
      label: label,
      onPressed: onPressed,
      leadingIcon: icon,
      type: type,
    );
  }
}

class NmtkOutlinedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NmtkTone tone;

  const NmtkOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = NmtkTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final type = switch (tone) {
      NmtkTone.neutral => ZetaButtonType.outlineSubtle,
      _ => ZetaButtonType.outline,
    };
    return ZetaButton(
      label: label,
      onPressed: onPressed,
      leadingIcon: icon,
      type: type,
    );
  }
}
