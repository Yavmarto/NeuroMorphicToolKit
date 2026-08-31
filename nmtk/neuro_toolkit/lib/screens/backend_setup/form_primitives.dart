import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

Widget buildTextField(
  TextEditingController controller,
  String label, {
  bool obscureText = false,
  Widget? suffix,
  String? errorText,
  String Function(String value)? valueSanitizer,
  FocusNode? focusNode,
}) {
  return NmtkTextInput(
    controller: controller,
    label: label,
    obscureText: obscureText,
    suffix: suffix,
    errorText: errorText,
    valueSanitizer: valueSanitizer,
    focusNode: focusNode,
  );
}

Widget buildMultilineField(
  TextEditingController controller,
  String label, {
  FocusNode? focusNode,
}) {
  return NmtkCodeTextArea(
    controller: controller,
    focusNode: focusNode,
    minLines: 4,
    maxLines: 8,
    label: label,
  );
}

Widget buildRadioLabel(String label) => Tooltip(
  message: label,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 210),
    child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
  ),
);

String? canonicalIpv4(String value) {
  final parts = value.trim().split('.');
  if (parts.length != 4) return null;
  final normalized = <String>[];
  for (final part in parts) {
    if (!RegExp(r'^\d{1,3}$').hasMatch(part)) return null;
    final number = int.tryParse(part);
    if (number == null || number > 255) return null;
    normalized.add(number.toString());
  }
  return normalized.join('.');
}

String displaySetupError(Object error) {
  return error.toString().replaceFirst(
    RegExp(r'^(Bad state|FormatException):\s*'),
    '',
  );
}

String modeLabel(String mode) {
  if (mode == 'docker') return 'Docker';
  if (mode == 'podman') return 'Podman';
  if (mode == 'kubernetes') return 'Kubernetes';
  return 'Standalone';
}
