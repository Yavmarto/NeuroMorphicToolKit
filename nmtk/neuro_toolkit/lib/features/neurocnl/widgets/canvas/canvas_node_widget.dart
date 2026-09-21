import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/models/port_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_selectors.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_mode_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_node_subtitle.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_node_card_widget.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

/// True when [inputPort] on [targetNode] can accept a connection dragged
/// from a port of type [connectingPortType]. A null [connectingPortType]
/// (no type constraint inferred) always accepts.
bool canvasNodeAcceptsConnection(
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

class CanvasNodeWidget extends CanvasNodeCardWidget {
  const CanvasNodeWidget({
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

  @override
  final VoidCallback onTap;
  @override
  final VoidCallback onDragStart;
  @override
  final VoidCallback? onDoubleTap;

  /// Reports the [PointerDeviceKind] of the second tap-down of a double-tap,
  /// fired just before [onDoubleTap]. Lets callers give stylus double-taps
  /// different semantics (e.g. delete-if-selected) from mouse/touch ones.
  @override
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

  @override
  String get nodeId => node.id;

  /// True when [inputPort] on this node can accept the dragged connection.
  bool _isPortCompatible(NirPortDef inputPort) =>
      canvasNodeAcceptsConnection(connectingPortType, node, inputPort);

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
  CanvasNodeCardSpec buildSpec(BuildContext context, WidgetRef ref) {
    // Watched here (not by the parent) so a selection change only dirties
    // the node(s) whose membership actually flipped, not every node.
    final bool isSelected = ref.watch(
      canvasSelectedNodeIdsProvider.select(
        (Set<String> ids) => ids.contains(node.id),
      ),
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

    return (
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
      onDelete: () {
        ref.read(canvasProvider.notifier).removeNode(node.id);
        ref.read(armedForDeleteNodeIdProvider.notifier).set(null);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      left: node.position[0] + sceneOrigin.dx,
      top: node.position[1] + sceneOrigin.dy,
      child: RepaintBoundary(
        key: isGlowing ? ValueKey<String>('cnl-focus-node_${node.id}') : null,
        child: super.build(context, ref),
      ),
    );
  }
}
