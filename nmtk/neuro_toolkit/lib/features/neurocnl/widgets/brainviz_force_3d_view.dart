import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/services/coactivation_correlation.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart'
    show spikeRateColor;
import 'package:neuro_toolkit/features/neurocnl/utils/force_directed_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_painter.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_perspective.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_reset_camera_button.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_2_5d_view.dart'
    show OrbitCamera;
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

export 'package:neuro_toolkit/features/neurocnl/widgets/brainviz_force_3d_painter.dart'
    show brainvizGlowDensityScale;

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
  Map<String, Map<String, double>>? _cachedCorrelationMatrix;
  List<({String a, String b, double strength})>? _cachedCorrelationPairs;
  Set<String>? _cachedLabelNodeIds;
  String? _cachedLabelSelection;
  int? _cachedLabelMaxLabels;
  Map<String, double>? _cachedLabelSignificance;

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
      _cachedLabelNodeIds = null;
      _cachedLabelSignificance = null;
    }
    if (widget.correlationMatrix != oldWidget.correlationMatrix) {
      _layout?.setCorrelations(widget.correlationMatrix);
      _cachedCorrelationMatrix = null;
      _cachedCorrelationPairs = null;
    }
    if (!mapEquals(widget.activity, oldWidget.activity)) {
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

  static const double _activityEpsilon = 1e-4;

  bool _activitySmoothingActive() {
    final target = widget.activity;
    if (target == null) return false;
    for (final entry in target.entries) {
      final current = _smoothedActivity[entry.key] ?? 0.0;
      if ((entry.value - current).abs() > _activityEpsilon) {
        return true;
      }
    }
    return false;
  }

  bool get _wantsAnimation =>
      widget.animate &&
      (_activitySmoothingActive() || (_layout?.isSettled == false));

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
    var needsRepaint = false;
    final target = widget.activity;
    if (target != null) {
      for (final entry in target.entries) {
        final current = _smoothedActivity[entry.key] ?? 0.0;
        final next = current + (entry.value - current) * _activityLerp;
        if ((next - current).abs() > _activityEpsilon) {
          needsRepaint = true;
        }
        _smoothedActivity[entry.key] = next;
      }
    }
    if (_layout != null && !_layout!.isSettled) {
      _layout!.advance();
      needsRepaint = true;
    }
    if (needsRepaint) {
      setState(() {});
    }
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
    final projection = BrainvizPerspective(
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

  List<({String a, String b, double strength})> _correlationPairsFor(
    Map<String, Map<String, double>> matrix,
  ) {
    if (_cachedCorrelationPairs != null &&
        (identical(matrix, _cachedCorrelationMatrix) ||
            mapEquals(matrix, _cachedCorrelationMatrix))) {
      return _cachedCorrelationPairs!;
    }
    _cachedCorrelationMatrix = matrix;
    return _cachedCorrelationPairs = correlationPairs(matrix);
  }

  Set<String> _labelNodeIds() {
    final significance = _nodeSignificance();
    final selected = _selectedId;
    if (_cachedLabelNodeIds != null &&
        selected == _cachedLabelSelection &&
        widget.maxLabels == _cachedLabelMaxLabels &&
        mapEquals(significance, _cachedLabelSignificance)) {
      return _cachedLabelNodeIds!;
    }
    final ranked = significance.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ids = ranked.take(widget.maxLabels).map((entry) => entry.key).toSet();
    if (selected != null) ids.add(selected);
    _cachedLabelSignificance = Map<String, double>.from(significance);
    _cachedLabelSelection = selected;
    _cachedLabelMaxLabels = widget.maxLabels;
    return _cachedLabelNodeIds = ids;
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
    final pairs = _correlationPairsFor(matrix);
    final labelIds = _labelNodeIds();
    final radii = _nodeRadii();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final projection = BrainvizPerspective(
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
                          painter: BrainvizForce3DPainter(
                            graph: widget.graph,
                            positions: layout.positions,
                            positionsRevision: layout.positionsRevision,
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
                    child: BrainvizResetCameraButton(
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
