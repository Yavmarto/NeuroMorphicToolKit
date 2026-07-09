import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/widgets/buttons.dart';

class NmtkShellRetryButton extends StatelessWidget {
  final VoidCallback onPressed;

  const NmtkShellRetryButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return NmtkOutlinedButton(
      label: 'Retry',
      icon: ZetaIcons.refresh,
      onPressed: onPressed,
    );
  }
}
