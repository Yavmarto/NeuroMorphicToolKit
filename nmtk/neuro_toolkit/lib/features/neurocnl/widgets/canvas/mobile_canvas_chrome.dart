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
    // The floating bars are fixed branded surfaces (canvas_screen.dart paints
    // the theme-independent "Obsidian Flow" colours), so their foregrounds
    // must be resolved from the actual bar colour — not theme-relative tokens
    // like mainInverse, which render dark-on-dark at ~1:1.
    final barColors = _CanvasBarColors.forBar(barBg);

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
        child: _CanvasBarColorsScope(
          colors: barColors,
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
                    tint: barColors.accent,
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
      color:
          (_CanvasBarColorsScope.maybeOf(context)?.icon ??
                  Zeta.of(context).colors.mainInverse)
              .withValues(alpha: 0.24),
      width: 16,
      thickness: 1,
    ),
  );
}

/// Resolved foreground palette for a fixed canvas bar.
///
/// The floating toolbars sit on deliberately theme-independent branded bars
/// (the "Obsidian Flow" colours in canvas_screen.dart), so their ink and
/// accent must not flip with theme-relative Zeta tokens. The colours are
/// derived from the actual [bar] colour instead, which keeps every caller
/// legible whether it passes a fixed dark bar or a theme-dependent one.
class _CanvasBarColors {
  const _CanvasBarColors({required this.icon, required this.accent});

  /// Default icon/ink colour (enabled state; also the disabled-ink base).
  final Color icon;

  /// Accent colour for the auto-layout action on this bar.
  final Color accent;

  factory _CanvasBarColors.forBar(Color bar) {
    // ZETA-MIGRATION-EXEMPT: fixed on-bar inks/accent — the obsidian bars have
    // no Zeta semantic role because they are intentionally independent of the
    // app light/dark theme (same rationale as the canvas_screen.dart callers).
    // Both inks clear WCAG 1.4.11's 3:1 floor on the obsidian bars (#0B1F3A /
    // #0B2116) and on the studio accentContainer surfaces the chrome is also
    // used on.
    final darkBar = bar.computeLuminance() < 0.35;
    return _CanvasBarColors(
      icon: darkBar ? const Color(0xFFF3F6FA) : const Color(0xFF1D1E23),
      accent: darkBar ? const Color(0xFF8B5CF6) : const Color(0xFF7C3AED),
    );
  }
}

/// Makes the resolved [barColors] available to every icon button hosted in the
/// bar, including the extraLeft/extraRight actions callers pass in.
class _CanvasBarColorsScope extends InheritedWidget {
  const _CanvasBarColorsScope({required this.colors, required super.child});

  final _CanvasBarColors colors;

  static _CanvasBarColors? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_CanvasBarColorsScope>()
      ?.colors;

  @override
  bool updateShouldNotify(_CanvasBarColorsScope oldWidget) =>
      colors.icon != oldWidget.colors.icon ||
      colors.accent != oldWidget.colors.accent;
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
    // When hosted on a fixed bar (MobileCanvasChrome) the icon follows the
    // bar-resolved ink so it stays legible in both app themes; standalone use
    // falls back to the theme-relative token.
    final ink =
        _CanvasBarColorsScope.maybeOf(context)?.icon ??
        Zeta.of(context).colors.mainInverse;
    final color = enabled ? (tint ?? ink) : ink.withValues(alpha: 0.38);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusLg,
        ),
        child: SizedBox(
          // 44x44 minimum tap target (icon stays visually 20px via Center).
          width: 44,
          height: 44,
          child: Center(child: Icon(icon, color: color, size: 20)),
        ),
      ),
    );
  }
}
