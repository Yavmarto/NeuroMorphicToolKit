import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Reusable labeled input for Studio-owned forms.

class StudioFormField extends StatelessWidget {
  const StudioFormField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return ZetaTextInput(
      controller: controller,
      obscureText: obscureText,
      // ZETA-MIGRATION-TODO: obscuringCharacter dropped
      keyboardType: keyboardType,
      label: label,
      hintText: helperText,
      // ZETA-MIGRATION-TODO: border has no ZetaTextInput equivalent
    );
  }
}
