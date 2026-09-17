import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';
import 'package:neuro_toolkit/ui_core/widgets/tone.dart';

/// Shared "locked step" treatment for workflow step indicators.
///
/// Both the desktop pipeline stepper (`NmtkPipelineStepper` /
/// `SnnWorkflowStepper`'s `_StageCell`) and the mobile workflow stepper
/// (`SnnMobileWorkflowStepper`) dim a step chip and, on desktop, explain why
/// via a tooltip, when that step is not yet reachable. Extracting the
/// wrapping here keeps the two indicator surfaces from silently drifting
/// apart on how "locked" reads.
class NmtkWorkflowLockedTreatment extends StatelessWidget {
  const NmtkWorkflowLockedTreatment({
    super.key,
    required this.child,
    required this.locked,
    this.opacity = 0.38,
    this.tooltip,
  });

  /// The step indicator to dim when [locked] is true.
  final Widget child;

  /// Whether the wrapped step is currently locked/disabled.
  final bool locked;

  /// Opacity applied to [child] while locked. Callers intentionally use
  /// different values (desktop's chips use 0.38, the mobile stepper's
  /// circular badges use 0.3) — both are readable dim-states for their own
  /// chip shape, so this stays a parameter rather than a single constant.
  final double opacity;

  /// Optional explanation shown in a [Tooltip] while locked. Left null on
  /// the mobile stepper, whose chips are dimmed but not the target of a
  /// hover/long-press tooltip.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    final dimmed = Opacity(opacity: opacity, child: child);
    final tooltipMessage = tooltip;
    if (tooltipMessage == null) return dimmed;
    return Tooltip(message: tooltipMessage, child: dimmed);
  }
}

class NmtkWorkflowStepRow extends StatelessWidget {
  const NmtkWorkflowStepRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.icon,
    this.padding = const EdgeInsets.only(bottom: 10),
  });

  final String title;
  final String subtitle;
  final NmtkTone tone;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(tokens.radiusChip),
            ),
            child: Icon(icon, size: 16, color: palette.foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Zeta.of(
                    context,
                  ).textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Zeta.of(context).textStyles.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
