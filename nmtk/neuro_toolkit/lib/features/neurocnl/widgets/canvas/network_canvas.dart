import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/models/port_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_selectors.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_focus_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_line_node_map_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_node_subtitle.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_resolver.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_suggestions.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_connect_palette.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_edge_painting.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_minimap.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_stylus_layer.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';

// Card footprint, port placement, hit-target sizes: models/canvas/
// node_geometry.dart, re-exported by canvas_shared_widgets.dart and shared
// with the Train/Eval canvases.
const CanvasWorldGeometry _networkWorld = CanvasWorldGeometry(
  Size(10000, 10000),
);

/// On-canvas footprint of [node]'s card.
///
/// A node's persisted `width`/`height` are deliberately not consulted: cards
/// are fixed-size on every canvas (there is no resize affordance), and reading
/// them is what let the Architecture cards drift to a different size from the
/// Train/Eval ones. The fields stay on the model so existing workspace files
/// keep loading and re-saving unchanged.
Size networkNodeSize(
  CanvasNode node,
  NirNodeType? nodeType, {
  required bool compact,
}) {
  final List<NirPortDef> ports = nodeType?.ports ?? const <NirPortDef>[];
  return canvasNodeSize(
    inputs: ports.where((NirPortDef p) => p.direction == 'input').length,
    outputs: ports.where((NirPortDef p) => p.direction == 'output').length,
    compact: compact,
    collapsed: !node.isVisible,
  );
}

/// Node-local centre of the [index]th input/output port on [node]'s card.
Offset networkPortCentre({
  required CanvasNode node,
  required int index,
  required int count,
  required Size cardSize,
  required bool isInput,
  required bool compact,
}) => canvasNodePortCentre(
  index: index,
  count: count,
  cardSize: cardSize,
  isInput: isInput,
  compact: compact,
  collapsed: !node.isVisible,
);

typedef PortPanUpdateCallback =
    void Function(String portId, Offset localPosition, Offset globalPosition);
typedef PortPanEndCallback = void Function(String portId);

/// A single input-port match found by [findNearestInputPort].
typedef NearestPortMatch = ({
  String nodeId,
  NirPortDef port,
  double distance,
  Offset portPosition,
});

/// Finds the input port nearest [scenePos] across every node in [graph]
/// except [excludeNodeId].
///
/// A node is only considered if [scenePos] falls inside its bounding rect
/// inflated by `kCanvasPortRadius * 2`. Within a considered node, [isCompatible]
/// (if supplied) filters out ports before the nearest-of-the-remaining
/// comparison runs; a null [isCompatible] considers every input port.
///
/// A match is accepted, and the search stops at the first qualifying node
/// (in `graph.nodes` order), when the node has exactly one input port
/// (bypassing the distance check) or the nearest port is closer than
/// [maxDistance]. A multi-port node whose nearest port exceeds
/// [maxDistance] is skipped, not rejected outright -- the search continues
/// to the next node.
NearestPortMatch? findNearestInputPort(
  CanvasGraph graph,
  Map<String, NirNodeType> nirTypeMap,
  Offset scenePos, {
  required String excludeNodeId,
  double maxDistance = 64.0,
  bool Function(CanvasNode node, NirPortDef port)? isCompatible,
  bool isVertical = false,
}) {
  for (final CanvasNode node in graph.nodes) {
    if (node.id == excludeNodeId) {
      continue;
    }
    final NirNodeType? nodeType = nirTypeMap[node.nirType ?? node.componentId];
    if (nodeType == null) {
      continue;
    }
    final List<NirPortDef> inputPorts = nodeType.ports
        .where((NirPortDef p) => p.direction == 'input')
        .toList();
    if (inputPorts.isEmpty) {
      continue;
    }

    final Size cardSize = networkNodeSize(node, nodeType, compact: isVertical);
    final Rect rect = Rect.fromLTWH(
      node.position[0],
      node.position[1],
      cardSize.width,
      cardSize.height,
    );
    if (!rect.inflate(kCanvasPortRadius * 2).contains(scenePos)) {
      continue;
    }

    final Offset nodeOrigin = Offset(node.position[0], node.position[1]);
    NirPortDef? closestPort;
    Offset? closestPortPosition;
    double minDistance = double.infinity;
    for (int i = 0; i < inputPorts.length; i += 1) {
      final NirPortDef candidatePort = inputPorts[i];
      if (isCompatible != null && !isCompatible(node, candidatePort)) {
        continue;
      }
      final Offset portPos =
          nodeOrigin +
          networkPortCentre(
            node: node,
            index: i,
            count: inputPorts.length,
            cardSize: cardSize,
            isInput: true,
            compact: isVertical,
          );
      final double distance = (scenePos - portPos).distance;
      if (distance < minDistance) {
        minDistance = distance;
        closestPort = candidatePort;
        closestPortPosition = portPos;
      }
    }

    if (closestPort != null &&
        (inputPorts.length == 1 || minDistance < maxDistance)) {
      return (
        nodeId: node.id,
        port: closestPort,
        distance: minDistance,
        portPosition: closestPortPosition!,
      );
    }
  }
  return null;
}

/// Midpoint of the wire drawn between two port centres — where the edge `✕`
/// and the learning-rule badge sit. Alias for the shared
/// [canvasEdgeMidpoint].
Offset connectionCurveMidpoint(Offset source, Offset target) =>
    canvasEdgeMidpoint(source, target);

/// True when [inputPort] on [targetNode] can accept a connection dragged
/// from a port of type [connectingPortType]. A null [connectingPortType]
/// (no type constraint inferred) always accepts.
bool _canAcceptConnection(
  PortType? connectingPortType,
  CanvasNode targetNode,
  NirPortDef inputPort,
) {
  if (connectingPortType == null) {
    return true;
  }
  final Map<String, PortType>? tgtTypes = inferNirPortTypes(
    targetNode.nirType,
    targetNode.parameters,
  );
  if (tgtTypes == null) {
    return true;
  }
  final PortType? tgtType = tgtTypes[inputPort.id];
  if (tgtType == null) {
    return true;
  }
  return connectingPortType.isCompatibleWith(tgtType);
}

class NetworkCanvas extends ConsumerStatefulWidget {
  const NetworkCanvas({super.key, this.onNodeDoubleTap, this.isVertical});

  final VoidCallback? onNodeDoubleTap;

  /// Overrides the mobile/vertical layout signal (node header + port
  /// placement) with a caller-measured value -- e.g. the local width of a
  /// split pipeline-stepper pane, which can be narrow even on a full
  /// desktop window. When null, falls back to a window-width MediaQuery
  /// check ([_computeIsVertical]) for embeddings that don't measure locally.
  final bool? isVertical;

  @override
  ConsumerState<NetworkCanvas> createState() => _NetworkCanvasState();
}

/// Returns true when the screen width is less than
/// [NmtkShellTokens.compactBreakpoint] logical pixels.
bool _computeIsVertical(BuildContext context) =>
    MediaQuery.sizeOf(context).width < NmtkShellTokens.compactBreakpoint;

class _NetworkCanvasState extends ConsumerState<NetworkCanvas>
    with
        SingleTickerProviderStateMixin,
        CanvasViewportMixin<NetworkCanvas>,
        CanvasStylusMixin<NetworkCanvas> {
  Offset? _currentConnectingPoint;

  // Set while a stylus is hovering (pre-touch) near the single nearest
  // compatible input port during an in-progress connection drag -- see
  // _handleAmbientPointerHover. Null whenever there is no such candidate.
  String? _hoverCandidateNodeId;
  String? _hoverCandidatePortId;

  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();
  bool _syncingViewportFromState = false;
  bool _isVertical = false;
  int _handledWorkspaceRestoreFocusRevision = 0;

  /// Drives the animated pan-to-node triggered when a new node is added --
  /// see [_followPendingViewportFocus]. Built eagerly in [initState] rather
  /// than via a lazy `late` initializer: if the controller is never read
  /// until [dispose] (e.g. no node was ever added), a lazy initializer would
  /// construct it -- and call `vsync: this` -- while the widget is already
  /// deactivated, which crashes.
  late final AnimationController _viewportFollowController;

  // Stylus/pen support state. The lasso and handwriting-popup state itself
  // lives in CanvasStylusMixin, shared with the Train/Eval canvases.
  double _latestPointerPressure = 1.0;
  PointerDeviceKind? _lastDoubleTapDownKind;
  String? _pendingCnlFocusNodeId;
  int? _cnlFocusPointerId;
  Offset? _cnlFocusPointerStart;

  bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get _isPrimaryModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  @override
  void initState() {
    super.initState();
    _transformationController.value = _worldMatrix(zoom: 1, pan: Offset.zero);
    _viewportFollowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _transformationController.addListener(_handleViewportChanged);
  }

  @override
  CanvasWorldGeometry get canvasWorld => _networkWorld;

  @override
  TransformationController get canvasTransform => _transformationController;

  Offset _sceneFromViewport(Offset viewportPosition) =>
      canvasSceneFromViewport(viewportPosition);

  Matrix4 _worldMatrix({required double zoom, required Offset pan}) =>
      canvasWorldMatrix(zoom: zoom, pan: pan);

  @override
  void dispose() {
    canvasDisposeStylusLayer();
    _transformationController.removeListener(_handleViewportChanged);
    _transformationController.dispose();
    _viewportFollowController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Narrowly scoped to exactly the fields this build method reads —
    // notably NOT `selectedNodeIds`, so a node-selection click (a plain
    // `copyWith` that leaves `graph`/`connectingFrom*`/`selectedEdgeId`
    // untouched) doesn't rebuild this ~300-line method and every node
    // widget in it. Each `_CanvasNodeWidget` watches its own selection
    // membership independently below.
    final (
      CanvasGraph graph,
      String? connectingFromNodeId,
      String? connectingFromPortId,
      String? selectedEdgeId,
    ) = ref.watch(
      canvasProvider.select(
        (CanvasState s) => (
          s.graph,
          s.connectingFromNodeId,
          s.connectingFromPortId,
          s.selectedEdgeId,
        ),
      ),
    );
    ref.listen<String?>(
      canvasProvider.select((CanvasState s) => s.pendingViewportFocusNodeId),
      (String? previous, String? next) {
        if (next != null) _followPendingViewportFocus(next);
      },
    );
    // A listen, NOT a watch: reading the viewport during build would rebuild
    // this whole method on every pan frame — exactly the cost that moving the
    // viewport off `graph` was meant to remove. This only has to fire when
    // something *other* than the gesture moves the camera (resetViewport).
    ref.listen<CanvasViewport>(
      canvasProvider.select((CanvasState s) => s.viewport),
      (CanvasViewport? previous, CanvasViewport next) =>
          _syncViewportFromState(next),
    );
    final Map<String, NirNodeType> nirTypeMap = ref.watch(
      nirNodeTypeMapProvider,
    );
    final int workspaceRestoreFocusRevision = ref.watch(
      canvasProvider.select((CanvasState s) => s.workspaceRestoreFocusRevision),
    );
    _scheduleWorkspaceRestoreFocus(workspaceRestoreFocusRevision);
    final focus = ref.watch(cnlFocusProvider);
    final lineMap = ref.watch(cnlLineNodeMapProvider);
    final String? glowNodeId =
        focus.focusedNodeId ?? lineMap.lineToNode[focus.focusedLine];
    final canvasNotifier = ref.read(canvasProvider.notifier);
    final cnlFocusNotifier = ref.read(cnlFocusProvider.notifier);
    final bool isVertical = widget.isVertical ?? _computeIsVertical(context);
    _isVertical = isVertical;

    // Infer the type of the port currently being dragged (null = no drag).
    final PortType? connectingPortType = _inferConnectingPortType(
      connectingFromNodeId,
      connectingFromPortId,
      graph,
    );

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleAmbientPointerDown,
        onPointerMove: _handleAmbientPointerMove,
        onPointerUp: _handleAmbientPointerUp,
        onPointerHover: _handleAmbientPointerHover,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = constraints.biggest;
            return Container(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ValueListenableBuilder<Matrix4>(
                      valueListenable: _transformationController,
                      builder:
                          (BuildContext ctx, Matrix4 transform, Widget? _) {
                            return CustomPaint(
                              painter: GridPainter(
                                transform: transform,
                                sceneOrigin: _networkWorld.origin,
                                lineColor: Theme.of(
                                  ctx,
                                ).colorScheme.onSurface.withValues(alpha: 0.07),
                              ),
                            );
                          },
                    ),
                  ),
                  Positioned.fill(
                    child: DragTarget<NirNodeType>(
                      onAcceptWithDetails:
                          (DragTargetDetails<NirNodeType> details) {
                            _handleNodeDrop(details);
                          },
                      builder:
                          (
                            BuildContext context,
                            List<NirNodeType?> _,
                            List<dynamic> _,
                          ) {
                            return RawGestureDetector(
                              behavior: HitTestBehavior.translucent,
                              gestures: <Type, GestureRecognizerFactory>{
                                TapGestureRecognizer:
                                    GestureRecognizerFactoryWithHandlers<
                                      TapGestureRecognizer
                                    >(() => TapGestureRecognizer(), (
                                      TapGestureRecognizer instance,
                                    ) {
                                      instance
                                          .onTapDown = (TapDownDetails details) {
                                        if (!mounted) return;
                                        _focusNode.requestFocus();
                                        // Any tap on the canvas disarms a
                                        // pending long-press delete; the
                                        // trash badge itself has its own
                                        // opaque tap target that handles the
                                        // deletion before this fires (same
                                        // pattern as CanvasEdgeDeleteButton).
                                        ref
                                            .read(
                                              armedForDeleteNodeIdProvider
                                                  .notifier,
                                            )
                                            .set(null);
                                        final Offset scenePos =
                                            _sceneFromViewport(
                                              details.localPosition,
                                            );
                                        final CanvasNode? tappedNode =
                                            _nodeAtPosition(scenePos, graph);
                                        final CanvasEdge? tappedEdge =
                                            _findEdgeAtPosition(
                                              scenePos,
                                              graph,
                                              nirTypeMap,
                                            );
                                        if (tappedNode != null) {
                                          if (_isPrimaryModifierPressed) {
                                            canvasNotifier.toggleNodeSelection(
                                              tappedNode.id,
                                              additive: true,
                                            );
                                            _pendingCnlFocusNodeId = null;
                                          } else {
                                            canvasNotifier.selectNode(
                                              tappedNode.id,
                                            );
                                            _pendingCnlFocusNodeId =
                                                lineMap.nodeToLine.containsKey(
                                                  tappedNode.id,
                                                )
                                                ? tappedNode.id
                                                : null;
                                          }
                                        } else if (tappedEdge != null) {
                                          _pendingCnlFocusNodeId = null;
                                          _clearArmedPort();
                                          canvasNotifier.selectEdge(
                                            tappedEdge.id,
                                          );
                                        } else if (!_isPrimaryModifierPressed) {
                                          _pendingCnlFocusNodeId = null;
                                          _clearArmedPort();
                                          canvasNotifier.clearSelection();
                                        }
                                      };
                                      instance.onTap = () {
                                        if (!mounted) return;
                                        final String? nodeId =
                                            _pendingCnlFocusNodeId;
                                        _pendingCnlFocusNodeId = null;
                                        if (nodeId == null) return;
                                        cnlFocusNotifier.setFocusedNode(nodeId);
                                      };
                                    }),
                                // Lasso-select / handwriting-to-node, wired
                                // identically on every canvas.
                                ...canvasStylusGestures,
                              },
                              child: InteractiveViewer(
                                constrained: false,
                                transformationController:
                                    _transformationController,
                                boundaryMargin: const EdgeInsets.all(5000),
                                minScale: kCanvasMinZoom,
                                maxScale: kCanvasMaxZoom,
                                child: SizedBox(
                                  width: _networkWorld.size.width,
                                  height: _networkWorld.size.height,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size.infinite,
                                          painter: ConnectionPainter(
                                            graph: graph,
                                            nirTypeMap: nirTypeMap,
                                            connectingFromNodeId:
                                                connectingFromNodeId,
                                            connectingFromPortId:
                                                connectingFromPortId,
                                            currentConnectingPoint:
                                                _currentConnectingPoint,
                                            currentConnectingPressure:
                                                _latestPointerPressure,
                                            selectedEdgeId: selectedEdgeId,
                                            // Matches the pipeline canvases'
                                            // selectionColor and the node
                                            // selection border color
                                            // (NodeCardChrome), instead of
                                            // colorScheme.primary -- a
                                            // different, only-similar-hued
                                            // value that made a selected wire
                                            // not quite match a selected node
                                            // on this same canvas.
                                            primaryColor: NmtkShellTokens.of(
                                              context,
                                            ).studioPalette.accent,
                                            outlineColor: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                            badgeAccentColor: Zeta.of(
                                              context,
                                            ).colors.mainInverse,
                                            isVertical: isVertical,
                                            sceneOrigin: _networkWorld.origin,
                                          ),
                                        ),
                                      ),
                                      ...graph.nodes.map((CanvasNode node) {
                                        final NirNodeType? nodeType =
                                            _resolveType(nirTypeMap, node);
                                        void selectStructurally() {
                                          _focusNode.requestFocus();
                                          final notifier = ref.read(
                                            canvasProvider.notifier,
                                          );
                                          if (_isPrimaryModifierPressed) {
                                            notifier.toggleNodeSelection(
                                              node.id,
                                              additive: true,
                                            );
                                          } else {
                                            notifier.selectNode(node.id);
                                          }
                                        }

                                        void selectAndFocusCnl() {
                                          selectStructurally();
                                          if (_isPrimaryModifierPressed) return;
                                          if (lineMap.nodeToLine.containsKey(
                                            node.id,
                                          )) {
                                            ref
                                                .read(cnlFocusProvider.notifier)
                                                .setFocusedNode(node.id);
                                          } else {
                                            ref
                                                .read(cnlFocusProvider.notifier)
                                                .setFocusedNode(null);
                                          }
                                        }

                                        return _CanvasNodeWidget(
                                          key: ValueKey<String>(
                                            'node_${node.id}',
                                          ),
                                          node: node,
                                          nodeType: nodeType,
                                          isGlowing: glowNodeId == node.id,
                                          connectingFromNodeId:
                                              connectingFromNodeId,
                                          connectingFromPortId:
                                              connectingFromPortId,
                                          connectingPortType:
                                              connectingPortType,
                                          hoverCandidateNodeId:
                                              _hoverCandidateNodeId,
                                          hoverCandidatePortId:
                                              _hoverCandidatePortId,
                                          transformationController:
                                              _transformationController,
                                          sceneOrigin: _networkWorld.origin,
                                          isVertical: isVertical,
                                          onTap: selectAndFocusCnl,
                                          onDragStart: selectStructurally,
                                          onDoubleTapDown:
                                              (PointerDeviceKind kind) {
                                                _lastDoubleTapDownKind = kind;
                                              },
                                          onDoubleTap: () {
                                            final bool isStylusDoubleTap =
                                                _lastDoubleTapDownKind ==
                                                PointerDeviceKind.stylus;
                                            if (isStylusDoubleTap &&
                                                ref
                                                    .read(canvasProvider)
                                                    .selectedNodeIds
                                                    .contains(node.id)) {
                                              ref
                                                  .read(canvasProvider.notifier)
                                                  .deleteSelection();
                                            } else {
                                              widget.onNodeDoubleTap?.call();
                                            }
                                          },
                                          onOutputPortTap: (String portId) {
                                            _focusNode.requestFocus();
                                            _handleOutputPortTap(
                                              node.id,
                                              portId,
                                            );
                                          },
                                          onInputPortTap: (String portId) {
                                            _focusNode.requestFocus();
                                            _handleInputPortTap(
                                              node.id,
                                              portId,
                                              nirTypeMap,
                                            );
                                          },
                                          onPortPanUpdate:
                                              (
                                                String portId,
                                                Offset localPos,
                                                Offset globalPos,
                                              ) {
                                                setState(() {
                                                  final RenderBox box =
                                                      context.findRenderObject()!
                                                          as RenderBox;
                                                  final Offset
                                                  localPosInCanvas = box
                                                      .globalToLocal(globalPos);
                                                  _currentConnectingPoint =
                                                      _sceneFromViewport(
                                                        localPosInCanvas,
                                                      );
                                                });
                                              },
                                          armedPortNodeId: _armedPortNodeId,
                                          armedPortId: _armedPortId,
                                          onPortPanEnd: (String portId) {
                                            if (_currentConnectingPoint !=
                                                null) {
                                              _handleConnectionDrop(
                                                node.id,
                                                portId,
                                                _currentConnectingPoint!,
                                                nirTypeMap,
                                              );
                                            }
                                            _resetConnectionHoverState();
                                          },
                                        );
                                      }),
                                      // Delete affordance for the selected edge.
                                      // Lives in the canvas Stack, not on a node,
                                      // because it belongs to the wire's midpoint.
                                      if (selectedEdgeId != null)
                                        ?() {
                                          final Offset? mid = _edgeMidpoint(
                                            graph,
                                            nirTypeMap,
                                            selectedEdgeId,
                                          );
                                          if (mid == null) return null;
                                          return Positioned(
                                            left:
                                                mid.dx +
                                                _networkWorld.origin.dx -
                                                kCanvasEdgeDeleteHitTargetSize /
                                                    2,
                                            top:
                                                mid.dy +
                                                _networkWorld.origin.dy -
                                                kCanvasEdgeDeleteHitTargetSize /
                                                    2,
                                            child: CanvasEdgeDeleteButton(
                                              key: const ValueKey<String>(
                                                'nir_edge_delete',
                                              ),
                                              onPressed: () {
                                                _focusNode.requestFocus();
                                                ref
                                                    .read(
                                                      canvasProvider.notifier,
                                                    )
                                                    .removeEdge(selectedEdgeId);
                                              },
                                            ),
                                          );
                                        }(),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                    ),
                  ),
                  if (canvasLassoStart != null && canvasLassoEnd != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: MarqueeSelectionPainter(
                          start: canvasLassoStart!,
                          end: canvasLassoEnd!,
                          transform: _transformationController.value,
                          sceneOrigin: _networkWorld.origin,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Positioned(
                    left: _isVertical ? null : 16,
                    top: _isVertical ? 16 : null,
                    right: _isVertical ? 16 : null,
                    bottom: _isVertical ? null : 16,
                    child: CanvasMinimapWidget(
                      nodes: graph.nodes.map((CanvasNode node) {
                        final NirNodeType? nodeType = _resolveType(
                          nirTypeMap,
                          node,
                        );
                        final Size cardSize = networkNodeSize(
                          node,
                          nodeType,
                          compact: _isVertical,
                        );
                        return MinimapNode(
                          Rect.fromLTWH(
                            node.position[0],
                            node.position[1],
                            cardSize.width,
                            cardSize.height,
                          ),
                          nodeType != null
                              ? nirCategoryColor(context, nodeType.category)
                              : Zeta.of(context).colors.mainSubtle,
                        );
                      }).toList(),
                      edgeLines: graph.edges
                          .map((CanvasEdge edge) {
                            final Offset? source = _getPortPosition(
                              graph,
                              nirTypeMap,
                              edge.sourceNodeId,
                              edge.sourcePort,
                              false,
                            );
                            final Offset? target = _getPortPosition(
                              graph,
                              nirTypeMap,
                              edge.targetNodeId,
                              edge.targetPort,
                              true,
                            );
                            if (source != null && target != null) {
                              return MinimapEdgeLine(source, target);
                            }
                            return null;
                          })
                          .whereType<MinimapEdgeLine>()
                          .toList(),
                      transformationController: _transformationController,
                      viewportSize: viewportSize,
                      onJumpTo: (Offset scenePoint) {
                        final double zoom = _transformationController.value
                            .getMaxScaleOnAxis();
                        final Offset pan = centeredPanFor(
                          scenePoint,
                          zoom,
                          viewportSize,
                        );
                        _transformationController.value = _worldMatrix(
                          zoom: zoom,
                          pan: pan,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  NirNodeType? _resolveType(
    Map<String, NirNodeType> nirTypeMap,
    CanvasNode node,
  ) {
    return nirTypeMap[node.nirType ?? node.componentId];
  }

  void _handleViewportChanged() {
    if (_syncingViewportFromState) {
      return;
    }

    final Matrix4 matrix = _transformationController.value;
    ref
        .read(canvasProvider.notifier)
        .updateViewport(
          zoom: matrix.getMaxScaleOnAxis(),
          pan: <double>[
            matrix.storage[12] +
                _networkWorld.origin.dx * matrix.getMaxScaleOnAxis(),
            matrix.storage[13] +
                _networkWorld.origin.dy * matrix.getMaxScaleOnAxis(),
          ],
        );
  }

  void _syncViewportFromState(CanvasViewport viewport) {
    final Matrix4 matrix = _transformationController.value;
    final CanvasViewport controllerViewport = CanvasViewport(
      zoom: matrix.getMaxScaleOnAxis(),
      pan: <double>[
        matrix.storage[12] +
            _networkWorld.origin.dx * matrix.getMaxScaleOnAxis(),
        matrix.storage[13] +
            _networkWorld.origin.dy * matrix.getMaxScaleOnAxis(),
      ],
    );
    if (controllerViewport.isCloseTo(viewport)) {
      return;
    }

    _syncingViewportFromState = true;
    _transformationController.value = _worldMatrix(
      zoom: viewport.zoom,
      pan: Offset(viewport.pan[0], viewport.pan[1]),
    );
    _syncingViewportFromState = false;
  }

  void _scheduleWorkspaceRestoreFocus(int revision) {
    if (revision == 0 || revision == _handledWorkspaceRestoreFocusRevision) {
      return;
    }
    _handledWorkspaceRestoreFocusRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final CanvasGraph graph = ref.read(canvasProvider).graph;
      if (graph.nodes.isEmpty) return;
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final CanvasNode node = graph.nodes.first;
      final double zoom = _transformationController.value.getMaxScaleOnAxis();
      final Offset pan = anchoredPanFor(
        Offset(
          node.position[0] + node.width / 2,
          node.position[1] + node.height / 2,
        ),
        zoom,
        box.size,
      );
      _transformationController.value = _worldMatrix(zoom: zoom, pan: pan);
    });
  }

  /// Animates the viewport to center [nodeId] (keeping the current zoom)
  /// then clears the pending signal so it doesn't re-trigger on unrelated
  /// rebuilds. Triggered by [CanvasController.addNode] /
  /// [CanvasController.addPipelineDagNode] setting
  /// `pendingViewportFocusNodeId` -- see the `ref.listen` in [build].
  void _followPendingViewportFocus(String nodeId) {
    final canvasNotifier = ref.read(canvasProvider.notifier);
    canvasNotifier.clearPendingViewportFocusNodeId();

    CanvasNode? node;
    for (final CanvasNode n in ref.read(canvasProvider).graph.nodes) {
      if (n.id == nodeId) {
        node = n;
        break;
      }
    }
    if (node == null) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final Matrix4 current = _transformationController.value;
    final double zoom = current.getMaxScaleOnAxis();
    final Offset sceneCenter = Offset(
      node.position[0] + node.width / 2,
      node.position[1] + node.height / 2,
    );
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
    listener = () => _transformationController.value = animation.value;
    animation.addListener(listener);
    _viewportFollowController
      ..reset()
      ..forward().whenCompleteOrCancel(
        () => animation.removeListener(listener),
      );
  }

  // ── Ambient pointer observation (stylus pressure/hover/eraser) ──────────
  //
  // A plain Listener never joins the gesture arena, so it is always safe
  // here regardless of placement -- it cannot steal pointers from
  // InteractiveViewer or any node/port GestureDetector. It is used only to
  // observe things those higher-level widgets don't expose: pressure during
  // moves (DragUpdateDetails has no pressure field), hover before contact,
  // and inverted-stylus (eraser tip) detection.

  void _handleAmbientPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.invertedStylus) {
      _eraseAt(event.position);
      return;
    }
    if (_isPrimaryModifierPressed) return;
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    final Offset scenePos = _sceneFromViewport(event.localPosition);
    final CanvasNode? node = _nodeAtPosition(scenePos, graph);
    if (node == null) return;
    _cnlFocusPointerId = event.pointer;
    _cnlFocusPointerStart = event.position;
    _pendingCnlFocusNodeId = node.id;
  }

  void _handleAmbientPointerMove(PointerMoveEvent event) {
    if (_cnlFocusPointerId == event.pointer &&
        _cnlFocusPointerStart != null &&
        (event.position - _cnlFocusPointerStart!).distance > kTouchSlop) {
      _pendingCnlFocusNodeId = null;
    }
    if (event.kind == PointerDeviceKind.stylus) {
      _latestPointerPressure = event.pressure;
    }
  }

  void _handleAmbientPointerUp(PointerUpEvent event) {
    if (_cnlFocusPointerId != event.pointer) return;
    final String? nodeId = _pendingCnlFocusNodeId;
    _cnlFocusPointerId = null;
    _cnlFocusPointerStart = null;
    _pendingCnlFocusNodeId = null;
    if (nodeId == null) return;
    if (!ref.read(cnlLineNodeMapProvider).nodeToLine.containsKey(nodeId)) {
      ref.read(cnlFocusProvider.notifier).setFocusedNode(null);
      return;
    }
    ref.read(cnlFocusProvider.notifier).setFocusedNode(nodeId);
  }

  void _handleAmbientPointerHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.stylus) {
      return;
    }
    final CanvasState canvasState = ref.read(canvasProvider);
    final String? sourceNodeId = canvasState.connectingFromNodeId;
    if (sourceNodeId == null) {
      return;
    }

    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset localPos = box.globalToLocal(event.position);
    final Offset scenePos = _sceneFromViewport(localPos);

    final PortType? connectingPortType = _inferConnectingPortType(
      canvasState.connectingFromNodeId,
      canvasState.connectingFromPortId,
      canvasState.graph,
    );
    final Map<String, NirNodeType> nirTypeMap = ref.read(
      nirNodeTypeMapProvider,
    );
    final NearestPortMatch? candidate = findNearestInputPort(
      canvasState.graph,
      nirTypeMap,
      scenePos,
      excludeNodeId: sourceNodeId,
      isCompatible: (CanvasNode node, NirPortDef port) =>
          _canAcceptConnection(connectingPortType, node, port),
      isVertical: _isVertical,
    );

    setState(() {
      _hoverCandidateNodeId = candidate?.nodeId;
      _hoverCandidatePortId = candidate?.port.id;
      _currentConnectingPoint = candidate?.portPosition ?? scenePos;
    });
  }

  /// Resolves the [PortType] of the port currently being dragged from, or
  /// null when no connection is in progress.
  PortType? _inferConnectingPortType(
    String? connectingFromNodeId,
    String? connectingFromPortId,
    CanvasGraph graph,
  ) {
    if (connectingFromNodeId == null || connectingFromPortId == null) {
      return null;
    }
    for (final CanvasNode n in graph.nodes) {
      if (n.id == connectingFromNodeId) {
        return inferNirPortTypes(
          n.nirType,
          n.parameters,
        )?[connectingFromPortId];
      }
    }
    return null;
  }

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

  CanvasNode? _firstNodeById(String id) {
    for (final CanvasNode node in ref.read(canvasProvider).graph.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// Clears the live connection-preview point and hover-candidate state.
  /// Called at every point a connection drag ends or is cancelled.
  void _resetConnectionHoverState() {
    // A drag consumed the port's intent, so a later single tap on it should arm
    // afresh rather than jump straight to the palette.
    _clearArmedPort();
    if (_currentConnectingPoint == null &&
        _hoverCandidateNodeId == null &&
        _hoverCandidatePortId == null) {
      return;
    }
    setState(() {
      _currentConnectingPoint = null;
      _hoverCandidateNodeId = null;
      _hoverCandidatePortId = null;
    });
  }

  void _eraseAt(Offset globalPosition) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset scenePos = _sceneFromViewport(
      box.globalToLocal(globalPosition),
    );
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    final CanvasNode? node = _nodeAtPosition(scenePos, graph);
    if (node != null) {
      ref.read(canvasProvider.notifier).removeNode(node.id);
      return;
    }
    final CanvasEdge? edge = _findEdgeAtPosition(
      scenePos,
      graph,
      ref.read(nirNodeTypeMapProvider),
    );
    if (edge != null) {
      ref.read(canvasProvider.notifier).removeEdge(edge.id);
    }
  }

  // ── Stylus-on-empty-canvas: lasso selection & handwriting-to-node ───────
  //
  // The behaviour itself lives in CanvasStylusMixin (shared with the Train and
  // Eval canvases). These four hooks are the Architecture-specific parts: what
  // counts as empty canvas here, what "select in this rect" means, and how
  // handwritten text becomes a NIR node.

  @override
  bool canvasIsEmptyAt(Offset scenePosition) {
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    if (_nodeAtPosition(scenePosition, graph) != null) {
      return false;
    }
    final Map<String, NirNodeType> nirTypeMap = ref.read(
      nirNodeTypeMapProvider,
    );
    for (final CanvasNode node in graph.nodes) {
      final NirNodeType? nodeType = _resolveType(nirTypeMap, node);
      if (nodeType == null) {
        continue;
      }
      for (final NirPortDef port in nodeType.ports) {
        final Offset? portPos = _getPortPosition(
          graph,
          nirTypeMap,
          node.id,
          port.id,
          port.direction == 'input',
        );
        if (portPos != null &&
            (portPos - scenePosition).distance <=
                kCanvasPortHitTargetSize / 2) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  void canvasSelectInRect(Rect sceneRect) =>
      ref.read(canvasProvider.notifier).selectNodesInRect(sceneRect);

  @override
  List<String> canvasSuggestNodeTypes(String query) => suggestNirNodeTypes(
    query,
    ref.read(nirNodeTypeMapProvider),
  ).map((NirNodeType type) => type.displayName).toList();

  @override
  void canvasCreateNodeFromText(String text, Offset scenePosition) {
    final NirNodeType? type = resolveNirNodeType(
      text,
      ref.read(nirNodeTypeMapProvider),
    );
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
    _createNodeAt(type, scenePosition);
  }

  void _createNodeAt(NirNodeType type, Offset scenePos) {
    final String id = '${type.id}_${DateTime.now().millisecondsSinceEpoch}';
    final int nextIndex = ref.read(canvasProvider).graph.nodes.length + 1;

    ref
        .read(canvasProvider.notifier)
        .addNode(
          CanvasNode(
            id: id,
            componentId: type.legacyComponentId ?? type.id,
            nirType: type.isCustom ? type.baseNirType : type.id,
            label: type.displayName,
            parameters: <String, dynamic>{
              ...type.defaultParameters,
              'name': '${type.displayName} $nextIndex',
            },
            position: <double>[scenePos.dx, scenePos.dy],
            width: kCanvasNodeWidth,
            height: kCanvasNodeBaseHeight,
            metadata: <String, dynamic>{'category': type.category},
          ),
          preferRight: !_isVertical,
        );
  }

  /// Scene-space midpoint of [edgeId]'s curve — where its delete `✕` goes.
  ///
  /// Reuses [_getPortPosition] and the painter's own control points, so the
  /// button lands on the wire the user actually sees.
  Offset? _edgeMidpoint(
    CanvasGraph graph,
    Map<String, NirNodeType> nirTypeMap,
    String edgeId,
  ) {
    CanvasEdge? edge;
    for (final CanvasEdge e in graph.edges) {
      if (e.id == edgeId) edge = e;
    }
    if (edge == null) return null;

    final Offset? source = _getPortPosition(
      graph,
      nirTypeMap,
      edge.sourceNodeId,
      edge.sourcePort,
      false,
    );
    final Offset? target = _getPortPosition(
      graph,
      nirTypeMap,
      edge.targetNodeId,
      edge.targetPort,
      true,
    );
    if (source == null || target == null) return null;
    return connectionCurveMidpoint(source, target);
  }

  /// Opens the connect palette for [portId] on [sourceNode],
  /// then creates the chosen node already wired to it.
  ///
  /// [fromOutput] true means the new node goes downstream (`sourceNode → new`);
  /// false means upstream.
  Future<void> _handleAddFromPort({
    required CanvasNode? sourceNode,
    required String portId,
    required bool fromOutput,
    required Map<String, NirNodeType> nirTypeMap,
  }) async {
    if (sourceNode == null) return;
    // A half-finished tap-to-connect would otherwise remain armed behind the
    // modal and complete on the next input-port tap.
    ref.read(canvasProvider.notifier).cancelConnecting();
    _resetConnectionHoverState();

    // Selecting the source first makes the grid placer put the new node next to
    // it — same mechanism the palette add uses, no bespoke placement here.
    ref.read(canvasProvider.notifier).selectNode(sourceNode.id);

    // Direction-only filter: a candidate qualifies if it has any port on the
    // facing side. Port *types* are inferred from live parameters and often
    // unknown, so filtering on them would hide connectable nodes; the existing
    // `_createConnection` check still reports genuine mismatches.
    final String wantedDirection = fromOutput ? 'input' : 'output';
    final List<CanvasConnectPaletteEntry> entries = <CanvasConnectPaletteEntry>[
      for (final NirNodeType type in nirTypeMap.values)
        if (type.ports.any((NirPortDef p) => p.direction == wantedDirection))
          CanvasConnectPaletteEntry(
            id: type.id,
            label: type.displayName,
            icon: type.icon,
            accent: nirCategoryColor(context, type.category),
            ports: <CanvasConnectPalettePort>[
              for (final NirPortDef p in type.ports)
                if (p.direction == wantedDirection)
                  CanvasConnectPalettePort(id: p.id, label: p.label),
            ],
          ),
    ];

    if (entries.isEmpty) return;

    final CanvasConnectPaletteResult? result = await showCanvasConnectPalette(
      context: context,
      direction: fromOutput
          ? CanvasConnectDirection.fromOutput
          : CanvasConnectDirection.fromInput,
      entries: entries,
    );
    if (result == null || !mounted) return;

    final NirNodeType? type = nirTypeMap[result.entryId];
    if (type == null) return;

    final String newNodeId =
        '${type.id}_${DateTime.now().millisecondsSinceEpoch}';
    final int nextIndex = ref.read(canvasProvider).graph.nodes.length + 1;

    ref
        .read(canvasProvider.notifier)
        .addNodeWithEdge(
          CanvasNode(
            id: newNodeId,
            componentId: type.legacyComponentId ?? type.id,
            nirType: type.isCustom ? type.baseNirType : type.id,
            label: type.displayName,
            parameters: <String, dynamic>{
              ...type.defaultParameters,
              'name': '${type.displayName} $nextIndex',
            },
            position: <double>[sourceNode.position[0], sourceNode.position[1]],
            width: kCanvasNodeWidth,
            height: kCanvasNodeBaseHeight,
            metadata: <String, dynamic>{'category': type.category},
          ),
          (CanvasNode placed) => CanvasEdge(
            // Derived from the node id rather than a second timestamp — two
            // `millisecondsSinceEpoch` calls in one gesture can collide.
            id: 'edge_$newNodeId',
            sourceNodeId: fromOutput ? sourceNode.id : placed.id,
            sourcePort: fromOutput ? portId : result.portId,
            targetNodeId: fromOutput ? placed.id : sourceNode.id,
            targetPort: fromOutput ? result.portId : portId,
            parameters: const <String, dynamic>{
              'weight': 1.0,
              'delay': 0.0,
              'polarity': 'excitatory',
              'strokeWeight': 1.0,
            },
          ),
          preferRight: !_isVertical,
        );
  }

  CanvasNode? _nodeAtPosition(Offset pos, CanvasGraph graph) {
    final Map<String, NirNodeType> nirTypeMap = ref.read(
      nirNodeTypeMapProvider,
    );
    for (final CanvasNode node in graph.nodes.reversed) {
      final Size cardSize = networkNodeSize(
        node,
        _resolveType(nirTypeMap, node),
        compact: _isVertical,
      );
      final Rect bounds = Rect.fromLTWH(
        node.position[0],
        node.position[1],
        cardSize.width,
        cardSize.height,
      );
      if (bounds.contains(pos)) {
        return node;
      }
    }
    return null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(canvasProvider.notifier).cancelConnecting();
      _resetConnectionHoverState();
      _clearArmedPort();
      canvasDismissHandwritingPopup();
      return;
    }

    if (_isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.digit0) {
      ref.read(canvasProvider.notifier).resetViewport();
      return;
    }

    if (_isPrimaryModifierPressed &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      _adjustZoom(kCanvasZoomStep);
      return;
    }

    if (_isPrimaryModifierPressed &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _adjustZoom(1 / kCanvasZoomStep);
      return;
    }

    if (!_isDesktopPlatform) {
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        ref.read(canvasProvider.notifier).deleteSelection();
      }
      return;
    }

    final notifier = ref.read(canvasProvider.notifier);
    if (_isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(notifier.copySelection());
      return;
    }
    if (_isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(notifier.pasteClipboard());
      return;
    }
    if (_isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyX) {
      unawaited(notifier.cutSelection());
      return;
    }
    if (_isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      notifier.selectAllNodes();
      return;
    }
    if (_isPrimaryModifierPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      notifier.undo();
      return;
    }
    if (_isPrimaryModifierPressed &&
        ((HardwareKeyboard.instance.isShiftPressed &&
                event.logicalKey == LogicalKeyboardKey.keyZ) ||
            event.logicalKey == LogicalKeyboardKey.keyY)) {
      notifier.redo();
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      notifier.deleteSelection();
    }
  }

  void _adjustZoom(double multiplier) {
    final Matrix4? updatedMatrix = canvasZoomedBy(multiplier);
    if (updatedMatrix == null) {
      return;
    }
    _syncingViewportFromState = true;
    _transformationController.value = updatedMatrix;
    _syncingViewportFromState = false;
    ref
        .read(canvasProvider.notifier)
        .updateViewport(
          zoom: updatedMatrix.getMaxScaleOnAxis(),
          pan: <double>[updatedMatrix.storage[12], updatedMatrix.storage[13]],
        );
  }

  void _handleOutputPortTap(String nodeId, String portId) {
    // Second tap on the same dot: the user has seen the armed state and tapped
    // again, which means "no existing node — give me a new one".
    if (_isArmedPort(nodeId, portId)) {
      _clearArmedPort();
      _handleAddFromPort(
        sourceNode: _firstNodeById(nodeId),
        portId: portId,
        fromOutput: true,
        nirTypeMap: ref.read(nirNodeTypeMapProvider),
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
    Map<String, NirNodeType> nirTypeMap,
  ) {
    final CanvasState canvasState = ref.read(canvasProvider);
    final String? sourceNodeId = canvasState.connectingFromNodeId;
    final String? sourcePortId = canvasState.connectingFromPortId;

    // No connection in progress: the input dot behaves like the output one —
    // first tap arms it, second tap asks for a new upstream node.
    if (sourceNodeId == null || sourcePortId == null) {
      if (_isArmedPort(targetNodeId, targetPortId)) {
        _clearArmedPort();
        _handleAddFromPort(
          sourceNode: _firstNodeById(targetNodeId),
          portId: targetPortId,
          fromOutput: false,
          nirTypeMap: nirTypeMap,
        );
      } else {
        _armPort(targetNodeId, targetPortId);
      }
      return;
    }

    // A connection *is* in progress, so this tap completes it — the armed state
    // belongs to the source port and is now spent either way.
    _clearArmedPort();
    _createConnection(
      sourceNodeId: sourceNodeId,
      sourcePortId: sourcePortId,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
      nirTypeMap: nirTypeMap,
    );
  }

  void _handleNodeDrop(DragTargetDetails<NirNodeType> details) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset localPos = box.globalToLocal(details.offset);
    final Offset scenePos = _sceneFromViewport(localPos);
    _createNodeAt(details.data, scenePos);
  }

  CanvasEdge? _findEdgeAtPosition(
    Offset pos,
    CanvasGraph graph,
    Map<String, NirNodeType> nirTypeMap,
  ) {
    for (final CanvasEdge edge in graph.edges) {
      final Offset? source = _getPortPosition(
        graph,
        nirTypeMap,
        edge.sourceNodeId,
        edge.sourcePort,
        false,
      );
      final Offset? target = _getPortPosition(
        graph,
        nirTypeMap,
        edge.targetNodeId,
        edge.targetPort,
        true,
      );
      if (source != null &&
          target != null &&
          _isPointNearBezier(pos, source, target)) {
        return edge;
      }
    }
    return null;
  }

  Offset? _getPortPosition(
    CanvasGraph graph,
    Map<String, NirNodeType> nirTypeMap,
    String nodeId,
    String portId,
    bool isInput,
  ) {
    try {
      final CanvasNode node = graph.nodes.firstWhere(
        (CanvasNode n) => n.id == nodeId,
      );
      final NirNodeType? nodeType = _resolveType(nirTypeMap, node);
      if (nodeType == null) {
        return null;
      }
      final List<NirPortDef> ports = nodeType.ports
          .where(
            (NirPortDef p) => p.direction == (isInput ? 'input' : 'output'),
          )
          .toList();
      final int index = ports.indexWhere((NirPortDef p) => p.id == portId);
      if (index == -1) {
        return null;
      }
      return Offset(node.position[0], node.position[1]) +
          networkPortCentre(
            node: node,
            index: index,
            count: ports.length,
            cardSize: networkNodeSize(node, nodeType, compact: _isVertical),
            isInput: isInput,
            compact: _isVertical,
          );
    } catch (_) {
      return null;
    }
  }

  bool _isPointNearBezier(Offset point, Offset source, Offset target) =>
      canvasEdgeHit(point, source, target, isVertical: _isVertical);

  void _handleConnectionDrop(
    String sourceNodeId,
    String sourcePortId,
    Offset scenePos,
    Map<String, NirNodeType> nirTypeMap,
  ) {
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    final NearestPortMatch? match = findNearestInputPort(
      graph,
      nirTypeMap,
      scenePos,
      excludeNodeId: sourceNodeId,
      isVertical: _isVertical,
    );

    if (match != null) {
      final bool created = _createConnection(
        sourceNodeId: sourceNodeId,
        sourcePortId: sourcePortId,
        targetNodeId: match.nodeId,
        targetPortId: match.port.id,
        nirTypeMap: nirTypeMap,
        strokeWeight: _latestPointerPressure.clamp(0.3, 1.0),
      );
      if (created) {
        _resetConnectionHoverState();
      }
    }

    if (ref.read(canvasProvider).connectingFromNodeId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Drop on another node input, or click an input port to finish the connection.',
          ),
          showCloseIcon: true,
        ),
      );
      ref.read(canvasProvider.notifier).cancelConnecting();
    }
  }

  bool _createConnection({
    required String sourceNodeId,
    required String sourcePortId,
    required String targetNodeId,
    required String targetPortId,
    required Map<String, NirNodeType> nirTypeMap,
    double strokeWeight = 1.0,
  }) {
    if (sourceNodeId == targetNodeId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connections must end on a different node.'),
          showCloseIcon: true,
        ),
      );
      ref.read(canvasProvider.notifier).cancelConnecting();
      return false;
    }

    final CanvasState canvasState = ref.read(canvasProvider);
    final Iterable<CanvasEdge> existingEdge = canvasState.graph.edges.where((
      CanvasEdge edge,
    ) {
      return edge.sourceNodeId == sourceNodeId &&
          edge.sourcePort == sourcePortId &&
          edge.targetNodeId == targetNodeId &&
          edge.targetPort == targetPortId;
    });

    if (existingEdge.isNotEmpty) {
      ref.read(canvasProvider.notifier).selectEdge(existingEdge.first.id);
      ref.read(canvasProvider.notifier).cancelConnecting();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That connection already exists.'),
          showCloseIcon: true,
        ),
      );
      return false;
    }

    // Type compatibility check
    CanvasNode? srcNode, tgtNode;
    for (final n in canvasState.graph.nodes) {
      if (n.id == sourceNodeId) srcNode = n;
      if (n.id == targetNodeId) tgtNode = n;
    }
    if (srcNode != null && tgtNode != null) {
      final PortType? srcType = inferNirPortTypes(
        srcNode.nirType,
        srcNode.parameters,
      )?[sourcePortId];
      final PortType? tgtType = inferNirPortTypes(
        tgtNode.nirType,
        tgtNode.parameters,
      )?[targetPortId];
      if (srcType != null &&
          tgtType != null &&
          !srcType.isCompatibleWith(tgtType)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Type mismatch: $srcType → $tgtType'),
            showCloseIcon: true,
          ),
        );
        ref.read(canvasProvider.notifier).cancelConnecting();
        return false;
      }
    }

    final String edgeId = 'edge_${DateTime.now().millisecondsSinceEpoch}';
    ref
        .read(canvasProvider.notifier)
        .addEdge(
          CanvasEdge(
            id: edgeId,
            sourceNodeId: sourceNodeId,
            sourcePort: sourcePortId,
            targetNodeId: targetNodeId,
            targetPort: targetPortId,
            parameters: <String, dynamic>{
              'weight': 1.0,
              'delay': 0.0,
              'polarity': 'excitatory',
              'strokeWeight': strokeWeight,
            },
          ),
        );
    ref.read(canvasProvider.notifier).cancelConnecting();
    return true;
  }
}

class _CanvasNodeWidget extends ConsumerWidget {
  const _CanvasNodeWidget({
    super.key,
    required this.node,
    required this.nodeType,
    required this.isGlowing,
    required this.connectingFromNodeId,
    required this.connectingFromPortId,
    this.connectingPortType,
    this.hoverCandidateNodeId,
    this.hoverCandidatePortId,
    required this.onTap,
    required this.onDragStart,
    this.onDoubleTap,
    this.onDoubleTapDown,
    required this.onOutputPortTap,
    required this.onInputPortTap,
    required this.onPortPanUpdate,
    required this.onPortPanEnd,
    this.armedPortNodeId,
    this.armedPortId,
    required this.transformationController,
    required this.sceneOrigin,
    this.isVertical = false,
  });

  final CanvasNode node;
  final NirNodeType? nodeType;
  final bool isGlowing;
  final String? connectingFromNodeId;
  final String? connectingFromPortId;

  /// Type of the port currently being dragged from. null = no type constraint.
  final PortType? connectingPortType;

  /// Node/port id of the single port a hovering (pre-touch) stylus has
  /// snapped to as the nearest compatible connection target. Null when
  /// there is no such candidate.
  final String? hoverCandidateNodeId;
  final String? hoverCandidatePortId;

  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final VoidCallback? onDoubleTap;

  /// Reports the [PointerDeviceKind] of the second tap-down of a double-tap,
  /// fired just before [onDoubleTap]. Lets callers give stylus double-taps
  /// different semantics (e.g. delete-if-selected) from mouse/touch ones.
  final ValueChanged<PointerDeviceKind>? onDoubleTapDown;
  final ValueChanged<String> onOutputPortTap;
  final ValueChanged<String> onInputPortTap;
  final PortPanUpdateCallback onPortPanUpdate;
  final PortPanEndCallback onPortPanEnd;

  /// The port whose *next* tap opens the add-node palette rather than arming a
  /// connection. Drives the stronger `+` treatment on that one dot.
  final String? armedPortNodeId;
  final String? armedPortId;

  bool _isArmed(String portId) =>
      armedPortNodeId == node.id && armedPortId == portId;

  final TransformationController transformationController;
  final Offset sceneOrigin;
  final bool isVertical;

  /// True when [inputPort] on this node can accept the dragged connection.
  bool _isPortCompatible(NirPortDef inputPort) =>
      _canAcceptConnection(connectingPortType, node, inputPort);

  /// Maps this node's NIR ports onto the shared card's port model.
  ///
  /// Input ports get [CanvasCardPort.onTap] only — with no pan recognizer
  /// registered, a drag starting over an input port still pans the canvas.
  /// Output ports also register pan handlers, which beat [InteractiveViewer]'s
  /// scale recognizer so dragging from one draws a wire.
  List<CanvasCardPort> _cardPorts(WidgetRef ref, {required bool isInput}) {
    final List<NirPortDef> ports = (nodeType?.ports ?? const <NirPortDef>[])
        .where((NirPortDef p) => p.direction == (isInput ? 'input' : 'output'))
        .toList();
    return <CanvasCardPort>[
      for (final NirPortDef port in ports)
        CanvasCardPort(
          id: port.id,
          label: port.id,
          isInput: isInput,
          isActive:
              connectingFromNodeId == node.id &&
              connectingFromPortId == port.id,
          canAcceptConnection:
              isInput &&
              connectingFromNodeId != null &&
              connectingFromNodeId != node.id &&
              _isPortCompatible(port),
          isHoverCandidate:
              isInput &&
              hoverCandidateNodeId == node.id &&
              hoverCandidatePortId == port.id,
          isArmed: _isArmed(port.id),
          tooltip: _isArmed(port.id)
              ? (isInput
                    ? 'Tap again to add a node feeding "${port.label}"'
                    : 'Tap again to add a node fed by "${port.label}"')
              : '${port.label} ${isInput ? 'input' : 'output'} — tap to connect, '
                    'tap again to add a node',
          onTap: () {
            if (isInput) {
              onInputPortTap(port.id);
            } else {
              onOutputPortTap(port.id);
            }
          },
          onPanStart: isInput
              ? null
              : (_) {
                  ref
                      .read(canvasProvider.notifier)
                      .startConnecting(node.id, port.id);
                },
          onPanUpdate: isInput
              ? null
              : (DragUpdateDetails details) => onPortPanUpdate(
                  port.id,
                  details.localPosition,
                  details.globalPosition,
                ),
          onPanEnd: isInput ? null : (_) => onPortPanEnd(port.id),
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched here (not by the parent) so a selection change only dirties
    // the node(s) whose membership actually flipped, not every node.
    final bool isSelected = ref.watch(
      canvasSelectedNodeIdsProvider.select(
        (Set<String> ids) => ids.contains(node.id),
      ),
    );
    final bool armedForDelete = ref.watch(
      armedForDeleteNodeIdProvider.select((String? id) => id == node.id),
    );
    // Only non-null while the Run/Results step is live or scrubbing epochs —
    // the Architecture tab never writes trainingModeProvider, so this stays
    // null there and the node paints exactly as before.
    final double? spikeRate = ref.watch(
      trainingModeProvider.select(
        (Map<String, double>? rates) => rates?[node.id],
      ),
    );
    final ThemeData theme = Theme.of(context);
    final NmtkShellTokens tokens = NmtkShellTokens.of(context);
    final String resolvedName = resolveNodeDisplayName(node);
    final String category =
        nodeType?.category ??
        node.metadata['category']?.toString() ??
        'utility';
    final Color accentColor = nirCategoryColor(context, category);
    final bool highlightSelected = isSelected || isGlowing;
    final Color? spikeColor = spikeRate == null
        ? null
        : spikeRateColor(spikeRate, Zeta.of(context).colors);

    return Positioned(
      left: node.position[0] + sceneOrigin.dx,
      top: node.position[1] + sceneOrigin.dy,
      child: RepaintBoundary(
        child: CanvasNodeCard(
          key: isGlowing ? ValueKey<String>('cnl-focus-node_${node.id}') : null,
          nodeId: node.id,
          cardSize: networkNodeSize(node, nodeType, compact: isVertical),
          accentColor: accentColor,
          icon:
              nodeType?.icon ??
              Icons.extension, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          title: resolvedName,
          subtitle: nirNodeKeyParam(node, nodeType),
          background: isGlowing
              ? tokens.studioPalette.accent.withValues(alpha: 0.08)
              : tokens.utilityPanelBackground,
          isSelected: highlightSelected,
          borderColor: highlightSelected ? null : spikeColor,
          borderWidth: highlightSelected || spikeColor != null ? 2 : 1,
          compact: isVertical,
          collapsed: !node.isVisible,
          isConnecting: connectingFromNodeId != null,
          ports: <CanvasCardPort>[
            ..._cardPorts(ref, isInput: true),
            ..._cardPorts(ref, isInput: false),
          ],
          trailingBadge: spikeRate == null || spikeColor == null
              ? null
              : IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: spikeColor.withValues(alpha: 0.85),
                      borderRadius: NmtkDesignTokens.chipShape,
                    ),
                    child: Text(
                      '${(spikeRate * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Zeta.of(context).colors.mainInverse,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
          armedForDelete: armedForDelete,
          onDelete: () {
            ref.read(canvasProvider.notifier).removeNode(node.id);
            ref.read(armedForDeleteNodeIdProvider.notifier).set(null);
          },
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onDoubleTapDown: onDoubleTapDown,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (DragUpdateDetails details) {
            final CanvasNode currentNode = ref
                .read(canvasProvider)
                .graph
                .nodes
                .firstWhere((CanvasNode n) => n.id == node.id);
            ref
                .read(canvasProvider.notifier)
                .updateNodePosition(
                  node.id,
                  currentNode.position[0] + details.delta.dx,
                  currentNode.position[1] + details.delta.dy,
                );
          },
          onPanEnd: (_) =>
              ref.read(canvasProvider.notifier).snapNodeToGrid(node.id),
          onLongPress: () =>
              ref.read(armedForDeleteNodeIdProvider.notifier).set(node.id),
        ),
      ),
    );
  }
}

/// Floating text field for stylus handwriting-to-node creation. Anchored to
/// the raw screen [position] where the stylus tapped -- deliberately
/// screen-space rather than scene-space/`LayerLink`, since the interaction is
/// momentary (tap, write, submit, dismiss) and doesn't need to track live
/// pan/zoom. The caller dismisses it (via [NetworkCanvas]'s
/// `_dismissHandwritingPopup`) if the viewport changes while it's open.
///
/// Shows ranked suggestion chips as the user types. Tapping a chip submits
/// that canonical node-type name immediately, tolerating Apple Scribble /
/// handwriting-OCR errors that would otherwise cause a snackbar error.
class _HandwritingOverlay extends ConsumerStatefulWidget {
  const _HandwritingOverlay({
    required this.position,
    required this.controller,
    required this.onSubmitted,
    required this.onDismiss,
  });

  final Offset position;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_HandwritingOverlay> createState() =>
      _HandwritingOverlayState();
}

class _HandwritingOverlayState extends ConsumerState<_HandwritingOverlay> {
  List<NirNodeType> _suggestions = const <NirNodeType>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final Map<String, NirNodeType> registry = ref.read(nirNodeTypeMapProvider);
    final List<NirNodeType> candidates = suggestNirNodeTypes(
      widget.controller.text,
      registry,
      max: 5,
    );
    if (mounted) {
      setState(() => _suggestions = candidates);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double radius = NmtkShellTokens.of(context).radiusSm;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(radius),
            color: colorScheme.surface,
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Text input
                  TextField(
                    controller: widget.controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Node type…',
                      suffixIcon: widget.controller.text.isNotEmpty
                          ? ZetaIconButton.text(
                              icon: Icons.clear,
                              size: ZetaWidgetSize.small,
                              onPressed: () {
                                widget.controller.clear();
                              },
                            )
                          : null,
                    ),
                    onSubmitted: widget.onSubmitted,
                  ),
                  // Suggestion chips — only shown when there are candidates
                  if (_suggestions.isNotEmpty) ...[
                    const Divider(height: 6, thickness: 0.5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _suggestions.map((NirNodeType type) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4, bottom: 4),
                            child: ActionChip(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 0,
                              ),
                              labelPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                type.displayName,
                                style: Zeta.of(context).textStyles.labelSmall
                                    .copyWith(fontSize: 11),
                              ),
                              onPressed: () =>
                                  widget.onSubmitted(type.displayName),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ConnectionPainter extends CustomPainter {
  ConnectionPainter({
    required this.graph,
    required this.nirTypeMap,
    this.connectingFromNodeId,
    this.connectingFromPortId,
    this.currentConnectingPoint,
    this.currentConnectingPressure = 1.0,
    this.selectedEdgeId,
    required this.primaryColor,
    required this.outlineColor,
    this.isVertical = false,
    this.sceneOrigin = Offset.zero,
    required this.badgeAccentColor,
  });

  final CanvasGraph graph;
  final Map<String, NirNodeType> nirTypeMap;
  final String? connectingFromNodeId;
  final String? connectingFromPortId;
  final Offset? currentConnectingPoint;

  /// Latest stylus pressure (0.0-1.0; defaults to 1.0 for non-pressure
  /// devices) sampled while a connection is being dragged. Used only to
  /// scale the width of the uncommitted, in-progress preview wire below.
  final double currentConnectingPressure;
  final String? selectedEdgeId;
  final Color primaryColor;
  final Color outlineColor;
  final bool isVertical;
  final Offset sceneOrigin;

  /// Border/text color for the learning-rule badge, resolved from the
  /// active Zeta theme by the caller (paint() has no BuildContext). Reads as
  /// white-on-colored-circle in both themes -- same `mainInverse` pairing
  /// [TileGridNeuronRenderer] uses for its dark-card popup.
  final Color badgeAccentColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(sceneOrigin.dx, sceneOrigin.dy);
    for (final CanvasEdge edge in graph.edges) {
      final bool isSelected = edge.id == selectedEdgeId;
      final double strokeWeight =
          (edge.parameters['strokeWeight'] as num?)?.toDouble() ?? 1.0;

      final Offset? source = _getPortPosition(
        edge.sourceNodeId,
        edge.sourcePort,
        false,
      );
      final Offset? target = _getPortPosition(
        edge.targetNodeId,
        edge.targetPort,
        true,
      );
      if (source == null || target == null) {
        continue;
      }

      // A wire takes the color of the node it leaves, so a graph reads by
      // signal path the way the Train/Eval wires do (those color by the data
      // kind their port carries — a notion this canvas's PortType, which
      // describes tensor shape, does not have). Wires used to be one uniform
      // outline grey here.
      final Color color = isSelected
          ? primaryColor
          : _edgeColor(edge.sourceNodeId);

      drawCanvasEdge(
        canvas,
        source,
        target,
        color,
        isVertical: isVertical,
        strokeWidth: canvasEdgeStrokeWidth(
          isSelected: isSelected,
          weight: strokeWeight,
        ),
        // Dashed stroke marks a plastic (learning-rule) edge.
        dashed: edge.parameters['hasLearningRule'] == true,
      );

      // ── Learning rule badge ──────────────────────────────────────────────
      final String? learningRule = edge.parameters['learningRuleKind']
          ?.toString();
      if (learningRule != null) {
        // ZETA-MIGRATION-EXEMPT: categorical data-viz color, no Zeta
        // equivalent for N-way distinct hues (one per learning-rule kind).
        final Color badgeColor = switch (learningRule) {
          'stdp' => const Color(0xFFFFC107),
          'surrogate_gradient' => const Color(0xFF2196F3),
          'hebbian' => const Color(0xFF4CAF50),
          _ => const Color(0xFF9E9E9E),
        };
        final String abbr = switch (learningRule) {
          'stdp' => 'S',
          'surrogate_gradient' => 'SG',
          'hebbian' => 'H',
          _ => '?',
        };
        final Offset mid = canvasEdgeMidpoint(source, target);
        // Circle background
        canvas.drawCircle(mid, 10, Paint()..color = badgeColor);
        // Border so the badge stands out on any background
        canvas.drawCircle(
          mid,
          10,
          Paint()
            ..color = badgeAccentColor.withValues(alpha: 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        // Abbreviation text
        // ZETA-MIGRATION-EXEMPT: drawn inside CustomPainter.paint, which has
        // no BuildContext to reach Zeta.of(context); badge also needs an
        // 8px size below Zeta's smallest text preset (12px) to fit the dot.
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: abbr,
            style: TextStyle(
              color: badgeAccentColor,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
      }
    }

    if (connectingFromNodeId != null &&
        connectingFromPortId != null &&
        currentConnectingPoint != null) {
      final Offset? source = _getPortPosition(
        connectingFromNodeId!,
        connectingFromPortId!,
        false,
      );
      if (source != null) {
        // Stylus pressure only scales the uncommitted preview wire.
        drawCanvasEdge(
          canvas,
          source,
          currentConnectingPoint!,
          primaryColor.withValues(alpha: 0.8),
          isVertical: isVertical,
          strokeWidth: (1.5 + currentConnectingPressure * 3.0).clamp(1.0, 6.0),
          arrowhead: false,
        );
      }
    }
    canvas.restore();
  }

  /// Accent color of the node a wire leaves, falling back to the theme's
  /// outline color when the node or its type no longer resolves.
  Color _edgeColor(String sourceNodeId) {
    for (final CanvasNode node in graph.nodes) {
      if (node.id != sourceNodeId) continue;
      final String? category =
          nirTypeMap[node.nirType ?? node.componentId]?.category ??
          node.metadata['category']?.toString();
      if (category == null) break;
      return canvasCategoryColor(category);
    }
    return outlineColor;
  }

  Offset? _getPortPosition(String nodeId, String portId, bool isInput) {
    final CanvasNode? node = graph.nodes.cast<CanvasNode?>().firstWhere(
      (CanvasNode? n) => n?.id == nodeId,
      orElse: () => null,
    );
    if (node == null) {
      return null;
    }
    final NirNodeType? nodeType = nirTypeMap[node.nirType ?? node.componentId];
    if (nodeType == null) {
      return null;
    }
    final List<NirPortDef> ports = nodeType.ports
        .where((NirPortDef p) => p.direction == (isInput ? 'input' : 'output'))
        .toList();
    final int index = ports.indexWhere((NirPortDef p) => p.id == portId);
    if (index == -1) {
      return null;
    }
    return Offset(node.position[0], node.position[1]) +
        networkPortCentre(
          node: node,
          index: index,
          count: ports.length,
          cardSize: networkNodeSize(node, nodeType, compact: isVertical),
          isInput: isInput,
          compact: isVertical,
        );
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.currentConnectingPoint != currentConnectingPoint ||
        oldDelegate.currentConnectingPressure != currentConnectingPressure ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.connectingFromNodeId != connectingFromNodeId ||
        oldDelegate.connectingFromPortId != connectingFromPortId ||
        oldDelegate.sceneOrigin != sceneOrigin ||
        oldDelegate.isVertical != isVertical;
  }
}
