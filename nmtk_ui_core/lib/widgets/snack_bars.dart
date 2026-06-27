import 'package:flutter/material.dart';

import 'package:nmtk_ui_core/shell_tokens.dart';

class NmtkSnackBars {
  NmtkSnackBars._();

  static SnackBar success(BuildContext context, String message) {
    final tokens = NmtkShellTokens.of(context);
    return SnackBar(
      content: SelectionArea(child: Text(message)),
      backgroundColor: tokens.healthyColor,
    );
  }

  static SnackBar error(BuildContext context, String message) {
    final tokens = NmtkShellTokens.of(context);
    return SnackBar(
      content: SelectionArea(child: Text(message)),
      backgroundColor: tokens.errorColor,
    );
  }
}
