import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/services/coactivation_correlation.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart'
    show spikeRateColor;
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/glow_sprite.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart'
    show OrbitCamera, kCoactivationClusterPalette;
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

/// Screen-density falloff for additive node glow — keeps packed clusters from
/// saturating to white while leaving sparse nodes bright.
double brainvizGlowDensityScale(int nearbyActiveCount) =>
    1.0 / math.sqrt(1.0 + nearbyActiveCount * 0.35);

/// True 3D force-directed brainviz for per-neuron raster playback.
///
/// Correlation pairs drive both layout attraction and visible edges; node
/// radius and emissive glow scale with activity and correlation degree; only
/// the top few significant nodes (plus the selection) receive labels.
class BrainvizForce3DView extends StatefulWidget {
  const BrainvizForce3DView({
    super.key,
    required this.graph,
    this.activity,
    this.correlationMatrix,
    this.nodeClusterIndices,
    this.selectedNodeId,
    this.onNodeSelected,
    this.animate = true,
    this.padding = 32,
    this.maxLabels = 8,
  });

  final CanvasGraph graph;
  final Map<String, double>? activity;
  final Map<String, Map<String, double>>? correlationMatrix;
  final Map<String, int>? nodeClusterIndices;
  final String? selectedNodeId;
  final ValueChanged<CanvasNode?>? onNodeSelected;
  final bool animate;
  final double padding;
  final int maxLabels;

  @override
  State<BrainvizForce3DView> createState() => _BrainvizForce3DViewState();
}

class _BrainvizForce3DViewState extends State<BrainvizForce3DView>
    with SingleTickerProviderStateMixin {
  CorrelationForceBrainvizLayout3D? _layout;
  Ticker? _ticker;
  String? _internalSelectedId;
  OrbitCamera _camera = OrbitCamera.identity;
  double _lastScale = 1.0;
  final Map<String, double> _smoothedActivity = <String, double>{};

  static const double _activityLerp = 0.22;
  static const double _hitSlop = 28.0;

  @override
  void initState() {
    super.initState();
    _rebuildLayout();
    _restartTickerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant BrainvizForce3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_topologyChanged(oldWidget.graph, widget.graph)) {
      _layout?.updateGraph(widget.graph);
      _smoothedActivity.clear();
    }
    if (widget.correlationMatrix != oldWidget.correlationMatrix) {
      _layout?.setCorrelations(widget.correlationMatrix);
    }
    if (widget.activity != oldWidget.activity) {
      _syncActivityTargets();
    }
    _restartTickerIfNeeded();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _rebuildLayout() {
    _layout = CorrelationForceBrainvizLayout3D(widget.graph);
    _layout!.setCorrelations(widget.correlationMatrix);
    _syncActivityTargets();
  }

  void _syncActivityTargets() {
    final target = widget.activity;
    if (target == null) {
      _smoothedActivity.clear();
      return;
    }
    for (final node in widget.graph.nodes) {
      _smoothedActivity.putIfAbsent(node.id, () => 0.0);
    }
    _smoothedActivity.removeWhere(
      (id, _) => !widget.graph.nodes.any((node) => node.id == id),
    );
  }

  bool _topologyChanged(CanvasGraph a, CanvasGraph b) {
    if (identical(a, b)) return false;
    if (a.nodes.length != b.nodes.length) return true;
    for (var i = 0; i < a.nodes.length; i++) {
      if (a.nodes[i].id != b.nodes[i].id) return true;
    }
    return false;
  }

  bool get _wantsAnimation =>
      widget.animate &&
      (widget.activity != null || (_layout?.isSettled == false));

  void _restartTickerIfNeeded() {
    if (!_wantsAnimation) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
      return;
    }
    _ticker ??= createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final target = widget.activity;
    if (target != null) {
      for (final entry in target.entries) {
        final current = _smoothedActivity[entry.key] ?? 0.0;
        _smoothedActivity[entry.key] =
            current + (entry.value - current) * _activityLerp;
      }
    }
    _layout?.advance();
    setState(() {});
    if (!_wantsAnimation) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
    }
  }

  String? get _selectedId => widget.selectedNodeId ?? _internalSelectedId;

  void _selectNode(CanvasNode? node) {
    final id = node?.id;
    final current = _selectedId;
    final next = id != null && id == current ? null : node;
    if (widget.selectedNodeId == null) {
      setState(() => _internalSelectedId = next?.id);
    }
    widget.onNodeSelected?.call(next);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.focalPointDelta;
    final scale = details.scale;
    setState(() {
      if (details.pointerCount >= 2) {
        _camera = _camera.zoomBy(scale / _lastScale);
      } else {
        _camera = _camera.orbit(delta.dx, delta.dy);
      }
    });
    _lastScale = scale;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _lastScale = 1.0;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = math.exp(-event.scrollDelta.dy * 0.0015);
    setState(() => _camera = _camera.zoomBy(factor));
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    final node = _hitTestNode(details.localPosition, size);
    _selectNode(node);
  }

  CanvasNode? _hitTestNode(Offset local, Size size) {
    final layout = _layout;
    if (layout == null) return null;
    final projection = _BrainvizPerspective(
      size: size,
      camera: _camera,
      sceneScale: layout.maxExtent(),
    );
    final radii = _nodeRadii();
    CanvasNode? closest;
    var closestDistance = _hitSlop;
    for (final node in widget.graph.nodes) {
      final position = layout.positions[node.id];
      if (position == null) continue;
      final projected = projection.project(position);
      final radius = radii[node.id] ?? 8.0;
      final distance = (projected.screen - local).distance;
      if (distance < closestDistance + radius) {
        closestDistance = distance;
        closest = node;
      }
    }
    return closest;
  }

  Map<String, double> _nodeSignificance() {
    final matrix = widget.correlationMatrix ?? const {};
    final degrees = correlationDegrees(matrix);
    final maxDegree = degrees.values.fold<int>(0, math.max);
    final result = <String, double>{};
    for (final node in widget.graph.nodes) {
      final activity = (_smoothedActivity[node.id] ?? 0.0).clamp(0.0, 1.0);
      final degreeNorm = maxDegree <= 0
          ? 0.0
          : (degrees[node.id] ?? 0) / maxDegree;
      result[node.id] = math.max(activity, degreeNorm);
    }
    return result;
  }

  Map<String, double> _nodeRadii() {
    final significance = _nodeSignificance();
    return significance.map(
      (id, value) => MapEntry(id, 2.0 + 6.0 * value.clamp(0.0, 1.0)),
    );
  }

  Set<String> _labelNodeIds() {
    final significance = _nodeSignificance();
    final ranked = significance.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ids = ranked.take(widget.maxLabels).map((entry) => entry.key).toSet();
    final selected = _selectedId;
    if (selected != null) ids.add(selected);
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    if (layout == null || widget.graph.nodes.isEmpty) {
      return const Center(child: Text('No neurons to visualize.'));
    }

    final zeta = Zeta.of(context);
    final tokens = NmtkShellTokens.of(context);
    final matrix = widget.correlationMatrix ?? const {};
    final pairs = correlationPairs(matrix);
    final labelIds = _labelNodeIds();
    final radii = _nodeRadii();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final projection = _BrainvizPerspective(
          size: size,
          camera: _camera,
          sceneScale: layout.maxExtent(),
        );

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerSignal: _handlePointerSignal,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _handleTapUp(details, size),
                      onScaleStart: _handleScaleStart,
                      onScaleUpdate: _handleScaleUpdate,
                      onScaleEnd: _handleScaleEnd,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: size,
                          painter: _BrainvizForce3DPainter(
                            graph: widget.graph,
                            positions: layout.positions,
                            projection: projection,
                            activity: _smoothedActivity,
                            radii: radii,
                            correlationPairs: pairs,
                            nodeClusterIndices: widget.nodeClusterIndices,
                            labelNodeIds: labelIds,
                            selectedId: _selectedId,
                            activityColorOf: (rate) =>
                                spikeRateColor(rate, zeta.colors),
                            labelStyle: zeta.textStyles.labelSmall.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_camera.isIdentity)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _ResetCameraButton(
                      onPressed: () =>
                          setState(() => _camera = OrbitCamera.identity),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResetCameraButton extends StatelessWidget {
  const _ResetCameraButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.background.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(tokens.radiusChip),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                ZetaIcons.refresh,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Reset view',
                style: Zeta.of(context).textStyles.labelSmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrainvizPerspective {
  const _BrainvizPerspective({
    required this.size,
    required this.camera,
    required this.sceneScale,
  });

  final Size size;
  final OrbitCamera camera;
  final double sceneScale;
  static const double _focalLength = 520;

  Vec3 _rotate(Vec3 point) {
    if (camera.isIdentity) return point;
    final cosYaw = math.cos(camera.yaw);
    final sinYaw = math.sin(camera.yaw);
    final x1 = point.x * cosYaw + point.z * sinYaw;
    final z1 = -point.x * sinYaw + point.z * cosYaw;
    final cosPitch = math.cos(camera.pitch);
    final sinPitch = math.sin(camera.pitch);
    final y1 = point.y * cosPitch - z1 * sinPitch;
    final z2 = point.y * sinPitch + z1 * cosPitch;
    return Vec3(x1, y1, z2);
  }

  ({Offset screen, double depth, double scale}) project(Vec3 point) {
    final normalized = point * (220 / math.max(sceneScale, 1.0));
    final rotated = _rotate(normalized);
    final perspective = _focalLength / (_focalLength - rotated.z);
    final center = Offset(size.width / 2, size.height / 2);
    final projected = Offset(
      center.dx + rotated.x * perspective * camera.zoom,
      center.dy + rotated.y * perspective * camera.zoom,
    );
    return (
      screen: projected,
      depth: -rotated.z,
      scale: perspective * camera.zoom,
    );
  }
}

class _BrainvizForce3DPainter extends CustomPainter {
  _BrainvizForce3DPainter({
    required this.graph,
    required this.positions,
    required this.projection,
    required this.activity,
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
  final _BrainvizPerspective projection;
  final Map<String, double> activity;
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

    final sortedPairs = correlationPairs.toList()
      ..sort((a, b) {
        final da = _pairDepth(a, projectedNodes);
        final db = _pairDepth(b, projectedNodes);
        return da.compareTo(db);
      });
    for (final pair in sortedPairs) {
      _paintCorrelationEdge(canvas, pair, projectedNodes);
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
      final glowColor = activityColorOf(act);
      final glowRadius = baseRadius + 3 + 10 * act;
      final highlight = node.id == selectedId || act >= 0.75;
      canvas.drawCircle(
        center,
        glowRadius,
        GlowSprite.radial(
          center: center,
          radius: glowRadius,
          color: glowColor,
          intensity: (0.45 + 0.55 * act) * glowDensityScale,
          blendMode: highlight ? BlendMode.plus : BlendMode.srcOver,
        ),
      );
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
            )!.withValues(alpha: depthAlpha),
            shaded.withValues(alpha: depthAlpha),
            Color.lerp(
              shaded,
              AppTheme.background,
              0.45,
            )!.withValues(alpha: depthAlpha),
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
  bool shouldRepaint(covariant _BrainvizForce3DPainter old) =>
      old.graph != graph ||
      old.positions != positions ||
      old.projection.camera != projection.camera ||
      old.activity != activity ||
      old.radii != radii ||
      old.correlationPairs != correlationPairs ||
      old.selectedId != selectedId ||
      old.labelNodeIds != labelNodeIds;
}
