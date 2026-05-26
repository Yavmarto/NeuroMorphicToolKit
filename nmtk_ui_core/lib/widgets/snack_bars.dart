import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import '../shell_tokens.dart';

class NmtkSnackBars {
  NmtkSnackBars._();

  static SnackBar success(BuildContext context, String message) {
    final tokens = NmtkShellTokens.of(context);
    return SnackBar(
      content: Text(message),
      backgroundColor: tokens.healthyColor,
    );
  }

  static SnackBar error(BuildContext context, String message) {
    final tokens = NmtkShellTokens.of(context);
    return SnackBar(content: Text(message), backgroundColor: tokens.errorColor);
  }
}
