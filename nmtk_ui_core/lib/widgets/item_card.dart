import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/widgets/tone.dart';

/// Density variants for [NmtkItemCard].
///
/// * [compact] — denser stacks of items (Parse rows, validation messages).
/// * [regular] — roomier cards carrying more content (NIR node cards).
enum NmtkItemCardDensity { compact, regular }

/// A flat, outlined "row" card used as the canonical item primitive across
/// NMTK studio surfaces (Parse, Validate, NIR, …).
///
/// Visual recipe (per user-locked design choices Q2=a, Q3=b):
///
/// * Background: [ZetaColors.surfaceDefault] regardless of [tone].
/// * Outline: 1 px [ZetaColors.borderSubtle] regardless of [tone].
/// * Radius: `NmtkShellTokens.radiusSm` so it matches [NmtkSurfaceCard].
/// * Tone is conveyed by a 3 px **left-edge accent** mapped from [tone] via
///   the Zeta semantic border tokens. The card body never tints — keeps
///   stacks of cards readable when many tones appear in sequence.
/// * When [onTap] is set, the inner content is wrapped in an [InkWell] with
///   [ZetaColors.surfaceHover] overlay; otherwise no [InkWell] is created.
///
/// This widget is the **inner-row** counterpart to [NmtkSurfaceCard]. Use
/// [NmtkSurfaceCard] for outer section wrappers; use [NmtkItemCard] for
/// the items inside those sections.
class NmtkItemCard extends StatelessWidget {
  const NmtkItemCard({
    super.key,
    required this.child,
    this.leading,
    this.trailing,
    this.tone = NmtkTone.neutral,
    this.density = NmtkItemCardDensity.regular,
    this.onTap,
    this.semanticLabel,
    this.padding,
  });

  /// The main content of the card. Typically a `Column` or a single text.
  final Widget child;

  /// Leading widget (e.g. a small icon or a line-number pill). Sits between
  /// the left-edge accent and the [child].
  final Widget? leading;

  /// Trailing widget (e.g. a status icon or a chevron). Sits after the
  /// [child] on the same row.
  final Widget? trailing;

  /// Tone of the card. Controls only the left-edge accent color.
  final NmtkTone tone;

  /// Density of the card. Controls only padding and inner gap.
  final NmtkItemCardDensity density;

  /// Optional tap callback. When non-null the card becomes interactive
  /// (ripple + hover state). When null the card is purely presentational.
  final VoidCallback? onTap;

  /// Optional [Semantics] label for screen readers.
  final String? semanticLabel;

  /// Optional override for the inner padding around [leading]/[child]/
  /// [trailing]. When `null` the value is derived from [density]. Pass
  /// [EdgeInsets.zero] when the [child] brings its own padding (e.g. an
  /// [ExpansionTile]) to avoid double-padding.
  final EdgeInsetsGeometry? padding;

  /// 3 px accent column width. Exposed so tests can assert against it
  /// without importing the private constant.
  @visibleForTesting
  static const double accentBarWidth = 3.0;

  /// Padding (all sides) used for [NmtkItemCardDensity.compact].
  @visibleForTesting
  static const double compactPadding = 8.0;

  /// Padding (all sides) used for [NmtkItemCardDensity.regular].
  @visibleForTesting
  static const double regularPadding = 12.0;

  /// Inner gap between non-null slots used for [NmtkItemCardDensity.compact].
  @visibleForTesting
  static const double compactInnerGap = 6.0;

  /// Inner gap between non-null slots used for [NmtkItemCardDensity.regular].
  @visibleForTesting
  static const double regularInnerGap = 8.0;

  /// Stable key on the card's own decorated body [Container]. Structure
  /// tests use this to exclude the NmtkItemCard's own surface from
  /// "no nested filled+rounded Container" assertions, so they only flag
  /// hand-rolled card surfaces accidentally added INSIDE the [child] slot.
  @visibleForTesting
  static const Key surfaceKey = Key('NmtkItemCard.surface');

  double get _padding => density == NmtkItemCardDensity.compact
      ? compactPadding
      : regularPadding;

  double get _innerGap => density == NmtkItemCardDensity.compact
      ? compactInnerGap
      : regularInnerGap;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final colors = _zetaColorsOrNull(context);

    final bodyColor = colors?.surfaceDefault ?? tokens.canvasBackground;
    final outlineColor = colors?.borderSubtle ?? tokens.subtleBorder;
    final accentColor = _accentColorForTone(context, tone, colors, tokens);
    final radius = BorderRadius.circular(tokens.radiusSm);

    final innerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: accentBarWidth,
          decoration: BoxDecoration(color: accentColor),
        ),
        Expanded(
          child: Padding(
            padding: padding ?? EdgeInsets.all(_padding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  SizedBox(width: _innerGap),
                ],
                Expanded(child: child),
                if (trailing != null) ...<Widget>[
                  SizedBox(width: _innerGap),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ],
    );

    final card = ClipRRect(
      borderRadius: radius,
      child: Container(
        key: surfaceKey,
        decoration: BoxDecoration(
          color: bodyColor,
          border: Border.all(color: outlineColor),
          borderRadius: radius,
        ),
        // IntrinsicHeight makes the 3 px accent stretch to the row height
        // when the body grows due to multi-line content.
        child: IntrinsicHeight(
          child: onTap == null
              ? innerRow
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    overlayColor: WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                        if (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused) ||
                            states.contains(WidgetState.pressed)) {
                          return colors?.surfaceHover ??
                              tokens.subtleBorder.withValues(alpha: 0.12);
                        }
                        return null;
                      },
                    ),
                    child: innerRow,
                  ),
                ),
        ),
      ),
    );

    if (semanticLabel == null) {
      return card;
    }
    return Semantics(label: semanticLabel, container: true, child: card);
  }
}

/// Resolve the left-edge accent color for [tone].
///
/// Mapping (Zeta semantic tokens):
///
/// * [NmtkTone.neutral] → `borderSubtle` (calm, no semantic emphasis).
/// * [NmtkTone.info]    → `borderInfo`.
/// * [NmtkTone.success] → `borderPositive`.
/// * [NmtkTone.warning] → `borderWarning`.
/// * [NmtkTone.danger]  → `borderNegative`.
///
/// When `ZetaProvider` is not in the tree (e.g. some widget tests), this
/// falls back to [NmtkShellTokens] semantic colors so the widget still
/// renders sane colors.
Color _accentColorForTone(
  BuildContext context,
  NmtkTone tone,
  ZetaColors? colors,
  NmtkShellTokens tokens,
) {
  if (colors != null) {
    switch (tone) {
      case NmtkTone.neutral:
        return colors.borderSubtle;
      case NmtkTone.info:
        return colors.borderInfo;
      case NmtkTone.success:
        return colors.borderPositive;
      case NmtkTone.warning:
        return colors.borderWarning;
      case NmtkTone.danger:
        return colors.borderNegative;
    }
  }
  switch (tone) {
    case NmtkTone.neutral:
      return tokens.subtleBorder;
    case NmtkTone.info:
      return tokens.runningColor;
    case NmtkTone.success:
      return tokens.healthyColor;
    case NmtkTone.warning:
      return tokens.warningColor;
    case NmtkTone.danger:
      return tokens.errorColor;
  }
}

ZetaColors? _zetaColorsOrNull(BuildContext context) {
  try {
    return Zeta.of(context).colors;
  } catch (_) {
    return null;
  }
}
