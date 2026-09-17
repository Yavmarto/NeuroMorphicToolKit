import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';

/// Colored pill badge with optional icon and accessible label.
///
/// Replaces the legacy `ZetaStatusLabel`-backed implementation.
/// Visual styling derives from [resolveNmtkTonePalette] so badges and
/// banners share identical colour semantics across the suite.
class NmtkStatusBadge extends StatelessWidget {
  const NmtkStatusBadge({
    required this.label,
    this.tone = NmtkTone.neutral,
    this.icon,
    this.semanticsLabel,
    this.onPressed,
    this.compact = false,
    super.key,
  });

  final String label;
  final NmtkTone tone;
  final IconData? icon;
  final String? semanticsLabel;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final tokens = NmtkShellTokens.of(context);
    final badge = Semantics(
      label: semanticsLabel ?? label,
      button: onPressed != null,
      enabled: onPressed != null ? true : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: palette.border, width: 0.5),
          borderRadius: BorderRadius.all(Radius.circular(tokens.radiusChip)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: palette.foreground),
              if (!compact) const SizedBox(width: 6),
            ],
            if (!compact)
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Zeta.of(context).textStyles.labelSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.foreground,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final callback = onPressed;
    if (callback == null) return badge;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): callback,
        const SingleActivator(LogicalKeyboardKey.space): callback,
      },
      child: Focus(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: callback, child: badge),
        ),
      ),
    );
  }
}
