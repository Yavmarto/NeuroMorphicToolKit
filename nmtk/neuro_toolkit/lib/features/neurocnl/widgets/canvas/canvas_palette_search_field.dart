import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Search field shown above every canvas node palette — the two bottom-bar
/// ones ("Add Node", "Add NIR Primitive") and the port-anchored connect
/// palette.
///
/// Deliberately a dumb, stateless field: each palette owns the query string so
/// it can also react to [onSubmitted] (Enter adds the top-ranked node, which
/// makes the whole palette keyboard-operable).
class CanvasPaletteSearchField extends StatelessWidget {
  const CanvasPaletteSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.hintText = 'Search nodes…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Called when the user presses Enter. Palettes wire this to "add the
  /// top-ranked result".
  final VoidCallback? onSubmitted;

  /// Only enable on pointer platforms — autofocusing inside a mobile bottom
  /// sheet raises the software keyboard over the grid the user came to look at.
  final bool autofocus;

  final String hintText;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double radius = NmtkShellTokens.of(context).radiusSm;

    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        prefixIcon: Icon(
          ZetaIcons.search,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : ZetaIconButton.text(
                icon: ZetaIcons.close,
                size: ZetaWidgetSize.small,
                semanticLabel: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
      ),
    );
  }
}
