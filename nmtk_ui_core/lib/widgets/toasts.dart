import 'package:flutter/material.dart';

class NmtkToasts {
  NmtkToasts._();

  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: SelectionArea(child: Text(message))));
  }

  static void error(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectionArea(child: Text(message)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  static void warning(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: SelectionArea(child: Text(message))));
  }
}
