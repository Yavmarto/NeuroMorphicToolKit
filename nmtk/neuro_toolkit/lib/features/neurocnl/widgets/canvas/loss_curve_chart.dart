import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Generic single-series training-curve chart (loss, accuracy, or any other
/// per-epoch scalar), matching the visual language of [TimeSeriesChart] used
/// in the simulator panel.
///
/// Renders a single line with:
/// - Filled area under the curve (10 % opacity) for visual weight
/// - A trailing cursor dot at the latest epoch while training is in progress
/// - 4 horizontal grid lines with value labels (formatted via
///   [valueFormatter])
/// - X-axis epoch ticks with an "Epoch" axis label
/// - An optional title rendered above the chart border
/// - An optional vertical marker (via [markerIndex]) showing which epoch is
///   currently selected elsewhere in the UI (e.g. the Results screen's
///   bottom epoch scrubber)
///
/// The default [height] (140 px) matches a comfortable panel inset. Pass a
/// larger value when the panel has more vertical space available.
///
/// Named `LossCurveChart` for backward-compatible call sites that only plot
/// loss; the widget itself is generic over [values] and works equally well
/// for accuracy or any other per-epoch scalar.
class LossCurveChart extends StatelessWidget {
  final List<double> values;
  final int? totalEpochs;
  final double height;
  final String title;

  /// Formats a raw value for the y-axis grid labels. Defaults to a
  /// loss-appropriate fixed-point format.
  final String Function(double value) valueFormatter;

  /// Index into [values] (0-based, positional — not the raw epoch number)
  /// to mark with a vertical line + dot, e.g. the epoch currently selected
  /// by an external scrubber. `null` or out-of-range draws no marker.
  final int? markerIndex;

  /// Optional hard floor for the y-axis minimum. Pass `0.0` for accuracy
  /// charts so a bad first epoch can't drag the scale below zero and squish
  /// the real training progress into a flat line at the top.
  final double? yFloor;

  const LossCurveChart({
    super.key,
    required this.values,
    this.totalEpochs,
    this.height = 140,
    this.title = 'Loss',
    this.valueFormatter = _defaultFormatter,
    this.markerIndex,
    this.yFloor,
  });

  static String _defaultFormatter(double v) =>
      v.toStringAsFixed(v.abs() < 0.01 ? 4 : 3);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Waiting for epoch data…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.metadataForeground,
            ),
          ),
        ),
      );
    }

    final markerIdx =
        (markerIndex != null &&
            markerIndex! >= 0 &&
            markerIndex! < values.length)
        ? markerIndex
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: height,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _LossCurvePainter(
                  values: values,
                  totalEpochs: totalEpochs ?? values.length,
                  lineColor: Zeta.of(context).colors.mainPrimary,
                  fillColor: Zeta.of(
                    context,
                  ).colors.mainPrimary.withValues(alpha: 0.08),
                  cursorColor: tokens.runningColor,
                  gridColor: theme.colorScheme.outlineVariant,
                  markerColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.7,
                  ),
                  markerIndex: markerIdx,
                  labelStyle: (theme.textTheme.bodySmall ?? const TextStyle())
                      .copyWith(color: tokens.metadataForeground, fontSize: 9),
                  axisLabelStyle:
                      (theme.textTheme.labelSmall ?? const TextStyle())
                          .copyWith(
                            color: tokens.metadataForeground,
                            fontSize: 9,
                          ),
                  valueFormatter: valueFormatter,
                  yFloor: yFloor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LossCurvePainter extends CustomPainter {
  final List<double> values;
  final int totalEpochs;
  final Color lineColor;
  final Color fillColor;
  final Color cursorColor;
  final Color gridColor;
  final Color markerColor;
  final int? markerIndex;
  final TextStyle labelStyle;
  final TextStyle axisLabelStyle;
  final String Function(double value) valueFormatter;
  final double? yFloor;

  const _LossCurvePainter({
    required this.values,
    required this.totalEpochs,
    required this.lineColor,
    required this.fillColor,
    required this.cursorColor,
    required this.gridColor,
    required this.markerColor,
    required this.markerIndex,
    required this.labelStyle,
    required this.axisLabelStyle,
    required this.valueFormatter,
    this.yFloor,
  });

  static const _leftMargin = 42.0;
  static const _rightMargin = 10.0;
  static const _topMargin = 8.0;
  static const _bottomMargin = 26.0; // room for epoch label + "Epoch" text

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _leftMargin - _rightMargin;
    final plotH = size.height - _topMargin - _bottomMargin;
    if (plotW <= 0 || plotH <= 0 || values.isEmpty) return;

    // Clip everything to the widget bounds so lines never bleed outside.
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // ── Y range ───────────────────────────────────────────────────────────────
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final rangeY = (maxVal - minVal).abs();
    final padY = rangeY < 1e-9 ? 0.1 : rangeY * 0.12;
    // If yFloor is set, never show below it (e.g. accuracy doesn't go < 0).
    final rawYMin = minVal - padY;
    final yMin = yFloor != null ? math.max(rawYMin, yFloor!) : rawYMin;
    final yMax = maxVal + padY;
    final yRange = yMax - yMin;

    double toY(double v) => _topMargin + plotH - ((v - yMin) / yRange) * plotH;
    double toX(int epoch) =>
        _leftMargin + (epoch / math.max(totalEpochs - 1, 1)) * plotW;

    // ── Grid ──────────────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // 3 interior grid lines → 4 labels total; prevents overlap in compact charts.
    const yTicks = 3;
    for (int i = 0; i <= yTicks; i++) {
      final frac = i / yTicks;
      final y = _topMargin + frac * plotH;
      canvas.drawLine(
        Offset(_leftMargin, y),
        Offset(size.width - _rightMargin, y),
        gridPaint,
      );
      final yVal = yMax - frac * yRange;
      _text(canvas, valueFormatter(yVal), Offset(0, y - 6), _leftMargin - 4);
    }

    // ── X-axis ticks ──────────────────────────────────────────────────────────
    final xTicks = math.min(5, totalEpochs);
    for (int i = 0; i <= xTicks; i++) {
      final epochIdx = (i / xTicks * (totalEpochs - 1)).round();
      final x = toX(epochIdx);
      canvas.drawLine(
        Offset(x, _topMargin + plotH),
        Offset(x, _topMargin + plotH + 3),
        gridPaint..strokeWidth = 1,
      );
      _text(
        canvas,
        (epochIdx + 1).toString(),
        Offset(x - 8, _topMargin + plotH + 5),
        20,
        centered: true,
      );
    }

    // "Epoch" axis label
    _axisText(
      canvas,
      'Epoch',
      Offset(_leftMargin + plotW / 2 - 16, size.height - 10),
      40,
    );

    // ── Fill under curve ──────────────────────────────────────────────────────
    final fillPath = Path();
    fillPath.moveTo(toX(0), toY(values.first));
    for (int i = 1; i < values.length; i++) {
      fillPath.lineTo(toX(i), toY(values[i]));
    }
    fillPath.lineTo(toX(values.length - 1), _topMargin + plotH);
    fillPath.lineTo(toX(0), _topMargin + plotH);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // ── Line ──────────────────────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final linePath = Path();
    for (int i = 0; i < values.length; i++) {
      if (i == 0) {
        linePath.moveTo(toX(i), toY(values[i]));
      } else {
        linePath.lineTo(toX(i), toY(values[i]));
      }
    }
    canvas.drawPath(linePath, linePaint);

    // ── Selected-epoch marker (external scrubber position) ─────────────────
    final markerIdx = markerIndex;
    if (markerIdx != null) {
      final mx = toX(markerIdx);
      _drawDashedLine(
        canvas,
        Offset(mx, _topMargin),
        Offset(mx, _topMargin + plotH),
        Paint()
          ..color = markerColor
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(
        Offset(mx, toY(values[markerIdx])),
        3.0,
        Paint()..color = markerColor,
      );
    }

    // ── Trailing cursor (only while still receiving data) ─────────────────────
    if (values.length < totalEpochs) {
      final cx = toX(values.length - 1);
      final cy = toY(values.last);
      canvas.drawLine(
        Offset(cx, _topMargin),
        Offset(cx, _topMargin + plotH),
        Paint()
          ..color = cursorColor.withValues(alpha: 0.55)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(Offset(cx, cy), 3.5, Paint()..color = cursorColor);
    } else if (values.isNotEmpty) {
      // Final dot at last point when complete.
      canvas.drawCircle(
        Offset(toX(values.length - 1), toY(values.last)),
        3.0,
        Paint()..color = lineColor,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 3.0;
    const gapLength = 3.0;
    final totalLength = (end - start).distance;
    if (totalLength <= 0) return;
    final direction = (end - start) / totalLength;
    double drawn = 0;
    while (drawn < totalLength) {
      final segEnd = math.min(drawn + dashLength, totalLength);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * segEnd,
        paint,
      );
      drawn = segEnd + gapLength;
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth, {
    bool centered = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final dx = centered ? offset.dx - tp.width / 2 : offset.dx;
    tp.paint(canvas, Offset(dx, offset.dy));
  }

  void _axisText(Canvas canvas, String text, Offset offset, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: axisLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _LossCurvePainter old) =>
      old.values != values ||
      old.totalEpochs != totalEpochs ||
      old.lineColor != lineColor ||
      old.markerIndex != markerIndex ||
      old.yFloor != yFloor;
}
