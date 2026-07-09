import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

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
    super.key,
  });

  final String label;
  final NmtkTone tone;
  final IconData? icon;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final tokens = NmtkShellTokens.of(context);
    return Semantics(
      label: semanticsLabel ?? label,
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
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Zeta.of(context).textStyles.labelSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: palette.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
