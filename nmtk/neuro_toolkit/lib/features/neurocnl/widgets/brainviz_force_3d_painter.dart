import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/glow_sprite.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_perspective.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart'
    show kCoactivationClusterPalette;

/// Screen-density falloff for additive node glow — keeps packed clusters from
/// saturating to white while leaving sparse nodes bright.
double brainvizGlowDensityScale(int nearbyActiveCount) =>
    1.0 / math.sqrt(1.0 + nearbyActiveCount * 0.35);

/// Custom painter for the 3D force-directed brainviz scene.
class BrainvizForce3DPainter extends CustomPainter {
  BrainvizForce3DPainter({
    required this.graph,
    required this.positions,
    required this.positionsRevision,
    required this.projection,
    required this.activity,
    this.pulse = const <String, double>{},
    this.drawWires = true,
    this.ringActivity = false,
    this.elapsedSeconds = 0.0,
    required this.radii,
    required this.correlationPairs,
    required this.nodeClusterIndices,
    required this.labelNodeIds,
    required this.selectedId,
    required this.activityColorOf,
    required this.labelStyle,
  });

  final CanvasGraph graph;
  final Map<String, Vec3> positions;
  final int positionsRevision;
  final BrainvizPerspective projection;
  final Map<String, double> activity;

  /// Per-node glow multiplier from the view's activity pulse. Empty when the
  /// scene is static (animation disabled or nothing firing).
  final Map<String, double> pulse;

  /// Draw co-firing wires. Off for variants that explain co-firing through
  /// motion or activity alone.
  final bool drawWires;

  /// Draw an expanding ring from each firing node, so nodes that fire together
  /// visibly ring in step.
  final bool ringActivity;

  /// Animation clock in seconds, used to phase [ringActivity].
  final double elapsedSeconds;

  final Map<String, double> radii;
  final List<({String a, String b, double strength})> correlationPairs;
  final Map<String, int>? nodeClusterIndices;
  final Set<String> labelNodeIds;
  final String? selectedId;
  final Color Function(double rate) activityColorOf;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);

    final projectedNodes =
        <String, ({Offset screen, double depth, double scale})>{};
    for (final node in graph.nodes) {
      final position = positions[node.id];
      if (position == null) continue;
      projectedNodes[node.id] = projection.project(position);
    }

    if (drawWires) {
      final sortedPairs = correlationPairs.toList()
        ..sort((a, b) {
          final da = _pairDepth(a, projectedNodes);
          final db = _pairDepth(b, projectedNodes);
          return da.compareTo(db);
        });
      for (final pair in sortedPairs) {
        _paintCorrelationEdge(canvas, pair, projectedNodes);
      }
    }

    final glowDensityScales = _computeGlowDensityScales(projectedNodes);

    final sortedNodes = graph.nodes.toList()
      ..sort((a, b) {
        final da = projectedNodes[a.id]?.depth ?? 0;
        final db = projectedNodes[b.id]?.depth ?? 0;
        return da.compareTo(db);
      });
    for (final node in sortedNodes) {
      _paintNode(
        canvas,
        node,
        projectedNodes[node.id],
        glowDensityScales[node.id] ?? 1.0,
      );
    }
  }

  /// Attenuates per-node glow when many active nodes overlap on screen.
  ///
  /// ponytail: O(n²) neighbor scan per frame; upgrade path: uniform grid if
  /// n>2k active nodes.
  Map<String, double> _computeGlowDensityScales(
    Map<String, ({Offset screen, double depth, double scale})> projected,
  ) {
    const screenNeighborRadius = 14.0;
    final activeIds = graph.nodes
        .map((node) => node.id)
        .where((id) => (activity[id] ?? 0) > 0.02 && projected.containsKey(id))
        .toList(growable: false);

    final scales = <String, double>{};
    for (final id in activeIds) {
      final center = projected[id]!.screen;
      final radius =
          screenNeighborRadius * projected[id]!.scale.clamp(0.35, 1.4);
      var nearby = 0;
      for (final otherId in activeIds) {
        if (otherId == id) continue;
        if ((center - projected[otherId]!.screen).distance < radius) {
          nearby++;
        }
      }
      scales[id] = brainvizGlowDensityScale(nearby);
    }
    return scales;
  }

  double _pairDepth(
    ({String a, String b, double strength}) pair,
    Map<String, ({Offset screen, double depth, double scale})> projected,
  ) {
    final da = projected[pair.a]?.depth ?? 0;
    final db = projected[pair.b]?.depth ?? 0;
    return (da + db) / 2;
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E18), Color(0xFF151B2B)],
        ).createShader(rect),
    );
    final fog = ui.Gradient.radial(
      Offset(size.width / 2, size.height * 0.42),
      size.longestSide * 0.55,
      [
        AppTheme.primary.withValues(alpha: 0.08),
        Colors.transparent,
        AppTheme.background.withValues(alpha: 0.55),
      ],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = fog);
  }

  void _paintCorrelationEdge(
    Canvas canvas,
    ({String a, String b, double strength}) pair,
    Map<String, ({Offset screen, double depth, double scale})> projected,
  ) {
    final from = projected[pair.a];
    final to = projected[pair.b];
    if (from == null || to == null) return;
    final depth = (from.depth + to.depth) / 2;
    final depthAlpha = (0.25 + 0.65 * (depth / 400)).clamp(0.2, 1.0);
    final alpha = (0.15 + 0.75 * pair.strength * depthAlpha).clamp(0.08, 0.95);
    final color = Color.lerp(
      AppTheme.primaryDim,
      AppTheme.primary,
      pair.strength,
    )!;
    final stroke = (0.6 + 2.4 * pair.strength) * from.scale.clamp(0.4, 2.0);
    canvas.drawLine(
      from.screen,
      to.screen,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.35)
        ..strokeWidth = stroke + 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      from.screen,
      to.screen,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintNode(
    Canvas canvas,
    CanvasNode node,
    ({Offset screen, double depth, double scale})? projected,
    double glowDensityScale,
  ) {
    if (projected == null) return;
    final center = projected.screen;
    final baseRadius =
        (radii[node.id] ?? 8.0) * projected.scale.clamp(0.35, 1.4);
    final act = (activity[node.id] ?? 0.0).clamp(0.0, 1.0);
    final depthAlpha = (0.35 + 0.65 * (projected.depth / 400)).clamp(0.25, 1.0);
    final clusterIndex = nodeClusterIndices?[node.id];
    final baseColor = clusterIndex != null
        ? kCoactivationClusterPalette[clusterIndex %
              kCoactivationClusterPalette.length]
        : AppTheme.primary;
    final shaded = Color.lerp(
      AppTheme.surfaceVariant,
      baseColor,
      0.4 + 0.6 * depthAlpha,
    )!;

    if (act > 0.02) {
      final pulseScale = pulse[node.id] ?? 1.0;
      final pulsedAct = (act * pulseScale).clamp(0.0, 1.0);
      final glowColor = activityColorOf(act);
      final glowRadius = baseRadius + 3 + 7 * pulsedAct;
      final highlight = node.id == selectedId || act >= 0.75;
      canvas.drawCircle(
        center,
        glowRadius,
        GlowSprite.radial(
          center: center,
          radius: glowRadius,
          color: glowColor,
          intensity: (0.45 + 0.55 * pulsedAct) * glowDensityScale,
          blendMode: highlight ? BlendMode.plus : BlendMode.srcOver,
        ),
      );

      // One shared clock drives every ring, so neurons that fire at the same
      // time visibly ring in step. Quiet neurons emit nothing.
      if (ringActivity) {
        final phase = (elapsedSeconds * 1.2) % 1.0;
        final ringRadius = baseRadius + 2 + 22 * phase;
        final ringAlpha = ((1.0 - phase) * (0.3 + 0.6 * act) * depthAlpha)
            .clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          ringRadius,
          Paint()
            ..color = glowColor.withValues(alpha: ringAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4 + 2.2 * act,
        );
      }
    }

    canvas.drawCircle(
      center,
      baseRadius + 3,
      Paint()
        ..shader = ui.Gradient.radial(center, baseRadius + 3, [
          shaded.withValues(alpha: 0.18 * depthAlpha),
          shaded.withValues(alpha: 0.0),
        ]),
    );

    if (node.id == selectedId) {
      canvas.drawCircle(
        center,
        baseRadius + 5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final highlight = center + Offset(-baseRadius * 0.28, -baseRadius * 0.32);
    // Quiet nodes stay visible but dim; a firing node reads clearly brighter.
    final activityOpacity = 0.55 + 0.45 * act;
    canvas.drawCircle(
      center,
      baseRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          highlight,
          baseRadius * 1.5,
          [
            Color.lerp(
              shaded,
              Colors.white,
              0.35,
            )!.withValues(alpha: depthAlpha * activityOpacity),
            shaded.withValues(alpha: depthAlpha * activityOpacity),
            Color.lerp(
              shaded,
              AppTheme.background,
              0.45,
            )!.withValues(alpha: depthAlpha * activityOpacity),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    if (labelNodeIds.contains(node.id)) {
      _paintLabel(canvas, node, center, baseRadius, depthAlpha);
    }
  }

  void _paintLabel(
    Canvas canvas,
    CanvasNode node,
    Offset center,
    double radius,
    double depthAlpha,
  ) {
    final label = node.label ?? node.id;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: labelStyle.copyWith(
          color: labelStyle.color?.withValues(alpha: depthAlpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);

    final top = center.dy + radius + 5;
    final background = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        center.dx - painter.width / 2 - 5,
        top - 2,
        painter.width + 10,
        painter.height + 4,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      background,
      Paint()..color = AppTheme.background.withValues(alpha: 0.78 * depthAlpha),
    );
    painter.paint(canvas, Offset(center.dx - painter.width / 2, top));
  }

  @override
  bool shouldRepaint(covariant BrainvizForce3DPainter old) =>
      old.graph != graph ||
      old.positionsRevision != positionsRevision ||
      old.projection.camera != projection.camera ||
      old.projection.size != projection.size ||
      old.projection.sceneScale != projection.sceneScale ||
      !mapEquals(old.activity, activity) ||
      !mapEquals(old.pulse, pulse) ||
      !mapEquals(old.radii, radii) ||
      !_sameCorrelationPairs(old.correlationPairs, correlationPairs) ||
      old.drawWires != drawWires ||
      old.ringActivity != ringActivity ||
      old.elapsedSeconds != elapsedSeconds ||
      old.selectedId != selectedId ||
      !setEquals(old.labelNodeIds, labelNodeIds) ||
      old.nodeClusterIndices != nodeClusterIndices;
}

bool _sameCorrelationPairs(
  List<({String a, String b, double strength})> a,
  List<({String a, String b, double strength})> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left.a != right.a ||
        left.b != right.b ||
        left.strength != right.strength) {
      return false;
    }
  }
  return true;
}
