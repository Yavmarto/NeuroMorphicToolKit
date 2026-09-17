import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class StimulusSourceButton extends StatelessWidget {
  const StimulusSourceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ZetaButton(
      label: label,
      onPressed: onPressed,
      size: ZetaWidgetSize.small,
      type: selected ? ZetaButtonType.primary : ZetaButtonType.outlineSubtle,
    );
  }
}
