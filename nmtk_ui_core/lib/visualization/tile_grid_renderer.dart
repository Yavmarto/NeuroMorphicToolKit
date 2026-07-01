import 'dart:typed_data';
import 'package:flutter/material.dart';

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
  int neuronsForTile(int index) => (totalNeuronCount / tileCount).round();
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
                        painter: _TileGridPainter(frame: frame),
                      ),
                      if (hovered != null) _buildTilePopup(frame, hovered),
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

  Widget _buildTilePopup(TileActivityFrame frame, int tileIndex) {
    final row = tileIndex ~/ frame.tileCols;
    final col = tileIndex % frame.tileCols;
    return Positioned(
      left: 12,
      top: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC111827),
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                'Neurons: ~${frame.neuronsForTile(tileIndex)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Activity: ${frame.tileActivity[tileIndex].toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Concentration: ${frame.tileConcentration[tileIndex].toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
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

  _TileGridPainter({required this.frame});

  static const _lo = Color(0xFF1e3a8f); // blue: low activity
  static const _hi = Color(0xFFf0453c); // red: high activity
  static const _hot = Color(0xFFffe9a8); // pale glow for the hotspot

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

        final tilePaint = Paint()..color = Color.lerp(_lo, _hi, activity)!;
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
            ..color = _hot.withValues(alpha: 0.15 + activity * 0.5)
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
  bool shouldRepaint(covariant _TileGridPainter oldDelegate) => true;
}
