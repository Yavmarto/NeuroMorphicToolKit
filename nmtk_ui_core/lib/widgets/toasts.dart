import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class NmtkToasts {
  NmtkToasts._();

  static void success(BuildContext context, String message) {
    ShadToaster.of(context).show(ShadToast(description: Text(message)));
  }

  static void error(BuildContext context, String message) {
    ShadToaster.of(
      context,
    ).show(ShadToast.destructive(description: Text(message)));
  }

  static void warning(BuildContext context, String message) {
    ShadToaster.of(context).show(
      ShadToast(
        description: Text(message),
      ),
    );
  }
}
