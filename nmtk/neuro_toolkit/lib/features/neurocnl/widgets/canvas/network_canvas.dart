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
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_edge_painting.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_minimap.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_node_widget.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_surface_state.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/connection_painter.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas_connections.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas_node_placement.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas_viewport.dart';

export 'package:neuro_toolkit/features/neurocnl/widgets/canvas/connection_painter.dart'
    show ConnectionPainter;

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

/// Resolves [node]'s [NirNodeType] entry in [nirTypeMap].
NirNodeType? resolveNetworkNodeType(
  Map<String, NirNodeType> nirTypeMap,
  CanvasNode node,
) {
  return nirTypeMap[node.nirType ?? node.componentId];
}

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

class _NetworkCanvasState extends CanvasSurfaceState<NetworkCanvas>
    with
        SingleTickerProviderStateMixin<NetworkCanvas>,
        NetworkCanvasViewportMixin<NetworkCanvas>,
        NetworkCanvasConnectionMixin<NetworkCanvas>,
        NetworkCanvasNodePlacementMixin<NetworkCanvas> {
  final TransformationController _transformationController =
      TransformationController();
  final FocusNode _focusNode = FocusNode();
  bool _isVertical = false;

  /// Drives the animated pan-to-node triggered when a new node is added --
  /// see [NetworkCanvasViewportMixin.networkFollowPendingViewportFocus].
  /// Built eagerly in [initState] rather than via a lazy `late` initializer:
  /// if the controller is never read until [dispose] (e.g. no node was ever
  /// added), a lazy initializer would construct it -- and call `vsync:
  /// this` -- while the widget is already deactivated, which crashes.
  late final AnimationController _viewportFollowController;

  @override
  AnimationController get networkViewportFollowController =>
      _viewportFollowController;

  @override
  bool get networkIsVertical => _isVertical;

  @override
  double get networkLatestPointerPressure => _latestPointerPressure;

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

  @override
  void initState() {
    super.initState();
    _transformationController.value = canvasWorldMatrix(
      zoom: 1,
      pan: Offset.zero,
    );
    _viewportFollowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _transformationController.addListener(networkHandleViewportChanged);
  }

  @override
  CanvasWorldGeometry get canvasWorld => _networkWorld;

  @override
  TransformationController get canvasTransform => _transformationController;

  @override
  void dispose() {
    _transformationController.removeListener(networkHandleViewportChanged);
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
    // widget in it. Each `CanvasNodeWidget` watches its own selection
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
        if (next != null) networkFollowPendingViewportFocus(next);
      },
    );
    // A listen, NOT a watch: reading the viewport during build would rebuild
    // this whole method on every pan frame — exactly the cost that moving the
    // viewport off `graph` was meant to remove. This only has to fire when
    // something *other* than the gesture moves the camera (resetViewport).
    ref.listen<CanvasViewport>(
      canvasProvider.select((CanvasState s) => s.viewport),
      (CanvasViewport? previous, CanvasViewport next) =>
          networkSyncViewportFromState(next),
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
    final PortType? connectingPortType = networkInferConnectingPortType(
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
                            networkHandleNodeDrop(details);
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
                                            canvasSceneFromViewport(
                                              details.localPosition,
                                            );
                                        final CanvasNode? tappedNode =
                                            networkNodeAtPosition(
                                              scenePos,
                                              graph,
                                            );
                                        final CanvasEdge? tappedEdge =
                                            networkFindEdgeAtPosition(
                                              scenePos,
                                              graph,
                                              nirTypeMap,
                                            );
                                        if (tappedNode != null) {
                                          if (isPrimaryModifierPressed) {
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
                                          networkClearArmedPort();
                                          canvasNotifier.selectEdge(
                                            tappedEdge.id,
                                          );
                                        } else if (!isPrimaryModifierPressed) {
                                          _pendingCnlFocusNodeId = null;
                                          networkClearArmedPort();
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
                                                networkCurrentConnectingPoint,
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
                                            resolveNetworkNodeType(
                                              nirTypeMap,
                                              node,
                                            );
                                        void selectStructurally() {
                                          _focusNode.requestFocus();
                                          final notifier = ref.read(
                                            canvasProvider.notifier,
                                          );
                                          if (isPrimaryModifierPressed) {
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
                                          if (isPrimaryModifierPressed) return;
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

                                        return CanvasNodeWidget(
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
                                              networkHoverCandidateNodeId,
                                          hoverCandidatePortId:
                                              networkHoverCandidatePortId,
                                          transformationController:
                                              _transformationController,
                                          sceneOrigin: _networkWorld.origin,
                                          isVertical: isVertical,
                                          onTap: selectAndFocusCnl,
                                          // On mobile, selecting a node pops
                                          // the inspector bottom sheet (see
                                          // CanvasScreen's ref.listen on
                                          // canvasSelectedNodeIdProvider) --
                                          // see CanvasSurfaceState.
                                          // dragStartGuard.
                                          onDragStart: dragStartGuard(
                                            isVertical: isVertical,
                                            selectStructurally:
                                                selectStructurally,
                                          ),
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
                                            networkHandleOutputPortTap(
                                              node.id,
                                              portId,
                                            );
                                          },
                                          onInputPortTap: (String portId) {
                                            _focusNode.requestFocus();
                                            networkHandleInputPortTap(
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
                                                  networkCurrentConnectingPoint =
                                                      canvasSceneFromViewport(
                                                        localPosInCanvas,
                                                      );
                                                });
                                              },
                                          armedPortNodeId:
                                              networkArmedPortNodeId,
                                          armedPortId: networkArmedPortId,
                                          onPortPanEnd: (String portId) {
                                            if (networkCurrentConnectingPoint !=
                                                null) {
                                              networkHandleConnectionDrop(
                                                node.id,
                                                portId,
                                                networkCurrentConnectingPoint!,
                                                nirTypeMap,
                                              );
                                            }
                                            networkResetConnectionHoverState();
                                          },
                                        );
                                      }),
                                      // Delete affordance for the selected edge.
                                      // Lives in the canvas Stack, not on a node,
                                      // because it belongs to the wire's midpoint.
                                      if (selectedEdgeId != null)
                                        ?() {
                                          final Offset? mid =
                                              networkEdgeMidpoint(
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
                        final NirNodeType? nodeType = resolveNetworkNodeType(
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
                            final Offset? source = networkGetPortPosition(
                              graph,
                              nirTypeMap,
                              edge.sourceNodeId,
                              edge.sourcePort,
                              false,
                            );
                            final Offset? target = networkGetPortPosition(
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
                        _transformationController.value = canvasWorldMatrix(
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

  void _scheduleWorkspaceRestoreFocus(int revision) {
    scheduleWorkspaceRestoreFocus(revision, () {
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
      _transformationController.value = canvasWorldMatrix(zoom: zoom, pan: pan);
    });
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
      networkEraseAt(event.position);
      return;
    }
    if (isPrimaryModifierPressed) return;
    final CanvasGraph graph = ref.read(canvasProvider).graph;
    final Offset scenePos = canvasSceneFromViewport(event.localPosition);
    final CanvasNode? node = networkNodeAtPosition(scenePos, graph);
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
    final Offset scenePos = canvasSceneFromViewport(localPos);

    final PortType? connectingPortType = networkInferConnectingPortType(
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
          canvasNodeAcceptsConnection(connectingPortType, node, port),
      isVertical: _isVertical,
    );

    setState(() {
      networkHoverCandidateNodeId = candidate?.nodeId;
      networkHoverCandidatePortId = candidate?.port.id;
      networkCurrentConnectingPoint = candidate?.portPosition ?? scenePos;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(canvasProvider.notifier).cancelConnecting();
      networkResetConnectionHoverState();
      networkClearArmedPort();
      canvasDismissHandwritingPopup();
      return;
    }

    if (isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.digit0) {
      ref.read(canvasProvider.notifier).resetViewport();
      return;
    }

    if (isPrimaryModifierPressed &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      networkAdjustZoom(kCanvasZoomStep);
      return;
    }

    if (isPrimaryModifierPressed &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      networkAdjustZoom(1 / kCanvasZoomStep);
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
    if (isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(notifier.copySelection());
      return;
    }
    if (isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(notifier.pasteClipboard());
      return;
    }
    if (isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyX) {
      unawaited(notifier.cutSelection());
      return;
    }
    if (isPrimaryModifierPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      notifier.selectAllNodes();
      return;
    }
    if (isPrimaryModifierPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      notifier.undo();
      return;
    }
    if (isPrimaryModifierPressed &&
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
}
