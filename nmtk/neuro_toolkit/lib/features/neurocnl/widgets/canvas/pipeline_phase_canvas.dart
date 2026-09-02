import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/component.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/custom_pipeline_node.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_selectors.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/component_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_node_subtitle.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_node_suggestions.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_connect_palette.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_edge_painting.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_minimap.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_stylus_layer.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

// Card footprint and port placement come from models/canvas/node_geometry.dart
// (re-exported by canvas_shared_widgets.dart), shared with the Architecture
// canvas and with canvas_provider.dart's grid-snap math.

// Keep the transformed child larger than a desktop viewport at minScale so
// every visible overflow node remains inside Flutter's hit-testable region.
const CanvasWorldGeometry _pipelineWorld = CanvasWorldGeometry(
  Size(10000, 10000),
);

// ── Shared helpers ────────────────────────────────────────────────────────────

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

// ── Port geometry ─────────────────────────────────────────────────────────────
//
// All of it delegates to the shared helpers in node_geometry.dart, which the
// Architecture canvas uses too — the two surfaces previously spread their
// ports by different rules (proportional there, fixed 28px spacing here).

Offset _portLocalTopLeft(
  PipelineDagNode node,
  int index, {
  required bool isInput,
  required bool isVertical,
}) => canvasNodePortTopLeft(
  index: index,
  count: isInput ? node.type.inputPorts.length : node.type.outputPorts.length,
  cardSize: pipelineDagNodeSize(node, compact: isVertical),
  isInput: isInput,
  compact: isVertical,
);

/// Scene-space centre of a port's dot — the point edges attach to.
///
/// Used by the edge painter, the live-wire preview, edge hit-testing and the
/// edge `✕` placement, so all four agree on where a wire actually ends.
Offset pipelinePortCentre(
  PipelineDagNode node,
  int index, {
  required bool isInput,
  required bool isVertical,
}) {
  final Offset local = _portLocalTopLeft(
    node,
    index,
    isInput: isInput,
    isVertical: isVertical,
  );
  return Offset(
    node.x + local.dx + kCanvasPortHitTargetSize / 2,
    node.y + local.dy + kCanvasPortHitTargetSize / 2,
  );
}

/// Scene-space endpoints of [edge], or null when either end no longer resolves.
({Offset start, Offset end, PortType type})? pipelineEdgeEndpoints(
  PipelineDAG dag,
  PipelineDagEdge edge, {
  required bool isVertical,
}) {
  final srcNode = _firstWhereOrNull(
    dag.nodes,
    (n) => n.id == edge.sourceNodeId,
  );
  final dstNode = _firstWhereOrNull(
    dag.nodes,
    (n) => n.id == edge.targetNodeId,
  );
  if (srcNode == null || dstNode == null) return null;

  final int srcIdx = srcNode.type.outputPorts.indexWhere(
    (p) => p.id == edge.sourcePort,
  );
  final int dstIdx = dstNode.type.inputPorts.indexWhere(
    (p) => p.id == edge.targetPort,
  );

  return (
    start: pipelinePortCentre(
      srcNode,
      srcIdx >= 0 ? srcIdx : 0,
      isInput: false,
      isVertical: isVertical,
    ),
    end: pipelinePortCentre(
      dstNode,
      dstIdx >= 0 ? dstIdx : 0,
      isInput: true,
      isVertical: isVertical,
    ),
    type: srcIdx >= 0 ? srcNode.type.outputPorts[srcIdx].type : PortType.any,
  );
}

// The cubic's control points, its sampled midpoint/distance and the stroke
// rules now live in canvas_edge_painting.dart, shared with the Architecture
// canvas. These aliases keep the existing call sites readable.

({Offset cp1, Offset cp2}) pipelineEdgeControlPoints(
  Offset start,
  Offset end, {
  required bool isVertical,
}) => canvasEdgeControlPoints(start, end, isVertical: isVertical);

Offset pipelineEdgePointAt(
  Offset start,
  Offset end,
  double t, {
  required bool isVertical,
}) => canvasEdgePointAt(start, end, t, isVertical: isVertical);

double pipelineEdgeDistance(
  Offset point,
  Offset start,
  Offset end, {
  required bool isVertical,
}) => canvasEdgeDistance(point, start, end, isVertical: isVertical);

// ── Canvas ────────────────────────────────────────────────────────────────────

class PipelinePhaseCanvas extends ConsumerStatefulWidget {
  const PipelinePhaseCanvas({
    super.key,
    required this.phase,
    this.onNodeDoubleTap,
    this.isVertical = false,
  });

  final PipelinePhaseId phase;
  final VoidCallback? onNodeDoubleTap;

  /// When true, nodes render with a stacked icon-above-label header and
  /// top/bottom ports instead of the default icon-beside-label header with
  /// left/right ports. Driven by the local width of the tab hosting this
  /// canvas (see `canvas_screen.dart`), not the window's raw MediaQuery
  /// width, so it also flips inside a half-width split pipeline-stepper pane.
  final bool isVertical;

  @override
  ConsumerState<PipelinePhaseCanvas> createState() =>
      _PipelinePhaseCanvasState();
}

class _PipelinePhaseCanvasState extends ConsumerState<PipelinePhaseCanvas>
    with
        SingleTickerProviderStateMixin,
        CanvasViewportMixin<PipelinePhaseCanvas>,
        CanvasStylusMixin<PipelinePhaseCanvas> {
  /// Scene-space pointer position while a connection drag is in progress.
  /// Null when no drag is active. Used for the live-wire preview.
  Offset? _currentConnectingPoint;

  final TransformationController _tc = TransformationController();
  final FocusNode _focus = FocusNode();

  /// Drives the animated pan-to-node triggered when a new node is added --
  /// see [_followPendingViewportFocus]. Built eagerly in [initState] rather
  /// than via a lazy `late` initializer: if the controller is never read
  /// until [dispose] (e.g. no node was ever added), a lazy initializer would
  /// construct it -- and call `vsync: this` -- while the widget is already
  /// deactivated, which crashes.
  late final AnimationController _viewportFollowController;
  int _handledWorkspaceRestoreFocusRevision = 0;

  bool get _isPrimaryModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// The port tapped last, if the next tap on it should open the add-node
  /// palette. The port dot is the `+`: the first tap arms a connection, a second
  /// tap on the same dot means "I didn't want an existing node, give me a new
  /// one". Cleared by anything that ends or redirects the interaction.
  String? _armedPortNodeId;
  String? _armedPortId;

  bool _isArmedPort(String nodeId, String portId) =>
      _armedPortNodeId == nodeId && _armedPortId == portId;

  void _clearArmedPort() {
    if (_armedPortNodeId == null && _armedPortId == null) return;
    setState(() {
      _armedPortNodeId = null;
      _armedPortId = null;
    });
  }

  void _armPort(String nodeId, String portId) {
    setState(() {
      _armedPortNodeId = nodeId;
      _armedPortId = portId;
    });
  }

  @override
  void initState() {
    super.initState();
    _tc.value = _worldMatrix(zoom: 1, pan: Offset.zero);
    _viewportFollowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  CanvasWorldGeometry get canvasWorld => _pipelineWorld;

  @override
  TransformationController get canvasTransform => _tc;

  Offset _sceneFromViewport(Offset viewportPosition) =>
      canvasSceneFromViewport(viewportPosition);

  Matrix4 _worldMatrix({required double zoom, required Offset pan}) =>
      canvasWorldMatrix(zoom: zoom, pan: pan);

  @override
  void dispose() {
    canvasDisposeStylusLayer();
    _tc.dispose();
    _viewportFollowController.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dag = ref.watch(
      canvasProvider.select((s) => s.pipelinePhases.dagFor(widget.phase)),
    );
    final selectedNodeIds = ref.watch(
      canvasProvider.select((s) => s.selectedNodeIds),
    );
    final connectingFromNodeId = ref.watch(
      canvasProvider.select((s) => s.connectingFromNodeId),
    );
    final connectingFromPort = ref.watch(
      canvasProvider.select((s) => s.connectingFromPortId),
    );
    final selectedEdgeId = ref.watch(
      canvasProvider.select((s) => s.selectedEdgeId),
    );
    ref.listen<String?>(
      canvasProvider.select((CanvasState s) => s.pendingViewportFocusNodeId),
      (String? previous, String? next) {
        if (next != null) _followPendingViewportFocus(next);
      },
    );
    final int workspaceRestoreFocusRevision = ref.watch(
      canvasProvider.select((CanvasState s) => s.workspaceRestoreFocusRevision),
    );
    _scheduleWorkspaceRestoreFocus(workspaceRestoreFocusRevision);

    // Resolve the pipeline PortType of the port being dragged (null = no drag).
    PortType? connectingPortType;
    if (connectingFromNodeId != null && connectingFromPort != null) {
      for (final n in dag.nodes) {
        if (n.id == connectingFromNodeId) {
          for (final p in n.type.outputPorts) {
            if (p.id == connectingFromPort) {
              connectingPortType = p.type;
              break;
            }
          }
          break;
        }
      }
    }

    // Midpoint of the selected edge, where its delete `✕` goes. Null when no
    // edge is selected or its endpoints no longer resolve.
    Offset? selectedEdgeCentre;
    if (selectedEdgeId != null) {
      final PipelineDagEdge? edge = _firstWhereOrNull(
        dag.edges,
        (PipelineDagEdge e) => e.id == selectedEdgeId,
      );
      if (edge != null) {
        final ends = pipelineEdgeEndpoints(
          dag,
          edge,
          isVertical: widget.isVertical,
        );
        if (ends != null) {
          selectedEdgeCentre = pipelineEdgePointAt(
            ends.start,
            ends.end,
            0.5,
            isVertical: widget.isVertical,
          );
        }
      }
    }

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = constraints.biggest;
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Stack(
              children: [
                // Grid background.
                Positioned.fill(
                  child: ValueListenableBuilder<Matrix4>(
                    valueListenable: _tc,
                    builder: (BuildContext ctx, Matrix4 matrix, Widget? _) {
                      return CustomPaint(
                        painter: GridPainter(
                          transform: matrix,
                          sceneOrigin: _pipelineWorld.origin,
                          lineColor: Theme.of(
                            ctx,
                          ).colorScheme.onSurface.withValues(alpha: 0.07),
                        ),
                      );
                    },
                  ),
                ),
                // Drop target + canvas.
                Positioned.fill(
                  child: DragTarget<PipelineDagNodeType>(
                    onAcceptWithDetails:
                        (DragTargetDetails<PipelineDagNodeType> details) =>
                            _handleDrop(details),
                    builder:
                        (
                          BuildContext ctx,
                          List<PipelineDagNodeType?> _,
                          List<dynamic> _,
                        ) {
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: (TapDownDetails details) {
                              _focus.requestFocus();
                              // A tap that lands on a wire selects it, revealing its
                              // delete `✕`. Only a tap on genuinely empty canvas
                              // clears the selection.
                              final PipelineDagEdge? edge =
                                  _edgeAtLocalPosition(
                                    details.localPosition,
                                    dag,
                                  );
                              if (edge != null) {
                                _clearArmedPort();
                                ref
                                    .read(canvasProvider.notifier)
                                    .selectEdge(edge.id);
                                return;
                              }
                              if (!_isPrimaryModifierPressed) {
                                _clearArmedPort();
                                ref
                                    .read(canvasProvider.notifier)
                                    .clearSelection();
                              }
                            },
                            child: RawGestureDetector(
                              behavior: HitTestBehavior.translucent,
                              // Lasso-select / handwriting-to-node, wired
                              // identically on every canvas.
                              gestures: canvasStylusGestures,
                              child: InteractiveViewer(
                                constrained: false,
                                transformationController: _tc,
                                boundaryMargin: const EdgeInsets.all(500),
                                minScale: kCanvasMinZoom,
                                maxScale: kCanvasMaxZoom,
                                child: SizedBox(
                                  width: _pipelineWorld.size.width,
                                  height: _pipelineWorld.size.height,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: _pipelineWorld.size,
                                          painter: _PipelineEdgePainter(
                                            dag: dag,
                                            connectingPoint:
                                                _currentConnectingPoint,
                                            connectingFromOffset:
                                                _connectingFromOffset(
                                                  dag,
                                                  connectingFromNodeId,
                                                  connectingFromPort,
                                                ),
                                            selectedEdgeId: selectedEdgeId,
                                            selectionColor: NmtkShellTokens.of(
                                              context,
                                            ).studioPalette.accent,
                                            previewWireColor: Zeta.of(
                                              context,
                                            ).colors.mainSubtle,
                                            isVertical: widget.isVertical,
                                            sceneOrigin: _pipelineWorld.origin,
                                          ),
                                        ),
                                      ),
                                      ...dag.nodes.map(
                                        (PipelineDagNode node) => Positioned(
                                          left:
                                              node.x + _pipelineWorld.origin.dx,
                                          top:
                                              node.y + _pipelineWorld.origin.dy,
                                          child: _PipelineDagNodeWidget(
                                            key: ValueKey<String>(
                                              'pnode_${node.id}',
                                            ),
                                            node: node,
                                            dag: dag,
                                            phase: widget.phase,
                                            isSelected: selectedNodeIds
                                                .contains(node.id),
                                            connectingFromNodeId:
                                                connectingFromNodeId,
                                            connectingFromPort:
                                                connectingFromPort,
                                            connectingPortType:
                                                connectingPortType,
                                            onTap: () {
                                              _focus.requestFocus();
                                              final notifier = ref.read(
                                                canvasProvider.notifier,
                                              );
                                              final additive =
                                                  HardwareKeyboard
                                                      .instance
                                                      .isMetaPressed ||
                                                  HardwareKeyboard
                                                      .instance
                                                      .isControlPressed;
                                              if (additive) {
                                                notifier.toggleNodeSelection(
                                                  node.id,
                                                  additive: true,
                                                );
                                              } else {
                                                notifier.selectNode(node.id);
                                              }
                                            },
                                            onDoubleTap: () {
                                              widget.onNodeDoubleTap?.call();
                                            },
                                            onPanUpdate: (DragUpdateDetails d) {
                                              ref
                                                  .read(canvasProvider.notifier)
                                                  .movePipelineDagNode(
                                                    widget.phase,
                                                    node.id,
                                                    d.delta.dx,
                                                    d.delta.dy,
                                                  );
                                            },
                                            onOutputPortTap: (String portId) {
                                              _focus.requestFocus();
                                              _handleOutputPortTap(
                                                node.id,
                                                portId,
                                              );
                                            },
                                            onInputPortTap: (String portId) {
                                              _focus.requestFocus();
                                              _handleInputPortTap(
                                                node.id,
                                                portId,
                                                dag,
                                              );
                                            },
                                            onPortPanUpdate: _onPortPanUpdate,
                                            onPortPanEnd: _onPortPanEnd,
                                            armedPortNodeId: _armedPortNodeId,
                                            armedPortId: _armedPortId,
                                            isVertical: widget.isVertical,
                                          ),
                                        ),
                                      ),
                                      // Delete affordance for the selected edge. Lives
                                      // in the canvas Stack, not on a node, because it
                                      // belongs to the wire's midpoint.
                                      if (selectedEdgeCentre != null)
                                        Positioned(
                                          left:
                                              selectedEdgeCentre.dx +
                                              _pipelineWorld.origin.dx -
                                              kCanvasEdgeDeleteHitTargetSize /
                                                  2,
                                          top:
                                              selectedEdgeCentre.dy +
                                              _pipelineWorld.origin.dy -
                                              kCanvasEdgeDeleteHitTargetSize /
                                                  2,
                                          child: CanvasEdgeDeleteButton(
                                            key: const ValueKey<String>(
                                              'pipeline_edge_delete',
                                            ),
                                            onPressed: () {
                                              _focus.requestFocus();
                                              ref
                                                  .read(canvasProvider.notifier)
                                                  .removePipelineDagEdge(
                                                    widget.phase,
                                                    selectedEdgeId!,
                                                  );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                  ),
                ),
                // Stylus lasso (rubber-band) selection rectangle.
                if (canvasLassoStart != null && canvasLassoEnd != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: MarqueeSelectionPainter(
                          start: canvasLassoStart!,
                          end: canvasLassoEnd!,
                          transform: _tc.value,
                          sceneOrigin: _pipelineWorld.origin,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                // Empty state.
                if (dag.nodes.isEmpty)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ZetaIcons.add_circle_outline,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Drag nodes from the palette to build the '
                          '${widget.phase.name} pipeline',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  left: widget.isVertical ? null : 16,
                  top: widget.isVertical ? 16 : null,
                  right: widget.isVertical ? 16 : null,
                  bottom: widget.isVertical ? null : 16,
                  child: CanvasMinimapWidget(
                    nodes: dag.nodes.map((PipelineDagNode node) {
                      final Size size = pipelineDagNodeSize(
                        node,
                        compact: widget.isVertical,
                      );
                      return MinimapNode(
                        Rect.fromLTWH(node.x, node.y, size.width, size.height),
                        pipelineCategoryColor(node.type.category),
                      );
                    }).toList(),
                    edgeLines: dag.edges
                        .map((PipelineDagEdge edge) {
                          final ends = pipelineEdgeEndpoints(
                            dag,
                            edge,
                            isVertical: widget.isVertical,
                          );
                          if (ends != null) {
                            return MinimapEdgeLine(ends.start, ends.end);
                          }
                          return null;
                        })
                        .whereType<MinimapEdgeLine>()
                        .toList(),
                    transformationController: _tc,
                    viewportSize: viewportSize,
                    onJumpTo: (Offset scenePoint) {
                      final double zoom = _tc.value.getMaxScaleOnAxis();
                      final Offset pan = centeredPanFor(
                        scenePoint,
                        zoom,
                        viewportSize,
                      );
                      _tc.value = _worldMatrix(zoom: zoom, pan: pan);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Drop ──────────────────────────────────────────────────────────────────

  void _handleDrop(DragTargetDetails<PipelineDagNodeType> details) {
    final renderBox = context.findRenderObject()! as RenderBox;
    final local = renderBox.globalToLocal(details.offset);
    _addNodeAt(details.data, _sceneFromViewport(local));
  }

  /// Animates the viewport to center [nodeId] (keeping the current zoom)
  /// then clears the pending signal so it doesn't re-trigger on unrelated
  /// rebuilds. Triggered by [CanvasController.addPipelineDagNode] setting
  /// `pendingViewportFocusNodeId` -- see the `ref.listen` in [build].
  /// Scene-space centre of [node]'s card — what the viewport centres on.
  Offset _nodeSceneCentre(PipelineDagNode node) {
    final Size size = pipelineDagNodeSize(node, compact: widget.isVertical);
    return Offset(node.x + size.width / 2, node.y + size.height / 2);
  }

  void _followPendingViewportFocus(String nodeId) {
    final canvasNotifier = ref.read(canvasProvider.notifier);
    canvasNotifier.clearPendingViewportFocusNodeId();

    final dag = ref.read(canvasProvider).pipelinePhases.dagFor(widget.phase);
    PipelineDagNode? node;
    for (final PipelineDagNode n in dag.nodes) {
      if (n.id == nodeId) {
        node = n;
        break;
      }
    }
    if (node == null) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final Matrix4 current = _tc.value;
    final double zoom = current.getMaxScaleOnAxis();
    final Offset sceneCenter = _nodeSceneCentre(node);
    final Offset pan = centeredPanFor(sceneCenter, zoom, box.size);
    final Matrix4 target = _worldMatrix(zoom: zoom, pan: pan);

    final Animation<Matrix4> animation =
        Matrix4Tween(begin: current, end: target).animate(
          CurvedAnimation(
            parent: _viewportFollowController,
            curve: Curves.easeOutCubic,
          ),
        );
    late final VoidCallback listener;
    listener = () => _tc.value = animation.value;
    animation.addListener(listener);
    _viewportFollowController
      ..reset()
      ..forward().whenCompleteOrCancel(
        () => animation.removeListener(listener),
      );
  }

  void _scheduleWorkspaceRestoreFocus(int revision) {
    if (revision == 0 || revision == _handledWorkspaceRestoreFocusRevision) {
      return;
    }
    _handledWorkspaceRestoreFocusRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final PipelineDAG dag = ref
          .read(canvasProvider)
          .pipelinePhases
          .dagFor(widget.phase);
      if (dag.nodes.isEmpty) return;
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final PipelineDagNode node = dag.nodes.first;
      final double zoom = _tc.value.getMaxScaleOnAxis();
      final Offset pan = anchoredPanFor(_nodeSceneCentre(node), zoom, box.size);
      _tc.value = _worldMatrix(zoom: zoom, pan: pan);
    });
  }

  // ── Connection: drag-to-connect live wire ─────────────────────────────────

  /// Called by [_PipelineDagNodeWidget] during an output-port pan drag.
  /// [global] is the pointer's global position; converted to scene coords here.
  void _onPortPanUpdate(String portId, Offset global) {
    final renderBox = context.findRenderObject()! as RenderBox;
    final local = renderBox.globalToLocal(global);
    final scenePos = _sceneFromViewport(local);
    setState(() => _currentConnectingPoint = scenePos);
  }

  /// Called when the user lifts after dragging from an output port.
  /// Snaps the drop to the nearest compatible input port.
  void _onPortPanEnd(String portId) {
    // A drag consumed the port's intent, so a subsequent single tap on it should
    // arm afresh rather than jump straight to the palette.
    _clearArmedPort();
    final connectingPoint = _currentConnectingPoint;
    final s = ref.read(canvasProvider);
    final sourceNodeId = s.connectingFromNodeId;
    final sourcePortId = s.connectingFromPortId;

    setState(() => _currentConnectingPoint = null);

    if (connectingPoint == null ||
        sourceNodeId == null ||
        sourcePortId == null) {
      ref.read(canvasProvider.notifier).cancelConnecting();
      return;
    }

    final dag = s.pipelinePhases.dagFor(widget.phase);

    for (final targetNode in dag.nodes) {
      if (targetNode.id == sourceNodeId) continue;
      final inputs = targetNode.type.inputPorts;
      for (var i = 0; i < inputs.length; i++) {
        // Centre of the input port's hit target in scene coordinates. Uses
        // the same orientation-aware helper the port dots/edges use, so a
        // drag-release lands on the correct target in vertical mode too --
        // this used to always assume the horizontal (left-edge) port layout.
        final portCenter = pipelinePortCentre(
          targetNode,
          i,
          isInput: true,
          isVertical: widget.isVertical,
        );
        if ((connectingPoint - portCenter).distance <
            kCanvasPortHitTargetSize) {
          final srcNode = _firstWhereOrNull(
            dag.nodes,
            (n) => n.id == sourceNodeId,
          );
          if (srcNode == null) break;
          final srcPort = _firstWhereOrNull(
            srcNode.type.outputPorts,
            (p) => p.id == sourcePortId,
          );
          final dstPort = inputs[i];
          final compatible =
              srcPort == null ||
              dstPort.type == PortType.any ||
              srcPort.type == PortType.any ||
              srcPort.type == dstPort.type;
          if (compatible) {
            ref
                .read(canvasProvider.notifier)
                .addPipelineDagEdge(
                  widget.phase,
                  PipelineDagEdge(
                    id: 'edge_${DateTime.now().millisecondsSinceEpoch}',
                    sourceNodeId: sourceNodeId,
                    sourcePort: sourcePortId,
                    targetNodeId: targetNode.id,
                    targetPort: dstPort.id,
                  ),
                );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Type mismatch: ${srcPort.type.name} → ${dstPort.type.name}',
                ),
                showCloseIcon: true,
              ),
            );
          }
          ref.read(canvasProvider.notifier).cancelConnecting();
          return;
        }
      }
    }

    ref.read(canvasProvider.notifier).cancelConnecting();
  }

  /// Returns the scene-space centre of the active output port, used as the
  /// start-point of the live-wire preview line.
  Offset? _connectingFromOffset(
    PipelineDAG dag,
    String? fromNodeId,
    String? fromPortId,
  ) {
    if (fromNodeId == null || fromPortId == null) return null;
    final node = _firstWhereOrNull(dag.nodes, (n) => n.id == fromNodeId);
    if (node == null) return null;
    final idx = node.type.outputPorts.indexWhere((p) => p.id == fromPortId);
    if (idx < 0) return null;
    return pipelinePortCentre(
      node,
      idx,
      isInput: false,
      isVertical: widget.isVertical,
    );
  }

  // ── Edge selection ────────────────────────────────────────────────────────

  /// The edge under [localPosition] (viewport coordinates), or null.
  ///
  /// Later edges win, matching paint order: the wire drawn on top is the one the
  /// user sees under the cursor.
  PipelineDagEdge? _edgeAtLocalPosition(Offset localPosition, PipelineDAG dag) {
    final Offset scene = _sceneFromViewport(localPosition);
    // Tolerance in scene units, so it stays a constant on-screen distance
    // regardless of zoom.
    final double scale = _tc.value.getMaxScaleOnAxis();
    final double tolerance = kCanvasEdgeHitTolerance / (scale == 0 ? 1 : scale);

    PipelineDagEdge? hit;
    for (final PipelineDagEdge edge in dag.edges) {
      final ends = pipelineEdgeEndpoints(
        dag,
        edge,
        isVertical: widget.isVertical,
      );
      if (ends == null) continue;
      if (pipelineEdgeDistance(
            scene,
            ends.start,
            ends.end,
            isVertical: widget.isVertical,
          ) <=
          tolerance) {
        hit = edge;
      }
    }
    return hit;
  }

  // ── Connection: tap-to-connect ────────────────────────────────────────────

  void _handleOutputPortTap(String nodeId, String portId) {
    // Second tap on the same dot: the user has seen the armed state and tapped
    // again, which means "no existing node — give me a new one".
    if (_isArmedPort(nodeId, portId)) {
      _clearArmedPort();
      _handleAddFromPort(
        node: _firstWhereOrNull(
          ref.read(canvasProvider).pipelinePhases.dagFor(widget.phase).nodes,
          (PipelineDagNode n) => n.id == nodeId,
        ),
        portId: portId,
        fromOutput: true,
      );
      return;
    }

    ref.read(canvasProvider.notifier).startConnecting(nodeId, portId);
    ref.read(canvasProvider.notifier).selectNode(nodeId);
    _armPort(nodeId, portId);
  }

  void _handleInputPortTap(
    String targetNodeId,
    String targetPortId,
    PipelineDAG dag,
  ) {
    final s = ref.read(canvasProvider);
    final sourceNodeId = s.connectingFromNodeId;
    final sourcePortId = s.connectingFromPortId;

    // No connection in progress: the input dot behaves like the output one —
    // first tap arms it, second tap asks for a new upstream node.
    if (sourceNodeId == null || sourcePortId == null) {
      if (_isArmedPort(targetNodeId, targetPortId)) {
        _clearArmedPort();
        _handleAddFromPort(
          node: _firstWhereOrNull(
            dag.nodes,
            (PipelineDagNode n) => n.id == targetNodeId,
          ),
          portId: targetPortId,
          fromOutput: false,
        );
      } else {
        _armPort(targetNodeId, targetPortId);
      }
      return;
    }

    // A connection *is* in progress, so this tap completes it — the armed state
    // belongs to the source port and is now spent either way.
    _clearArmedPort();
    if (sourceNodeId == targetNodeId) {
      ref.read(canvasProvider.notifier).cancelConnecting();
      return;
    }

    final sourceNode = _firstWhereOrNull(
      dag.nodes,
      (n) => n.id == sourceNodeId,
    );
    final targetNode = _firstWhereOrNull(
      dag.nodes,
      (n) => n.id == targetNodeId,
    );
    if (sourceNode == null || targetNode == null) {
      ref.read(canvasProvider.notifier).cancelConnecting();
      return;
    }
    final srcPort = _firstWhereOrNull(
      sourceNode.type.outputPorts,
      (p) => p.id == sourcePortId,
    );
    final dstPort = _firstWhereOrNull(
      targetNode.type.inputPorts,
      (p) => p.id == targetPortId,
    );
    final compatible =
        srcPort == null ||
        dstPort == null ||
        srcPort.type == PortType.any ||
        dstPort.type == PortType.any ||
        srcPort.type == dstPort.type;

    if (!compatible) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Type mismatch: ${srcPort.type.name} → ${dstPort.type.name}',
          ),
          showCloseIcon: true,
        ),
      );
      ref.read(canvasProvider.notifier).cancelConnecting();
      return;
    }

    ref
        .read(canvasProvider.notifier)
        .addPipelineDagEdge(
          widget.phase,
          PipelineDagEdge(
            id: 'edge_${DateTime.now().millisecondsSinceEpoch}',
            sourceNodeId: sourceNodeId,
            sourcePort: sourcePortId,
            targetNodeId: targetNodeId,
            targetPort: targetPortId,
          ),
        );
    ref.read(canvasProvider.notifier).cancelConnecting();
  }

  // ── Connection: add-and-connect from a port's second tap ──────────────────

  /// Opens the connect palette for [portId] on [node], then creates the chosen
  /// node and wires it up in one gesture.
  ///
  /// [fromOutput] true means the new node goes *downstream* of [node]: it needs
  /// an input port, and the edge runs `node → new`. False is the mirror.
  ///
  /// [node] is nullable because the caller resolves it by id from live state; a
  /// null means the node vanished between the tap and this call.
  Future<void> _handleAddFromPort({
    required PipelineDagNode? node,
    required String portId,
    required bool fromOutput,
  }) async {
    if (node == null) return;
    // Any half-finished tap-to-connect would otherwise stay armed behind the
    // modal and fire on the next input-port tap.
    ref.read(canvasProvider.notifier).cancelConnecting();
    _clearArmedPort();
    setState(() => _currentConnectingPoint = null);

    // Selecting the source node first makes `addPipelineDagNode` place the new
    // node adjacent to it — the grid placer positions relative to the current
    // selection, so no bespoke placement maths is needed here.
    ref.read(canvasProvider.notifier).selectNode(node.id);

    final List<String> platforms = ref.read(
      workspaceProvider.select((s) => s.selectedPlatforms),
    );

    // Saved custom components are a bonus, not a precondition: when the backend
    // is unreachable the fetch throws, and letting that propagate would mean the
    // `+` silently does nothing at all. Fall back to the built-in types.
    List<ComponentBlock> components;
    try {
      components = await ref.read(componentsProvider.future);
    } catch (_) {
      components = const <ComponentBlock>[];
    }
    if (!mounted) return;
    final items = pipelinePaletteItems(
      phase: widget.phase,
      platforms: platforms.toSet(),
      components: components,
    );

    // Direction-only filter: a candidate qualifies if it has any port on the
    // facing side. No data-type filtering — `PortSpec.type` coverage is thin
    // enough that it would hide legitimately connectable nodes. Mismatches are
    // still reported by the existing connect-time check.
    final List<CanvasConnectPaletteEntry> entries = items
        .map((PipelineNodePaletteItem item) {
          final type = item.type;
          final List<PortSpec> facing = fromOutput
              ? type.inputPorts
              : type.outputPorts;
          return CanvasConnectPaletteEntry(
            id: item.id,
            label: item.label,
            icon: pipelineCategoryIcon(type.category),
            accent: pipelineCategoryColor(type.category),
            ports: facing
                .map(
                  (PortSpec p) =>
                      CanvasConnectPalettePort(id: p.id, label: p.id),
                )
                .toList(),
          );
        })
        .where((CanvasConnectPaletteEntry e) => e.ports.isNotEmpty)
        .toList();

    if (entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fromOutput
                ? 'No node type in this phase accepts an input.'
                : 'No node type in this phase produces an output.',
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }

    final CanvasConnectPaletteResult? result = await showCanvasConnectPalette(
      context: context,
      direction: fromOutput
          ? CanvasConnectDirection.fromOutput
          : CanvasConnectDirection.fromInput,
      entries: entries,
    );
    if (result == null || !mounted) return;

    final PipelineNodePaletteItem? selectedItem = _firstWhereOrNull(
      items,
      (PipelineNodePaletteItem item) => item.id == result.entryId,
    );
    if (selectedItem == null) return;
    final newType = selectedItem.type;

    final String newNodeId =
        '${newType.name}_${DateTime.now().millisecondsSinceEpoch}';
    final notifier = ref.read(canvasProvider.notifier);

    notifier.addPipelineDagNode(
      widget.phase,
      PipelineDagNode(
        id: newNodeId,
        type: newType,
        customComponentId: selectedItem.customComponentId,
        x: node.x,
        y: node.y,
        parameters: selectedItem.defaultParameters,
      ),
      preferRight: !widget.isVertical,
    );

    notifier.addPipelineDagEdge(
      widget.phase,
      PipelineDagEdge(
        // Derived from the node id rather than a second timestamp — two
        // `millisecondsSinceEpoch` calls in one gesture can collide.
        id: 'edge_$newNodeId',
        sourceNodeId: fromOutput ? node.id : newNodeId,
        sourcePort: fromOutput ? portId : result.portId,
        targetNodeId: fromOutput ? newNodeId : node.id,
        targetPort: fromOutput ? result.portId : portId,
      ),
    );
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final s = ref.read(canvasProvider);

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(canvasProvider.notifier).cancelConnecting();
      _clearArmedPort();
      setState(() => _currentConnectingPoint = null);
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (s.selectedNodeIds.isNotEmpty) {
        ref
            .read(canvasProvider.notifier)
            .removePipelineDagNodes(widget.phase, s.selectedNodeIds);
      } else if (s.selectedEdgeId != null) {
        ref
            .read(canvasProvider.notifier)
            .removePipelineDagEdge(widget.phase, s.selectedEdgeId!);
      }
      return;
    }

    final isPrimaryModifier =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (isPrimaryModifier &&
        (event.logicalKey == LogicalKeyboardKey.digit0 ||
            event.logicalKey == LogicalKeyboardKey.numpad0)) {
      canvasResetViewport();
      return;
    }

    if (isPrimaryModifier &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      _adjustZoom(kCanvasZoomStep);
      return;
    }

    if (isPrimaryModifier &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _adjustZoom(1 / kCanvasZoomStep);
    }
  }

  void _adjustZoom(double multiplier) {
    final Matrix4? zoomed = canvasZoomedBy(multiplier);
    if (zoomed != null) _tc.value = zoomed;
  }

  // ── Stylus-on-empty-canvas: lasso selection & handwriting-to-node ─────────
  //
  // The behaviour lives in CanvasStylusMixin, shared with the Architecture
  // canvas — these hooks are the pipeline-specific parts.

  @override
  bool canvasIsEmptyAt(Offset scenePosition) {
    final PipelineDAG dag = ref
        .read(canvasProvider)
        .pipelinePhases
        .dagFor(widget.phase);
    for (final PipelineDagNode node in dag.nodes) {
      final Size size = pipelineDagNodeSize(node, compact: widget.isVertical);
      if (Rect.fromLTWH(
        node.x,
        node.y,
        size.width,
        size.height,
      ).contains(scenePosition)) {
        return false;
      }
      for (int i = 0; i < node.type.inputPorts.length; i += 1) {
        if ((pipelinePortCentre(
                      node,
                      i,
                      isInput: true,
                      isVertical: widget.isVertical,
                    ) -
                    scenePosition)
                .distance <=
            kCanvasPortHitTargetSize / 2) {
          return false;
        }
      }
      for (int i = 0; i < node.type.outputPorts.length; i += 1) {
        if ((pipelinePortCentre(
                      node,
                      i,
                      isInput: false,
                      isVertical: widget.isVertical,
                    ) -
                    scenePosition)
                .distance <=
            kCanvasPortHitTargetSize / 2) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  void canvasSelectInRect(Rect sceneRect) => ref
      .read(canvasProvider.notifier)
      .selectPipelineDagNodesInRect(widget.phase, sceneRect);

  @override
  List<String> canvasSuggestNodeTypes(String query) => suggestPipelineNodeTypes(
    query,
  ).map((PipelineDagNodeType type) => type.label).toList();

  @override
  void canvasCreateNodeFromText(String text, Offset scenePosition) {
    final PipelineDagNodeType? type = resolvePipelineNodeType(text);
    if (type == null) {
      if (text.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No matching node type for '$text'."),
            showCloseIcon: true,
          ),
        );
      }
      return;
    }
    _addNodeAt(type, scenePosition);
  }

  void _addNodeAt(PipelineDagNodeType type, Offset scenePos) {
    ref
        .read(canvasProvider.notifier)
        .addPipelineDagNode(
          widget.phase,
          PipelineDagNode(
            id: 'node_${DateTime.now().millisecondsSinceEpoch}',
            type: type,
            x: scenePos.dx,
            y: scenePos.dy,
            parameters: type.defaultParameters,
          ),
          preferRight: !widget.isVertical,
        );
  }
}

// ── Edge painter ──────────────────────────────────────────────────────────────

class _PipelineEdgePainter extends CustomPainter {
  _PipelineEdgePainter({
    required this.dag,
    this.connectingPoint,
    this.connectingFromOffset,
    this.selectedEdgeId,
    required this.selectionColor,
    required this.previewWireColor,
    this.isVertical = false,
    this.sceneOrigin = Offset.zero,
  });

  final PipelineDAG dag;

  /// Edge currently selected, drawn thicker and in [selectionColor] so it is
  /// obvious which wire the `✕` and the Delete key will remove.
  final String? selectedEdgeId;

  final Color selectionColor;

  /// Neutral grey for the live-wire preview (dragged port). Resolved from the
  /// active Zeta theme by the caller — paint() has no BuildContext.
  final Color previewWireColor;

  /// Scene-space pointer position for the live-wire preview. Null when idle.
  final Offset? connectingPoint;

  /// Scene-space position of the active source port for the live-wire preview.
  final Offset? connectingFromOffset;

  /// Matches [PipelinePhaseCanvas.isVertical] -- selects bottom-to-top edge
  /// endpoints (ports on top/bottom edges) instead of right-to-left.
  final bool isVertical;
  final Offset sceneOrigin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(sceneOrigin.dx, sceneOrigin.dy);
    for (final edge in dag.edges) {
      final ends = pipelineEdgeEndpoints(dag, edge, isVertical: isVertical);
      if (ends == null) continue;
      final bool isSelected = edge.id == selectedEdgeId;
      drawCanvasEdge(
        canvas,
        ends.start,
        ends.end,
        isSelected ? selectionColor : canvasPortTypeColor(ends.type),
        isVertical: isVertical,
        strokeWidth: canvasEdgeStrokeWidth(isSelected: isSelected),
      );
    }

    // Live-wire preview while dragging from an output port.
    if (connectingFromOffset != null && connectingPoint != null) {
      drawCanvasEdge(
        canvas,
        connectingFromOffset!,
        connectingPoint!,
        previewWireColor,
        isVertical: isVertical,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PipelineEdgePainter old) =>
      old.dag != dag ||
      old.connectingPoint != connectingPoint ||
      old.connectingFromOffset != connectingFromOffset ||
      old.selectedEdgeId != selectedEdgeId ||
      old.selectionColor != selectionColor ||
      old.previewWireColor != previewWireColor ||
      old.sceneOrigin != sceneOrigin ||
      old.isVertical != isVertical;
}

// ── Node widget ────────────────────────────────────────────────────────────────

/// A single DAG node card rendered on the pipeline canvas.
///
/// The widget uses [CanvasPortWidget] for its ports — the same shared widget
/// used by the Architecture canvas — so all canvases have identical port
/// behaviour: pan from an output port to drag-to-connect with live-wire
/// preview, or tap to toggle the active connection source; tap an input port
/// to complete a pending connection.
class _PipelineDagNodeWidget extends ConsumerWidget {
  const _PipelineDagNodeWidget({
    super.key,
    required this.node,
    required this.dag,
    required this.phase,
    required this.isSelected,
    required this.connectingFromNodeId,
    required this.connectingFromPort,
    this.connectingPortType,
    required this.onTap,
    this.onDoubleTap,
    required this.onPanUpdate,
    required this.onOutputPortTap,
    required this.onInputPortTap,
    required this.onPortPanUpdate,
    required this.onPortPanEnd,
    this.armedPortNodeId,
    this.armedPortId,
    this.isVertical = false,
  });

  final PipelineDagNode node;
  final PipelineDAG dag;
  final PipelinePhaseId phase;
  final bool isSelected;
  final String? connectingFromNodeId;
  final String? connectingFromPort;

  /// See [PipelinePhaseCanvas.isVertical].
  final bool isVertical;

  /// Pipeline data type of the port being dragged. null = no drag or unknown.
  final PortType? connectingPortType;

  /// Returns true if [inputPort] is type-compatible with the port being dragged.
  bool _isPortCompatible(PortSpec inputPort) {
    final srcType = connectingPortType;
    if (srcType == null) return true;
    if (inputPort.type == PortType.any) return true;
    if (srcType == PortType.any) return true;
    return srcType == inputPort.type;
  }

  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(DragUpdateDetails) onPanUpdate;
  final void Function(String portId) onOutputPortTap;
  final void Function(String portId) onInputPortTap;

  /// Called with (portId, globalPosition) during an output-port pan drag.
  /// The canvas state converts global→scene coords and updates the live wire.
  final void Function(String portId, Offset global) onPortPanUpdate;

  /// Called with (portId) when an output-port pan ends.
  /// The canvas state resolves the nearest compatible input port.
  final void Function(String portId) onPortPanEnd;

  /// The port whose *next* tap opens the add-node palette rather than arming a
  /// connection. Drives the stronger `+` treatment on that one dot.
  final String? armedPortNodeId;
  final String? armedPortId;

  bool _isArmed(String portId) =>
      armedPortNodeId == node.id && armedPortId == portId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final accent = pipelineCategoryColor(node.type.category);
    final Size cardSize = pipelineDagNodeSize(node, compact: isVertical);
    final bool armedForDelete = ref.watch(
      armedForDeleteNodeIdProvider.select((String? id) => id == node.id),
    );

    // Input ports get [onTap] only — with no pan recognizer registered, a drag
    // that starts over an input port still pans the canvas. Output ports also
    // register pan handlers, which beat [InteractiveViewer]'s scale recognizer
    // so dragging from an output port draws a wire instead of moving the view.
    List<CanvasCardPort> portsFor(
      List<PortSpec> specs, {
      required bool isInput,
    }) => <CanvasCardPort>[
      for (final PortSpec spec in specs)
        CanvasCardPort(
          id: spec.id,
          label: spec.id,
          isInput: isInput,
          isActive:
              connectingFromNodeId == node.id && connectingFromPort == spec.id,
          canAcceptConnection:
              isInput &&
              connectingFromNodeId != null &&
              connectingFromNodeId != node.id &&
              _isPortCompatible(spec),
          isArmed: _isArmed(spec.id),
          tooltip: _isArmed(spec.id)
              ? (isInput
                    ? 'Tap again to add a node feeding "${spec.id}"'
                    : 'Tap again to add a node fed by "${spec.id}"')
              : spec.hint ?? 'Tap to connect, tap again to add a node',
          onTap: () {
            if (isInput) {
              onInputPortTap(spec.id);
            } else {
              onOutputPortTap(spec.id);
            }
          },
          onPanStart: isInput
              ? null
              : (_) {
                  ref
                      .read(canvasProvider.notifier)
                      .startConnecting(node.id, spec.id);
                },
          onPanUpdate: isInput
              ? null
              : (DragUpdateDetails d) =>
                    onPortPanUpdate(spec.id, d.globalPosition),
          onPanEnd: isInput ? null : (_) => onPortPanEnd(spec.id),
        ),
    ];

    return CanvasNodeCard(
      nodeId: node.id,
      cardSize: cardSize,
      accentColor: accent,
      icon: pipelineCategoryIcon(node.type.category),
      title: node.type.label,
      subtitle: pipelineNodeKeyParam(node),
      background: tokens.utilityPanelBackground,
      isSelected: isSelected,
      compact: isVertical,
      isConnecting: connectingFromNodeId != null,
      ports: <CanvasCardPort>[
        ...portsFor(node.type.inputPorts, isInput: true),
        ...portsFor(node.type.outputPorts, isInput: false),
      ],
      armedForDelete: armedForDelete,
      onDelete: () {
        ref.read(canvasProvider.notifier).removePipelineDagNode(phase, node.id);
        ref.read(armedForDeleteNodeIdProvider.notifier).set(null);
      },
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onPanStart: (_) => onTap(),
      onPanUpdate: onPanUpdate,
      onPanEnd: (_) => ref
          .read(canvasProvider.notifier)
          .snapPipelineDagNodeToGrid(phase, node.id),
      onLongPress: () =>
          ref.read(armedForDeleteNodeIdProvider.notifier).set(node.id),
    );
  }
}
