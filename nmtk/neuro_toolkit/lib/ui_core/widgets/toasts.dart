import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

class NmtkToasts {
  NmtkToasts._();

  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      ZetaSnackBar(
        context: context,
        content: Text(message),
        type: ZetaSnackBarType.positive,
      ),
    );
  }

  static void error(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      ZetaSnackBar(
        context: context,
        content: Text(message),
        type: ZetaSnackBarType.error,
      ),
    );
  }

  static void warning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      ZetaSnackBar(
        context: context,
        content: Text(message),
        type: ZetaSnackBarType.warning,
      ),
    );
  }
}
