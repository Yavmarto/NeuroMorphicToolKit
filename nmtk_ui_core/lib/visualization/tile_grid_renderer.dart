import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// One frame of per-core-tile aggregated activity for the /viz-demo
/// chip-die view. `tileActivity[i]`/`tileConcentration[i]` describe tile
/// `i`, row-major: `i == row * tileCols + col`.
class TileActivityFrame {
  final int totalNeuronCount;
  final Float32List tileActivity;
  final Float32List tileConcentration;
  final int tileRows;
  final int tileCols;
  final double simulationTimeMs;

  TileActivityFrame({
    required this.totalNeuronCount,
    required this.tileActivity,
    required this.tileConcentration,
    required this.tileRows,
    required this.tileCols,
    required this.simulationTimeMs,
  });

  int get tileCount => tileRows * tileCols;

  /// Neurons mapped to tile [index] — an even split; the toolkit's chip
  /// targets don't expose per-core neuron counts finer than this average.
  int neuronsForTile(int index) => tileCount == 0 ? 0 : (totalNeuronCount / tileCount).round();
}

/// Renders [TileActivityFrame]s as a chip-die grid: one square tile per
/// core, colored blue (low activity) to red (high activity), with a soft
/// square glow inside each tile showing whether that core's activation
/// concentrates near its "core" (small, centered glow) or "edge" (glow
/// pushed toward the tile boundary) neuron indices. Supports hover/click
/// for a per-tile detail popup and pinch/drag zoom-pan.
class TileGridNeuronRenderer {
  final ValueNotifier<TileActivityFrame?> _frameNotifier = ValueNotifier(null);
  final ValueNotifier<int?> _hoveredTile = ValueNotifier(null);
  Size _size = Size.zero;

  void attach(Size size) {
    _size = size;
  }

  void pushFrame(TileActivityFrame frame) {
    _frameNotifier.value = frame;
  }

  int? _tileAtLocalPosition(Offset local, TileActivityFrame frame) {
    if (_size.width <= 0 || _size.height <= 0) return null;
    final tileW = _size.width / frame.tileCols;
    final tileH = _size.height / frame.tileRows;
    final col = (local.dx / tileW).floor();
    final row = (local.dy / tileH).floor();
    if (col < 0 || col >= frame.tileCols || row < 0 || row >= frame.tileRows) {
      return null;
    }
    final index = row * frame.tileCols + col;
    return index < frame.tileCount ? index : null;
  }

  Widget buildSurface(BuildContext context) {
    // Heat-map colors are resolved from the active Zeta theme here — this is
    // the only place in the render path with a BuildContext. They're threaded
    // into the painter below because CustomPainter.paint() has no context.
    final zetaColors = Zeta.of(context).colors;
    // The design system does not use gradients. We use a 10-step discrete scale
    // of a single primitive swatch (blue) to visualize quantitative intensity
    // using allowed tokens.
    final activityScale = [
      zetaColors.primitives.blue.shade10,
      zetaColors.primitives.blue.shade20,
      zetaColors.primitives.blue.shade30,
      zetaColors.primitives.blue.shade40,
      zetaColors.primitives.blue.shade50,
      zetaColors.primitives.blue.shade60,
      zetaColors.primitives.blue.shade70,
      zetaColors.primitives.blue.shade80,
      zetaColors.primitives.blue.shade90,
      zetaColors.primitives.blue.shade100,
    ];
    final hotspotColor = Colors.white; // concentration hotspot glow

    return ValueListenableBuilder<TileActivityFrame?>(
      valueListenable: _frameNotifier,
      builder: (context, frame, _) {
        if (frame == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ValueListenableBuilder<int?>(
          valueListenable: _hoveredTile,
          builder: (context, hovered, _) {
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 8.0,
              child: MouseRegion(
                onHover: (event) =>
                    _hoveredTile.value = _tileAtLocalPosition(event.localPosition, frame),
                onExit: (_) => _hoveredTile.value = null,
                child: GestureDetector(
                  onTapUp: (details) =>
                      _hoveredTile.value = _tileAtLocalPosition(details.localPosition, frame),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: _size,
                        painter: _TileGridPainter(
                          frame: frame,
                          activityScale: activityScale,
                          hotspotColor: hotspotColor,
                        ),
                      ),
                      if (hovered != null) _buildTilePopup(context, frame, hovered),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTilePopup(BuildContext context, TileActivityFrame frame, int tileIndex) {
    final row = tileIndex ~/ frame.tileCols;
    final col = tileIndex % frame.tileCols;
    final zeta = Zeta.of(context);
    // `surfaceDefaultInverse` is the design system's dark-surface token (see
    // ZetaSnackBar's default styling); `mainInverse` is the light foreground
    // token meant to sit on top of it (same pairing used by ZetaSnackBar and
    // ZetaTooltip), so this reproduces the old dark-card-with-white-text look
    // without any hardcoded hex values.
    final cardColor = zeta.colors.surfaceDefaultInverse.withValues(alpha: 0.9);
    final labelColor = zeta.colors.mainInverse;
    final subtleLabelStyle = zeta.textStyles.labelMedium.copyWith(
      color: labelColor.withValues(alpha: 0.7),
    );
    return Positioned(
      left: 12,
      top: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Core $tileIndex (row $row, col $col)',
                style: zeta.textStyles.bodyMedium.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Neurons: ~${frame.neuronsForTile(tileIndex)}',
                style: subtleLabelStyle,
              ),
              Text(
                'Activity: ${frame.tileActivity[tileIndex].toStringAsFixed(2)}',
                style: subtleLabelStyle,
              ),
              Text(
                'Concentration: ${frame.tileConcentration[tileIndex].toStringAsFixed(2)}',
                style: subtleLabelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void dispose() {
    _frameNotifier.dispose();
    _hoveredTile.dispose();
  }
}

class _TileGridPainter extends CustomPainter {
  final TileActivityFrame frame;

  // Resolved from the active Zeta theme by TileGridNeuronRenderer.buildSurface
  // (paint() has no BuildContext, so these must be threaded in via the
  // constructor rather than read here).
  final List<Color> activityScale;
  final Color hotspotColor;

  _TileGridPainter({
    required this.frame,
    required this.activityScale,
    required this.hotspotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tileW = size.width / frame.tileCols;
    final tileH = size.height / frame.tileRows;
    const gap = 2.0;

    for (var row = 0; row < frame.tileRows; row++) {
      for (var col = 0; col < frame.tileCols; col++) {
        final index = row * frame.tileCols + col;
        if (index >= frame.tileCount) continue;

        final activity = frame.tileActivity[index].clamp(0.0, 1.0);
        final concentration = frame.tileConcentration[index].clamp(0.0, 1.0);
        final rect = Rect.fromLTWH(
          col * tileW + gap / 2,
          row * tileH + gap / 2,
          tileW - gap,
          tileH - gap,
        );

        // Snap activity [0.0, 1.0] to an index in the 10-step discrete scale
        final scaleIndex = (activity * (activityScale.length - 1)).round();
        final tileColor = activityScale[scaleIndex];

        final tilePaint = Paint()..color = tileColor;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          tilePaint,
        );

        if (activity > 0.05) {
          // Soft square hotspot: shrinks toward the tile's center as
          // concentration -> 0 (core-heavy), grows toward the tile's
          // edges as concentration -> 1 (edge-heavy).
          final inset = rect.deflate(rect.shortestSide * (0.4 - concentration * 0.3));
          final hotspotPaint = Paint()
            ..color = hotspotColor.withValues(alpha: 0.15 + activity * 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawRRect(
            RRect.fromRectAndRadius(inset, const Radius.circular(3)),
            hotspotPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TileGridPainter oldDelegate) => !identical(oldDelegate.frame, frame);
}

/// One cascade node's tile-activity frame plus its display label, for the
/// /viz-demo topology-cascade mode. Wraps [TileActivityFrame] without
/// changing it — keeps this demo's contract self-contained.
class CascadeNodeFrame {
  final String nodeId;
  final String label;
  final TileActivityFrame tileFrame;

  CascadeNodeFrame({
    required this.nodeId,
    required this.label,
    required this.tileFrame,
  });
}

/// One frame across all cascade nodes, keyed by nodeId ("0".."12").
class CascadeFrame {
  final Map<String, CascadeNodeFrame> nodes;
  final double simulationTimeMs;

  CascadeFrame({required this.nodes, required this.simulationTimeMs});
}
