import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/app_theme.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// Multiline code/configuration input using the suite's typography and shape.
///
/// Zeta 1.4.5 does not expose multiline parameters on [ZetaTextInput]. Keeping
/// this compatibility surface in `nmtk_ui_core` prevents module code from
/// creating inconsistent raw text fields while preserving multiline editing.
class NmtkCodeTextArea extends StatelessWidget {
  const NmtkCodeTextArea({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.minLines = 4,
    this.maxLines = 8,
    this.focusNode,
    this.errorText,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final int minLines;
  final int maxLines;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusSm),
    );
    return SelectionContainer.disabled(
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        minLines: minLines,
        maxLines: maxLines,
        enabled: enabled,
        onChanged: onChanged,
        style: Zeta.of(context).textStyles.bodySmall.copyWith(
          fontFamily: NmtkFontFamilies.monospace,
          package: NmtkFontFamilies.package,
        ),
        decoration: InputDecoration(
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          labelText: label,
          hintText: hintText,
          errorText: errorText,
        ),
      ),
    );
  }
}
