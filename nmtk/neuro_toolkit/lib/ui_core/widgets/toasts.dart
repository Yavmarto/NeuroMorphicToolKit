import 'package:flutter/material.dart';

import 'package:neuro_toolkit/ui_core/widgets/snack_bars.dart';

/// Top-right notification shorthands. Replaces the old bottom [SnackBar] surface.
class NmtkToasts {
  NmtkToasts._();

  static void success(BuildContext context, String message) {
    NmtkSnackBars.success(context, message);
  }

  static void error(BuildContext context, String message) {
    NmtkSnackBars.error(context, message);
  }

  static void warning(BuildContext context, String message) {
    NmtkSnackBars.warning(context, message);
  }
}
