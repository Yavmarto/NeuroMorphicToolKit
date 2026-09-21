import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Floating text field for stylus handwriting-to-node creation, shared by
/// every canvas.
///
/// Anchored to the raw screen [position] where the stylus tapped —
/// deliberately screen-space rather than scene-space/`LayerLink`, since the
/// interaction is momentary (tap, write, submit, dismiss) and doesn't need to
/// track live pan/zoom. The host canvas dismisses it if the viewport changes
/// while it's open.
///
/// Shows ranked suggestion chips as the user types; tapping a chip submits
/// that canonical node-type name immediately, which is what makes Apple
/// Scribble / handwriting-OCR errors recoverable instead of a dead end.
///
/// [suggest] returns the display names to offer for the current text. It is
/// supplied by the host so this widget stays free of any one canvas's node
/// model — the Architecture canvas ranks NIR types, the Train/Eval canvases
/// rank pipeline DAG types.
class CanvasHandwritingOverlay extends StatefulWidget {
  const CanvasHandwritingOverlay({
    super.key,
    required this.position,
    required this.controller,
    required this.onSubmitted,
    required this.onDismiss,
    required this.suggest,
  });

  final Offset position;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onDismiss;
  final List<String> Function(String query) suggest;

  @override
  State<CanvasHandwritingOverlay> createState() =>
      _CanvasHandwritingOverlayState();
}

class _CanvasHandwritingOverlayState extends State<CanvasHandwritingOverlay> {
  List<String> _suggestions = const <String>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final List<String> candidates = widget.suggest(widget.controller.text);
    if (mounted) {
      setState(() => _suggestions = candidates);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double radius = NmtkShellTokens.of(context).radiusSm;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(radius),
            color: colorScheme.surface,
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: widget.controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Node type…',
                      suffixIcon: widget.controller.text.isNotEmpty
                          ? IconButton(
                              // ZETA-MIGRATION-EXEMPT: matches the pre-existing
                              // clear affordance this widget was extracted from.
                              icon: Icon(
                                Icons.clear,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: widget.controller.clear,
                            )
                          : null,
                    ),
                    onSubmitted: widget.onSubmitted,
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const Divider(height: 6, thickness: 0.5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _suggestions.map((String name) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4, bottom: 4),
                            child: ActionChip(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              labelPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                name,
                                style: Zeta.of(
                                  context,
                                ).textStyles.bodyXSmall.copyWith(fontSize: 11),
                              ),
                              onPressed: () => widget.onSubmitted(name),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
