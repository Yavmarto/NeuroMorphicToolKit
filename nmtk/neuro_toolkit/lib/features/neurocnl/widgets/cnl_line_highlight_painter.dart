import 'package:flutter/material.dart';

/// [CustomPainter] that draws a line-highlight tint behind the CNL editor's
/// [TextField] to indicate the currently focused line.
///
/// This is a display-only diagnostic painter. It lives in a [Stack] behind
/// the [TextField] so the editor interaction is unaffected.
///
/// ## Coordinate contract
/// - [lineOffset] — vertical offset of the focused logical line, calculated
///   from the editor's text layout so soft-wrapped lines stay aligned.
/// - [scrollOffset] — current scroll position of the editor's
///   [ScrollController], used to translate the highlight into the visible
///   viewport.
/// - [paddingTop] — content padding above the first line (matches
///   `_kEditorContentPadding.top`).
///
class CnlLineHighlightPainter extends CustomPainter {
  const CnlLineHighlightPainter({
    required this.lineOffset,
    required this.lineHeight,
    required this.scrollOffset,
    required this.paddingTop,
    required this.accentColor,
    required this.cornerRadius,
  });

  /// Offset of the focused logical line. Null means no highlight is drawn.
  final double? lineOffset;

  /// Height of a single visual text line in logical pixels.
  final double lineHeight;

  /// Current vertical scroll offset of the editor scroll controller.
  final double scrollOffset;

  /// Top content padding applied by the [TextField]'s [InputDecoration].
  final double paddingTop;

  /// Studio focus colour supplied by the owning editor's design tokens.
  final Color accentColor;

  /// Corner radius supplied by the owning editor's design tokens.
  final double cornerRadius;

  static const double _kAccentStrokeWidth = 2.0;
  static const double _kFillOpacity = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final double? offset = lineOffset;
    if (offset == null) return;

    final double y = paddingTop + offset - scrollOffset;

    // Do not paint if the line is entirely above or below the visible viewport.
    if (y + lineHeight < 0 || y > size.height) return;

    final Rect rect = Rect.fromLTWH(0, y, size.width, lineHeight);
    final RRect roundedRect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cornerRadius),
    );

    // Fill.
    final Paint fillPaint = Paint()
      ..color = accentColor.withValues(alpha: _kFillOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(roundedRect, fillPaint);

    // Left accent stroke.
    final Paint strokePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, y, _kAccentStrokeWidth, lineHeight),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(CnlLineHighlightPainter oldDelegate) =>
      oldDelegate.lineOffset != lineOffset ||
      oldDelegate.scrollOffset != scrollOffset ||
      oldDelegate.lineHeight != lineHeight ||
      oldDelegate.paddingTop != paddingTop ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.cornerRadius != cornerRadius;
}
