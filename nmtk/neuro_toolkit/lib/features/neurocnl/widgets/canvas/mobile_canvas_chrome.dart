import 'package:flutter/material.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Floating mobile controls bar for the NIR canvas and pipeline canvases.
///
/// Wraps [body] with a [BottomBar] that hosts:
///   • Undo / Redo icon buttons (left)
///   • Auto-layout icon button (centre)
///   • Add icon button (right) — hidden when [onAddPrimitive] is null
///
/// All controls are passed in as callbacks — no provider reads here.
class MobileCanvasChrome extends StatelessWidget {
  const MobileCanvasChrome({
    super.key,
    required this.body,
    required this.onAutoLayout,
    this.onAddPrimitive,
    this.onClearCanvas,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    this.barColor,
    this.canvasTint,
    this.extraLeftActions,
    this.extraRightActions,
  });

  final Widget body;
  final VoidCallback onAutoLayout;

  /// When null the Add button is not shown.
  final VoidCallback? onAddPrimitive;
  final VoidCallback? onClearCanvas;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;

  /// Override for the floating bar background colour.
  /// Defaults to [Zeta.of(context).colors.surfaceDefault] when null.
  final Color? barColor;

  /// Optional translucent tint applied over the canvas body.
  /// Use a low-alpha colour (e.g. a [NmtkShellModePalette.frameTint]) to give
  /// the canvas a subtle mode-specific wash without affecting interactions.
  final Color? canvasTint;
  final List<Widget>? extraLeftActions;
  final List<Widget>? extraRightActions;

  @override
  Widget build(BuildContext context) {
    final barBg = barColor ?? Zeta.of(context).colors.surfaceDefault;

    final bar = Container(
      decoration: BoxDecoration(
        color: barBg,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusLg,
        ),
        boxShadow: [
          BoxShadow(
            // ZETA-MIGRATION-EXEMPT: drop-shadow cast color — no Zeta semantic role for shadows
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        // IntrinsicWidth clamps to the incoming (bounded) width, so the pill
        // still hugs its content when it fits; only when the buttons don't
        // fit (narrow phones with several extra actions) does the row
        // scroll horizontally instead of overflowing.
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (extraLeftActions != null) ...[
                  ...extraLeftActions!,
                  _barDivider(context),
                ],
                CanvasChromeIconButton(
                  icon: ZetaIcons.undo,
                  tooltip: 'Undo',
                  enabled: canUndo,
                  onPressed: onUndo,
                ),
                CanvasChromeIconButton(
                  icon: ZetaIcons.redo,
                  tooltip: 'Redo',
                  enabled: canRedo,
                  onPressed: onRedo,
                ),
                _barDivider(context),
                CanvasChromeIconButton(
                  icon: Icons
                      .auto_awesome, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  tooltip: 'Auto Layout',
                  enabled: true,
                  onPressed: onAutoLayout,
                  tint: NmtkShellTokens.of(context).studioPalette.accent,
                ),
                if (onAddPrimitive != null) ...[
                  _barDivider(context),
                  CanvasChromeIconButton(
                    icon: ZetaIcons.add,
                    tooltip: 'Add',
                    enabled: true,
                    onPressed: onAddPrimitive!,
                  ),
                ],
                if (onClearCanvas != null) ...[
                  _barDivider(context),
                  CanvasChromeIconButton(
                    icon: ZetaIcons.delete,
                    tooltip: 'Clear Canvas',
                    enabled: true,
                    tint: Zeta.of(context).colors.surfaceNegative,
                    onPressed: onClearCanvas!,
                  ),
                ],
                if (extraRightActions != null) ...[
                  _barDivider(context),
                  ...extraRightActions!,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (canvasTint != null)
          Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: canvasTint!)),
          ),
        Positioned(
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          left: 0,
          right: 0,
          child: Center(child: bar),
        ),
      ],
    );
  }

  Widget _barDivider(BuildContext context) => SizedBox(
    height: 24,
    child: VerticalDivider(
      color: Zeta.of(context).colors.mainInverse.withValues(alpha: 0.24),
      width: 16,
      thickness: 1,
    ),
  );
}

class CanvasChromeIconButton extends StatelessWidget {
  const CanvasChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.tint,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (tint ?? Zeta.of(context).colors.mainInverse)
        : Zeta.of(context).colors.mainInverse.withValues(alpha: 0.38);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusLg,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
