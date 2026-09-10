import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart'
    show spikeRateColor;
import 'package:neuro_toolkit/features/neurocnl/utils/globe_layout.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/glow_sprite.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

/// 2.5D network renderer over a [CanvasGraph].
///
/// The graph is laid out client-side by [GlobeLayout] (AIS-OS-style spherical
/// equal-area placement grouped by layer type) and painted by
/// [Network25DPainter]. There is no 3D or WebGL dependency: depth is simulated
/// on a 2D canvas with a perspective projection (nearer nodes are larger and
/// pushed outward from the focal point), z-sorted painting, per-node depth
/// shading, and a depth fog. It is the same `CustomPainter` + `Paint.shader`
/// rendering family as `network_graph_view.dart` and the
/// `fragment_shader_renderer.dart` shaders.
///
/// Granularity is components/layers — tens of nodes — not raw neurons. Live
/// per-node activity ([activity]) drives node glow; optional [edgeStrengths]
/// (edge id → co-activation correlation, from the CEL-140 correlation engine)
/// drives edge emphasis.
///
/// The view also owns an [OrbitCamera]: dragging empty space rotates the whole
/// scene, and the scroll wheel or a two-finger pinch zooms it. Orbiting is a
/// pure re-projection — it never re-runs [GlobeLayout], so it stays cheap on
/// every frame. Dragging a node still moves that node, and tapping
/// still selects it. A "Reset view" affordance appears once the camera moves.
///
/// The widget is intentionally provider-free so it can be unit/widget tested
/// with plain constructor arguments; the Studio wiring (CEL-141) supplies the
/// graph, activity, and correlation from Riverpod.
class Network25DView extends StatefulWidget {
  const Network25DView({
    super.key,
    required this.graph,
    this.activity,
    this.depths,
    this.edgeStrengths,
    this.nirTypes,
    this.selectedNodeId,
    this.onNodeSelected,
    this.animate = true,
    this.showChrome = true,
    this.padding = 64.0,
    this.nodeClusterIndices,
  });

  /// Topology to lay out and draw.
  final CanvasGraph graph;

  /// Node id → spike rate in `0..1`. Drives the node activity glow. Null hides
  /// activity entirely (review mode before playback data exists).
  final Map<String, double>? activity;

  /// Optional depth override in `0..1` (`1` nearest). When null, depth is
  /// derived from topology by [computeNetworkDepths].
  final Map<String, double>? depths;

  /// Optional edge id → co-activation correlation in `[-1, 1]`. Edges without
  /// an entry render neutral. Positive values brighten and thicken the wire.
  final Map<String, double>? edgeStrengths;

  /// Optional NIR type registry (`nirNodeTypeMapProvider`) so nodes take their
  /// type's category accent and globe sectors. Falls back to
  /// `node.metadata['category']`.
  final Map<String, NirNodeType>? nirTypes;

  /// Optional node id → co-active cluster index. When set, clustered nodes use
  /// a distinct accent instead of their layer-type color; singletons are omitted.
  final Map<String, int>? nodeClusterIndices;

  /// Controlled selection. When null the view manages its own selection.
  final String? selectedNodeId;

  /// Called when the selected node changes. The argument is null when the tap
  /// clears the selection.
  final ValueChanged<CanvasNode?>? onNodeSelected;

  /// Whether to run the relax/pulse ticker. Tests set this false.
  final bool animate;

  /// Whether to draw the stat chips, depth legend, and selection panel.
  final bool showChrome;

  /// Padding kept free on every edge when fitting the layout to the viewport.
  final double padding;

  @override
  State<Network25DView> createState() => _Network25DViewState();
}

class _Network25DViewState extends State<Network25DView>
    with SingleTickerProviderStateMixin {
  late GlobeNetworkLayout _layout;
  Ticker? _ticker;
  String? _internalSelectedId;
  String? _draggingNodeId;

  /// Orientation/zoom of the virtual camera. Changed by drag/scroll/pinch
  /// without ever touching [_layout], so orbiting is a cheap re-projection.
  OrbitCamera _camera = OrbitCamera.identity;

  /// Cumulative pinch scale at the last update, so the camera only applies the
  /// per-frame ratio instead of the whole gesture's scale.
  double _lastScale = 1.0;

  final Map<String, double> _smoothedActivity = <String, double>{};

  static const double _nodeHitRadius = 34.0;
  static const double _activityLerp = 0.2;

  @override
  void initState() {
    super.initState();
    _rebuildLayout();
    _restartTickerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant Network25DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_topologyChanged(oldWidget.graph, widget.graph)) {
      _layout.updateGraph(
        widget.graph,
        categoryOf: GlobeNetworkLayout.categoryResolver(widget.nirTypes),
      );
      _smoothedActivity.clear();
    }
    if (widget.activity != oldWidget.activity ||
        widget.depths != oldWidget.depths) {
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
    _layout = GlobeNetworkLayout(
      widget.graph,
      categoryOf: GlobeNetworkLayout.categoryResolver(widget.nirTypes),
    );
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
    if (a.nodes.length != b.nodes.length || a.edges.length != b.edges.length) {
      return true;
    }
    for (var i = 0; i < a.nodes.length; i++) {
      if (a.nodes[i].id != b.nodes[i].id) return true;
    }
    for (var i = 0; i < a.edges.length; i++) {
      if (a.edges[i].sourceNodeId != b.edges[i].sourceNodeId ||
          a.edges[i].targetNodeId != b.edges[i].targetNodeId) {
        return true;
      }
    }
    return false;
  }

  // ── Ticker ─────────────────────────────────────────────────────────────────

  bool get _wantsAnimation => widget.animate && widget.activity != null;

  void _restartTickerIfNeeded() {
    if (!_wantsAnimation) {
      _stopTicker();
      return;
    }
    _ticker ??= createTicker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
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

    setState(() {});

    if (!_wantsAnimation) {
      _stopTicker();
    }
  }

  // ── Interaction ────────────────────────────────────────────────────────────

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

  /// A drag that starts on a node moves that node; a drag that starts on empty
  /// space orbits the camera. A second pointer turns the gesture into a pinch
  /// zoom. [ScaleStartDetails.localFocalPoint] is used so the hit test matches
  /// the same coordinate space as the tap handler.
  void _handleScaleStart(ScaleStartDetails details, _FitTransform fit) {
    _lastScale = 1.0;
    final node = _hitTestNode(details.localFocalPoint, fit);
    if (node != null) {
      setState(() => _draggingNodeId = node.id);
      _layout.pin(node.id, _layout.positions[node.id] ?? Offset.zero);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, _FitTransform fit) {
    final id = _draggingNodeId;
    if (id != null && details.pointerCount <= 1) {
      final current = _layout.positions[id];
      if (current != null) {
        final next = fit.invert(fit.apply(current) + details.focalPointDelta);
        _layout.pin(id, next);
        setState(() {});
      }
      return;
    }

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
    if (_draggingNodeId != null) {
      setState(() => _draggingNodeId = null);
    }
  }

  /// Mouse wheel / trackpad scroll zoom. Exponential so each notch is a
  /// constant ratio regardless of the current zoom.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = math.exp(-event.scrollDelta.dy * 0.0015);
    setState(() => _camera = _camera.zoomBy(factor));
  }

  void _resetCamera() {
    if (_camera.isIdentity) return;
    setState(() => _camera = OrbitCamera.identity);
  }

  void _handleTapUp(TapUpDetails details, _FitTransform fit) {
    final node = _hitTestNode(details.localPosition, fit);
    _selectNode(node);
  }

  CanvasNode? _hitTestNode(Offset local, _FitTransform fit) {
    final depths = _effectiveDepths();
    final projection = Network25DProjection(size: fit.size, camera: _camera);
    CanvasNode? closest;
    var closestDistance = _nodeHitRadius;
    for (final node in widget.graph.nodes) {
      final position = _layout.positions[node.id];
      if (position == null) continue;
      final depth = depths[node.id] ?? 0.5;
      final projected = projection.project(fit.apply(position), depth);
      final distance = (projected - local).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = node;
      }
    }
    return closest;
  }

  Map<String, double> _effectiveDepths() => widget.depths ?? _layout.depths;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.graph.nodes.isEmpty) {
      return _buildEmptyState(context);
    }

    final zeta = Zeta.of(context);
    final tokens = NmtkShellTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final fit = _FitTransform.forLayout(
          layout: _layout,
          size: size,
          padding: widget.padding,
        );
        final fitted = <String, Offset>{
          for (final entry in _layout.positions.entries)
            entry.key: fit.apply(entry.value),
        };
        final depths = _effectiveDepths();

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
                      onTapUp: (details) => _handleTapUp(details, fit),
                      onScaleStart: (details) =>
                          _handleScaleStart(details, fit),
                      onScaleUpdate: (details) =>
                          _handleScaleUpdate(details, fit),
                      onScaleEnd: _handleScaleEnd,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: size,
                          painter: Network25DPainter(
                            graph: widget.graph,
                            positions: fitted,
                            depths: depths,
                            projection: Network25DProjection(
                              size: size,
                              camera: _camera,
                            ),
                            activity: _smoothedActivity,
                            edgeStrengths: widget.edgeStrengths,
                            nirTypes: widget.nirTypes,
                            nodeClusterIndices: widget.nodeClusterIndices,
                            selectedId: _selectedId,
                            nodeLabelStyle: zeta.textStyles.labelSmall.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            secondaryLabelStyle: zeta.textStyles.labelSmall
                                .copyWith(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                ),
                            activityColorOf: (rate) =>
                                spikeRateColor(rate, zeta.colors),
                            selectionColor: zeta.colors.mainInverse,
                            gridColor: zeta.colors.borderSubtle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.showChrome) ...[
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatChips(),
                        if (_camera.isIdentity) ...[
                          const SizedBox(height: 8),
                          _buildOrbitHint(),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildDepthLegend(),
                        if (!_camera.isIdentity) ...[
                          const SizedBox(height: 8),
                          _buildResetCameraButton(),
                        ],
                      ],
                    ),
                  ),
                  if (widget.edgeStrengths != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _buildProxyDisclosure(),
                    ),
                  if (_selectedNode != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: widget.edgeStrengths != null ? 64 : 12,
                      child: _buildNodePanel(_selectedNode!),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  CanvasNode? get _selectedNode {
    final id = _selectedId;
    if (id == null) return null;
    for (final node in widget.graph.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            size: 44,
            color: AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Add layers to the model to see the network.',
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          '${widget.graph.nodes.length} layers',
        ),
        _chip(
          ZetaIcons.arrow_forward,
          '${widget.graph.edges.length} connections',
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusChip,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Zeta.of(context).textStyles.labelSmall.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrbitHint() {
    return _chip(ZetaIcons.sync, 'Drag to orbit · scroll to zoom');
  }

  Widget _buildResetCameraButton() {
    final tokens = NmtkShellTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusChip),
        onTap: _resetCamera,
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

  Widget _buildDepthLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'far',
            style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 64,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [AppTheme.surfaceVariant, AppTheme.primary],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'near',
            style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
              color: AppTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxyDisclosure() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        'Wire brightness reflects co-activation (a layer-level proxy for '
        'Hebbian correlation, not per-neuron).',
        style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
          color: AppTheme.textSecondary,
          fontSize: 10,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildNodePanel(CanvasNode node) {
    final category =
        widget.nirTypes?[node.nirType ?? node.componentId]?.category ??
        node.metadata['category']?.toString() ??
        'utility';
    final color = canvasCategoryColor(category);
    final activity = widget.activity?[node.id];
    final depth = _effectiveDepths()[node.id] ?? 0.5;

    final rows = <(String, String)>[
      ('Type', node.nirType ?? node.componentId),
      ('Depth', depth.toStringAsFixed(2)),
      if (activity != null) ('Activity', activity.toStringAsFixed(2)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 3, right: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  node.label ?? node.componentId,
                  style: Zeta.of(context).textStyles.labelMedium.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rows.map((row) => '${row.$1}: ${row.$2}').join('   ·   '),
                  style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
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

/// Maps engine-space layout coordinates onto canvas pixels, preserving aspect
/// ratio and centering. Mirrors the transform the layout bounds use so drag
/// interaction can invert it.
class _FitTransform {
  const _FitTransform({
    required this.size,
    required this.scale,
    required this.sourceCenter,
  });

  final Size size;
  final double scale;
  final Offset sourceCenter;

  factory _FitTransform.forLayout({
    required GlobeNetworkLayout layout,
    required Size size,
    required double padding,
  }) {
    final box = layout.bounds();
    if (box == null) {
      return _FitTransform(
        size: size,
        scale: 1.0,
        sourceCenter: Offset(size.width / 2, size.height / 2),
      );
    }
    final spanX = math.max(box.width, 1e-3);
    final spanY = math.max(box.height, 1e-3);
    final availableWidth = math.max(size.width - padding * 2, 1.0);
    final availableHeight = math.max(size.height - padding * 2, 1.0);
    final scale = math
        .min(availableWidth / spanX, availableHeight / spanY)
        .clamp(0.15, 1.0);
    return _FitTransform(size: size, scale: scale, sourceCenter: box.center);
  }

  Offset get target => Offset(size.width / 2, size.height / 2);

  Offset apply(Offset layoutPosition) =>
      target + (layoutPosition - sourceCenter) * scale;

  Offset invert(Offset canvasPosition) =>
      sourceCenter + (canvasPosition - target) / scale;
}

/// Orientation and zoom of the virtual camera that orbits the network scene.
///
/// The camera is a pure value object: dragging rotates the *whole scene* by
/// [yaw] (around the vertical axis) and [pitch] (around the horizontal axis),
/// and the scroll wheel / pinch gesture changes [zoom]. It never touches the
/// globe layout, so orbiting does not re-run placement — the layout is solved
/// once and every frame is a cheap re-projection.
@immutable
class OrbitCamera {
  const OrbitCamera({this.yaw = 0.0, this.pitch = 0.0, this.zoom = 1.0});

  /// No rotation, unit zoom. The projection with this camera reproduces the
  /// pre-camera CEL-139 output exactly.
  static const OrbitCamera identity = OrbitCamera();

  static const double minZoom = 0.35;
  static const double maxZoom = 3.2;

  /// Pitch is clamped short of ±90° so the scene never flips over the pole.
  static const double maxPitch = 1.25;

  static const double _orbitSensitivity = 0.008;

  /// Rotation around the vertical (y) axis, in radians.
  final double yaw;

  /// Rotation around the horizontal (x) axis, in radians.
  final double pitch;

  /// Uniform scale applied after projection. `1.0` is the fitted default.
  final double zoom;

  bool get isIdentity => yaw == 0.0 && pitch == 0.0 && zoom == 1.0;

  /// Rotates the scene by a screen-space drag delta, in logical pixels.
  OrbitCamera orbit(double dx, double dy) {
    return copyWith(
      yaw: yaw + dx * _orbitSensitivity,
      pitch: (pitch + dy * _orbitSensitivity).clamp(-maxPitch, maxPitch),
    );
  }

  /// Multiplies zoom by [factor], clamped to [[minZoom], [maxZoom]].
  OrbitCamera zoomBy(double factor) {
    if (!factor.isFinite || factor <= 0) return this;
    return copyWith(zoom: (zoom * factor).clamp(minZoom, maxZoom));
  }

  OrbitCamera copyWith({double? yaw, double? pitch, double? zoom}) {
    return OrbitCamera(
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      zoom: zoom ?? this.zoom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OrbitCamera &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(yaw, pitch, zoom);

  @override
  String toString() => 'OrbitCamera(yaw: $yaw, pitch: $pitch, zoom: $zoom)';
}

/// Perspective projection that turns a 2D layout position plus a depth value
/// into a canvas position and scale. Nearer nodes (`depth` 1) are larger and
/// pushed outward from the focal point; farther nodes recede.
///
/// An optional [camera] rotates the scene before the perspective divide, which
/// is what makes drag-to-orbit work without re-running the layout. With
/// [OrbitCamera.identity] the math collapses to the original CEL-139 formula.
class Network25DProjection {
  const Network25DProjection({
    required this.size,
    this.focal = const Offset(0.5, 0.5),
    this.nearScale = 1.18,
    this.farScale = 0.6,
    this.parallax = 20.0,
    this.camera = OrbitCamera.identity,
    this.depthSpread = 180.0,
  });

  final Size size;
  final Offset focal;
  final double nearScale;
  final double farScale;

  /// Lateral shift applied by depth, in pixels. Gives the layers a parallax
  /// separation that reads as depth even where two nodes overlap in x/y.
  final double parallax;

  /// Orientation/zoom of the virtual camera.
  final OrbitCamera camera;

  /// How many pixels of separation a full `0..1` depth range maps to when the
  /// camera rotates. Larger values make the scene read as deeper.
  final double depthSpread;

  double scaleFor(double depth) {
    final d = depth.clamp(0.0, 1.0);
    return farScale + (nearScale - farScale) * d;
  }

  /// Applies the orbit [camera] to a scene point plus its depth, returning the
  /// rotated point and the depth re-derived from the rotated z. Identity camera
  /// is a no-op, so callers get the pre-camera result unchanged.
  ({Offset point, double depth}) transformScene(
    Offset canvasPosition,
    double depth,
  ) {
    final d = depth.clamp(0.0, 1.0);
    if (camera.isIdentity) {
      return (point: canvasPosition, depth: d);
    }
    final center = Offset(size.width * focal.dx, size.height * focal.dy);
    final local = canvasPosition - center;
    final z = (d - 0.5) * depthSpread;

    final cosYaw = math.cos(camera.yaw);
    final sinYaw = math.sin(camera.yaw);
    final x1 = local.dx * cosYaw + z * sinYaw;
    final z1 = -local.dx * sinYaw + z * cosYaw;

    final cosPitch = math.cos(camera.pitch);
    final sinPitch = math.sin(camera.pitch);
    final y1 = local.dy * cosPitch - z1 * sinPitch;
    final z2 = local.dy * sinPitch + z1 * cosPitch;

    final rotatedDepth = (0.5 + z2 / depthSpread).clamp(0.0, 1.0);
    return (point: center + Offset(x1, y1), depth: rotatedDepth);
  }

  /// Projects an already camera-transformed point at [depth] to the canvas,
  /// applying the depth scale, parallax, and camera zoom.
  Offset projectTransformed(Offset point, double depth) {
    final d = depth.clamp(0.0, 1.0);
    final center = Offset(size.width * focal.dx, size.height * focal.dy);
    final scaled = center + (point - center) * scaleFor(d);
    final shift = (d - 0.5) * parallax;
    final projected = scaled + Offset(shift, shift * 0.5);
    return center + (projected - center) * camera.zoom;
  }

  Offset project(Offset canvasPosition, double depth) {
    final transformed = transformScene(canvasPosition, depth);
    return projectTransformed(transformed.point, transformed.depth);
  }
}

/// Distinct accents for co-active clusters (singletons keep layer-type color).
const List<Color> kCoactivationClusterPalette = <Color>[
  Color(0xFFE91E63),
  Color(0xFF00BCD4),
  Color(0xFFFFC107),
  Color(0xFF7C4DFF),
  Color(0xFF66BB6A),
  Color(0xFFFF7043),
];

/// Paints a [CanvasGraph] in 2.5D.
///
/// Depth is simulated entirely on the 2D canvas: nodes are painted back-to-front
/// (`depth` ascending), each is perspective-projected, and its fill, rim, glow,
/// and label alpha are shaded by depth. A radial depth fog over the background
/// reinforces the recession. All fills use `Paint.shader` gradients, matching
/// the shader-based rendering family in `fragment_shader_renderer.dart`.
class Network25DPainter extends CustomPainter {
  Network25DPainter({
    required this.graph,
    required this.positions,
    required this.depths,
    required this.projection,
    required this.activity,
    required this.edgeStrengths,
    required this.nirTypes,
    required this.nodeClusterIndices,
    required this.selectedId,
    required this.nodeLabelStyle,
    required this.secondaryLabelStyle,
    required this.activityColorOf,
    required this.selectionColor,
    required this.gridColor,
  });

  final CanvasGraph graph;

  /// Canvas-space positions (already fit to the viewport).
  final Map<String, Offset> positions;
  final Map<String, double> depths;
  final Network25DProjection projection;
  final Map<String, double> activity;
  final Map<String, double>? edgeStrengths;
  final Map<String, NirNodeType>? nirTypes;
  final Map<String, int>? nodeClusterIndices;
  final String? selectedId;
  final TextStyle nodeLabelStyle;
  final TextStyle secondaryLabelStyle;
  final Color Function(double rate) activityColorOf;
  final Color selectionColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintOrbitalChrome(canvas, size);

    final ordered = graph.nodes.toList()
      ..sort((a, b) => (depths[a.id] ?? 0.5).compareTo(depths[b.id] ?? 0.5));

    _paintEdges(canvas);
    for (final node in ordered) {
      _paintNode(canvas, node);
    }
  }

  // ── Background ─────────────────────────────────────────────────────────────

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surface, AppTheme.surfaceVariant],
        ).createShader(rect),
    );

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const spacing = 34.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Depth fog: darker at the edges, brighter at the focal centre.
    final fog = ui.Gradient.radial(
      Offset(size.width / 2, size.height / 2),
      size.longestSide * 0.62,
      [
        AppTheme.primary.withValues(alpha: 0.06),
        AppTheme.background.withValues(alpha: 0.0),
        AppTheme.background.withValues(alpha: 0.42),
      ],
      [0.0, 0.55, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = fog);

    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = AppTheme.border.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ── Orbital chrome (AIS-OS glow core + orbit rings) ───────────────────────

  void _paintOrbitalChrome(Canvas canvas, Size size) {
    if (graph.nodes.isEmpty) return;

    final focal = Offset(
      size.width * projection.focal.dx,
      size.height * projection.focal.dy,
    );
    final minDim = math.min(size.width, size.height);
    final zoom = projection.camera.zoom;
    final meanActivity = _meanActivity();

    final transformed = projection.transformScene(focal, 0.5);
    final projected = projection.projectTransformed(
      transformed.point,
      transformed.depth,
    );

    canvas.save();
    canvas.translate(projected.dx, projected.dy);
    canvas.rotate(projection.camera.yaw);

    final coreRadius = minDim * 0.11 * zoom;
    canvas.drawCircle(
      Offset.zero,
      coreRadius,
      GlowSprite.radial(
        center: Offset.zero,
        radius: coreRadius,
        color: AppTheme.primary,
        intensity: 0.28 + 0.32 * meanActivity,
      ),
    );

    final hotspotRadius = coreRadius * 0.35;
    canvas.drawCircle(
      Offset.zero,
      hotspotRadius,
      GlowSprite.radial(
        center: Offset.zero,
        radius: hotspotRadius,
        color: Colors.white,
        intensity: 0.12 + 0.22 * meanActivity,
        stops: const <GlowStop>[
          GlowStop(0.0, 1.0),
          GlowStop(0.7, 0.2),
          GlowStop(1.0, 0.0),
        ],
      ),
    );

    final flatten = 0.35 + 0.65 * math.cos(projection.camera.pitch).abs();
    GlowSprite.ring(
      canvas,
      radiusX: minDim * 0.24 * zoom,
      radiusY: minDim * 0.24 * zoom * flatten,
      color: AppTheme.primary,
      alpha: 0.2 + 0.08 * meanActivity,
    );
    GlowSprite.ring(
      canvas,
      radiusX: minDim * 0.38 * zoom,
      radiusY: minDim * 0.38 * zoom * flatten,
      color: AppTheme.primaryDim,
      alpha: 0.12 + 0.05 * meanActivity,
    );

    canvas.restore();
  }

  double _meanActivity() {
    if (activity.isEmpty) return 0.0;
    var sum = 0.0;
    for (final value in activity.values) {
      sum += value.clamp(0.0, 1.0);
    }
    return sum / activity.length;
  }

  // ── Edges ──────────────────────────────────────────────────────────────────

  void _paintEdges(Canvas canvas) {
    final edges = graph.edges.toList()
      ..sort((a, b) {
        final da = _edgeDepth(a);
        final db = _edgeDepth(b);
        return da.compareTo(db);
      });

    for (final edge in edges) {
      final from = positions[edge.sourceNodeId];
      final to = positions[edge.targetNodeId];
      if (from == null || to == null) continue;

      final sourceNode = _nodeById(edge.sourceNodeId);
      final depth = _edgeDepth(edge);
      final isSelected = edge.id == selectedId;
      final baseColor = sourceNode == null
          ? AppTheme.edgeExcitatory
          : _nodeColor(sourceNode);
      final inhibitory =
          (edge.parameters['polarity']?.toString() ?? '') == 'inhibitory';
      final color = inhibitory ? AppTheme.edgeInhibitory : baseColor;

      final correlation = edgeStrengths?[edge.id];
      final strength = correlation == null
          ? 0.0
          : correlation.abs().clamp(0.0, 1.0);
      final depthAlpha = 0.28 + 0.62 * depth;
      final alpha = (depthAlpha * (0.55 + 0.45 * strength)).clamp(0.12, 1.0);
      final strokeWidth =
          (1.0 + 1.6 * depth + 2.6 * strength) * (isSelected ? 1.8 : 1.0);

      final projectedFrom = projection.project(
        from,
        depths[edge.sourceNodeId] ?? depth,
      );
      final projectedTo = projection.project(
        to,
        depths[edge.targetNodeId] ?? depth,
      );
      final path = _edgePath(projectedFrom, projectedTo, depth);

      // Glow underlay — wider, low-alpha, brightest for strong co-activation.
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha * (0.16 + 0.34 * strength))
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );

      _paintArrowhead(canvas, projectedTo, color.withValues(alpha: alpha));
    }
  }

  Path _edgePath(Offset from, Offset to, double depth) {
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final delta = to - from;
    final length = delta.distance;
    if (length < 1) return Path()..moveTo(from.dx, from.dy);
    // Bow the wire perpendicular to its direction, more so for far edges —
    // a cheap 2.5D cue that wires leave and return to the depth plane.
    final normal = Offset(-delta.dy / length, delta.dx / length);
    final bow = (1.0 - depth) * math.min(26.0, length * 0.12);
    final control = mid + normal * bow;
    return Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
  }

  void _paintArrowhead(Canvas canvas, Offset tip, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tip, 2.4, paint);
  }

  double _edgeDepth(CanvasEdge edge) {
    final source = depths[edge.sourceNodeId] ?? 0.5;
    final target = depths[edge.targetNodeId] ?? 0.5;
    return (source + target) / 2;
  }

  // ── Nodes ──────────────────────────────────────────────────────────────────

  void _paintNode(Canvas canvas, CanvasNode node) {
    final position = positions[node.id];
    if (position == null) return;

    final rawDepth = (depths[node.id] ?? 0.5).clamp(0.0, 1.0);
    final transformed = projection.transformScene(position, rawDepth);
    final depth = transformed.depth;
    final color = _nodeColor(node);
    final radius =
        _nodeRadius(node) * projection.scaleFor(depth) * projection.camera.zoom;
    final center = projection.projectTransformed(transformed.point, depth);
    final isSelected = node.id == selectedId;
    final activity = (this.activity[node.id] ?? 0.0).clamp(0.0, 1.0);

    // Depth shading: far nodes desaturate toward the background.
    final shaded = Color.lerp(
      AppTheme.surfaceVariant,
      color,
      0.35 + 0.65 * depth,
    )!;
    final depthAlpha = 0.45 + 0.55 * depth;

    // Contact shadow grounds the node on the implied floor.
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, radius * 0.72),
        width: radius * 1.7,
        height: radius * 0.5,
      ),
      Paint()..color = AppTheme.background.withValues(alpha: 0.5 * depthAlpha),
    );

    // Activity glow — the brighter the layer fires, the larger and hotter.
    if (activity > 0.02) {
      final glowColor = activityColorOf(activity);
      final glowRadius = radius + 8 + 26 * activity;
      canvas.drawCircle(
        center,
        glowRadius,
        Paint()
          ..shader = ui.Gradient.radial(center, glowRadius, [
            glowColor.withValues(alpha: 0.34 * activity * depthAlpha),
            glowColor.withValues(alpha: 0.0),
          ]),
      );
    }

    // Soft depth glow so near nodes lift off the background.
    canvas.drawCircle(
      center,
      radius + 10,
      Paint()
        ..shader = ui.Gradient.radial(center, radius + 10, [
          shaded.withValues(alpha: 0.22 * depthAlpha),
          shaded.withValues(alpha: 0.0),
        ]),
    );

    final clusterIndex = nodeClusterIndices?[node.id];
    if (clusterIndex != null) {
      final halo =
          kCoactivationClusterPalette[clusterIndex %
              kCoactivationClusterPalette.length];
      canvas.drawCircle(
        center,
        radius + 14,
        Paint()
          ..shader = ui.Gradient.radial(center, radius + 14, [
            halo.withValues(alpha: 0.42 * depthAlpha),
            halo.withValues(alpha: 0.0),
          ]),
      );
    }

    if (isSelected) {
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = selectionColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Body: a radial gradient with an off-centre highlight sells the sphere.
    final highlight = center + Offset(-radius * 0.3, -radius * 0.35);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          highlight,
          radius * 1.6,
          [
            Color.lerp(
              shaded,
              Colors.white,
              0.32 * depth,
            )!.withValues(alpha: depthAlpha),
            shaded.withValues(alpha: depthAlpha),
            Color.lerp(
              shaded,
              AppTheme.background,
              0.5,
            )!.withValues(alpha: depthAlpha),
          ],
          [0.0, 0.55, 1.0],
        ),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.55 + 0.45 * depth)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 1.6,
    );

    _paintNodeLabel(canvas, node, center, radius, depth, activity);
  }

  void _paintNodeLabel(
    Canvas canvas,
    CanvasNode node,
    Offset center,
    double radius,
    double depth,
    double activity,
  ) {
    final label = node.label ?? node.componentId;
    final primaryAlpha = (0.4 + 0.6 * depth).clamp(0.3, 1.0);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: nodeLabelStyle.copyWith(
          color: nodeLabelStyle.color?.withValues(alpha: primaryAlpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);

    final top = center.dy + radius + 6;
    final background = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        center.dx - painter.width / 2 - 6,
        top - 3,
        painter.width + 12,
        painter.height + 6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      background,
      Paint()
        ..color = AppTheme.background.withValues(alpha: 0.72 * primaryAlpha),
    );
    painter.paint(canvas, Offset(center.dx - painter.width / 2, top));

    final subtitle = _subtitleFor(node, activity);
    if (subtitle == null || depth < 0.35) return;
    final secondary = TextPainter(
      text: TextSpan(
        text: subtitle,
        style: secondaryLabelStyle.copyWith(
          color: secondaryLabelStyle.color?.withValues(
            alpha: primaryAlpha * 0.9,
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);
    secondary.paint(
      canvas,
      Offset(center.dx - secondary.width / 2, top + painter.height + 1),
    );
  }

  String? _subtitleFor(CanvasNode node, double activity) {
    final parts = <String>[];
    final neurons = node.parameters['n_neurons'];
    if (neurons != null) parts.add('n=$neurons');
    if (activity > 0.02) parts.add('act ${(activity * 100).round()}%');
    return parts.isEmpty ? null : parts.join('  ');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  CanvasNode? _nodeById(String id) {
    for (final node in graph.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Color _nodeColor(CanvasNode node) {
    final clusterIndex = nodeClusterIndices?[node.id];
    if (clusterIndex != null) {
      return kCoactivationClusterPalette[clusterIndex %
          kCoactivationClusterPalette.length];
    }
    final category =
        nirTypes?[node.nirType ?? node.componentId]?.category ??
        node.metadata['category']?.toString() ??
        'utility';
    return canvasCategoryColor(category);
  }

  double _nodeRadius(CanvasNode node) {
    final neurons = (node.parameters['n_neurons'] as num?)?.toDouble();
    if (neurons == null) return 20.0;
    final clamped = neurons.clamp(1.0, 512.0);
    return 16.0 + 18.0 * (math.log(clamped + 1) / math.log(513));
  }

  @override
  bool shouldRepaint(covariant Network25DPainter old) =>
      old.graph != graph ||
      old.positions != positions ||
      old.depths != depths ||
      old.activity != activity ||
      old.edgeStrengths != edgeStrengths ||
      old.selectedId != selectedId ||
      old.nirTypes != nirTypes ||
      old.nodeClusterIndices != nodeClusterIndices ||
      old.projection.size != projection.size ||
      old.projection.camera != projection.camera;
}
