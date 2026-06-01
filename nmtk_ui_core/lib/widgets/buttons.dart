import 'package:flutter/widgets.dart';
import 'package:nmtk_ui_core/cupertino_kit/primitives/kit_button.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

/// Public NMTK primary button.
///
/// Pre-migration this wrapped `ZetaButton`; post-migration it wraps
/// the kit's [KitButton]. Constructor parameter names are preserved
/// so submodule call sites don't need to change.
class NmtkPrimaryButton extends StatelessWidget {
  const NmtkPrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = NmtkTone.info,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NmtkTone tone;

  @override
  Widget build(BuildContext context) {
    final style = switch (tone) {
      NmtkTone.danger => KitButtonStyle.destructive,
      NmtkTone.success => KitButtonStyle.tinted,
      NmtkTone.neutral => KitButtonStyle.outline,
      NmtkTone.info => KitButtonStyle.filled,
      NmtkTone.warning => KitButtonStyle.filled,
    };
    return KitButton(
      label: label,
      onPressed: onPressed,
      leadingIcon: icon,
      style: style,
    );
  }
}

/// Public NMTK outlined / secondary button.
class NmtkOutlinedButton extends StatelessWidget {
  const NmtkOutlinedButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = NmtkTone.neutral,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NmtkTone tone;

  @override
  Widget build(BuildContext context) {
    return KitButton(
      label: label,
      onPressed: onPressed,
      leadingIcon: icon,
      style: KitButtonStyle.outline,
    );
  }
}
