import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

class NmtkStatusBadge extends StatelessWidget {
  final String label;
  final NmtkTone tone;
  final IconData? icon;
  final String? semanticsLabel;

  const NmtkStatusBadge({
    super.key,
    required this.label,
    this.tone = NmtkTone.neutral,
    this.icon,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);

    return Semantics(
      label: semanticsLabel ?? label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: palette.foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: palette.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
