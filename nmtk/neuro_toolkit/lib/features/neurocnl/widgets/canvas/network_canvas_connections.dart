import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/models/port_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_connect_palette.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_edge_painting.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

/// Connection/port interaction for [NetworkCanvas]: dragging, tapping and
/// arming ports; hit-testing edges; creating and validating connections.
///
/// The host implements [networkIsVertical] and [networkLatestPointerPressure]
/// (values it already tracks for its own build) so this mixin never needs to
/// duplicate them.
mixin NetworkCanvasConnectionMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>
    implements CanvasViewportMixin<T> {
  bool get networkIsVertical;
  double get networkLatestPointerPressure;

  Offset? _currentConnectingPoint;
  Offset? get networkCurrentConnectingPoint => _currentConnectingPoint;
  set networkCurrentConnectingPoint(Offset? value) {
    _currentConnectingPoint = value;
  }

  // Set while a stylus is hovering (pre-touch) near the single nearest
  // compatible input port during an in-progress connection drag -- see
  // NetworkCanvas's ambient pointer hover handling. Null whenever there is
  // no such candidate.
  String? _hoverCandidateNodeId;
  String? get networkHoverCandidateNodeId => _hoverCandidateNodeId;
  set networkHoverCandidateNodeId(String? value) {
    _hoverCandidateNodeId = value;
  }

  String? _hoverCandidatePortId;
  String? get networkHoverCandidatePortId => _hoverCandidatePortId;
  set networkHoverCandidatePortId(String? value) {
    _hoverCandidatePortId = value;
  }

  /// The port tapped last, if the next tap on it should open the add-node
  /// palette. The port dot is the `+`: the first tap arms a connection, a
  /// second tap on the same dot means "I didn't want an existing node, give
  /// me a new one". Cleared by anything that ends or redirects the
  /// interaction.
  String? _armedPortNodeId;
  String? get networkArmedPortNodeId => _armedPortNodeId;
  String? _armedPortId;
  String? get networkArmedPortId => _armedPortId;

  bool _isArmedPort(String nodeId, String portId) =>
      _armedPortNodeId == nodeId && _armedPortId == portId;

  void networkClearArmedPort() {
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

  /// Resolves the [PortType] of the port currently being dragged from, or
  /// null when no connection is in progress.
  PortType? networkInferConnectingPortType(
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

  /// Clears the live connection-preview point and hover-candidate state.
  /// Called at every point a connection drag ends or is cancelled.
  void networkResetConnectionHoverState() {
    // A drag consumed the port's intent, so a later single tap on it should
    // arm afresh rather than jump straight to the palette.
    networkClearArmedPort();
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

  void networkHandleOutputPortTap(String nodeId, String portId) {
    // Second tap on the same dot: the user has seen the armed state and
    // tapped again, which means "no existing node — give me a new one".
    if (_isArmedPort(nodeId, portId)) {
      networkClearArmedPort();
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

  void networkHandleInputPortTap(
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
        networkClearArmedPort();
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

    // A connection *is* in progress, so this tap completes it — the armed
    // state belongs to the source port and is now spent either way.
    networkClearArmedPort();
    _createConnection(
      sourceNodeId: sourceNodeId,
      sourcePortId: sourcePortId,
      targetNodeId: targetNodeId,
      targetPortId: targetPortId,
      nirTypeMap: nirTypeMap,
    );
  }

  /// Opens the connect palette for [portId] on [sourceNode],
  /// then creates the chosen node already wired to it.
  ///
  /// [fromOutput] true means the new node goes downstream (`sourceNode →
  /// new`); false means upstream.
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
    networkResetConnectionHoverState();

    // Selecting the source first makes the grid placer put the new node next
    // to it — same mechanism the palette add uses, no bespoke placement here.
    ref.read(canvasProvider.notifier).selectNode(sourceNode.id);

    // Direction-only filter: a candidate qualifies if it has any port on the
    // facing side. Port *types* are inferred from live parameters and often
    // unknown, so filtering on them would hide connectable nodes; the
    // existing `_createConnection` check still reports genuine mismatches.
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
          preferRight: !networkIsVertical,
        );
  }

  CanvasEdge? networkFindEdgeAtPosition(
    Offset pos,
    CanvasGraph graph,
    Map<String, NirNodeType> nirTypeMap,
  ) {
    for (final CanvasEdge edge in graph.edges) {
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
      if (source != null &&
          target != null &&
          _isPointNearBezier(pos, source, target)) {
        return edge;
      }
    }
    return null;
  }

  Offset? networkGetPortPosition(
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
      final NirNodeType? nodeType = resolveNetworkNodeType(nirTypeMap, node);
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
            cardSize: networkNodeSize(
              node,
              nodeType,
              compact: networkIsVertical,
            ),
            isInput: isInput,
            compact: networkIsVertical,
          );
    } catch (_) {
      return null;
    }
  }

  bool _isPointNearBezier(Offset point, Offset source, Offset target) =>
      canvasEdgeHit(point, source, target, isVertical: networkIsVertical);

  /// Scene-space midpoint of [edgeId]'s curve — where its delete `✕` goes.
  ///
  /// Reuses [networkGetPortPosition] and the painter's own control points, so
  /// the button lands on the wire the user actually sees.
  Offset? networkEdgeMidpoint(
    CanvasGraph graph,
    Map<String, NirNodeType> nirTypeMap,
    String edgeId,
  ) {
    CanvasEdge? edge;
    for (final CanvasEdge e in graph.edges) {
      if (e.id == edgeId) edge = e;
    }
    if (edge == null) return null;

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
    if (source == null || target == null) return null;
    return connectionCurveMidpoint(source, target);
  }

  void networkHandleConnectionDrop(
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
      isVertical: networkIsVertical,
    );

    if (match != null) {
      final bool created = _createConnection(
        sourceNodeId: sourceNodeId,
        sourcePortId: sourcePortId,
        targetNodeId: match.nodeId,
        targetPortId: match.port.id,
        nirTypeMap: nirTypeMap,
        strokeWeight: networkLatestPointerPressure.clamp(0.3, 1.0),
      );
      if (created) {
        networkResetConnectionHoverState();
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
