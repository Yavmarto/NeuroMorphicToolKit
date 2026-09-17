import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

NirNodeType _typeWithPorts(String id, List<NirPortDef> ports) => NirNodeType(
  id: id,
  displayName: id,
  category: 'test',
  icon: Icons.circle,
  ports: ports,
  parameters: const [],
);

/// The card's on-canvas footprint is derived from its port count by
/// `canvasNodeSize` (shared with the Train/Eval canvases), so the persisted
/// `width`/`height` fields are deliberately left at their defaults here — they
/// no longer affect where anything renders.
CanvasNode _node({
  required String id,
  required String nirType,
  required List<double> position,
}) => CanvasNode(
  id: id,
  componentId: nirType,
  nirType: nirType,
  label: id,
  parameters: const <String, dynamic>{},
  position: position,
);

void main() {
  final Map<String, NirNodeType> singlePortRegistry = {
    'single.type': _typeWithPorts('single.type', const [
      NirPortDef(id: 'in', direction: 'input', label: 'in'),
    ]),
  };
  final Map<String, NirNodeType> multiPortRegistry = {
    'multi.type': _typeWithPorts('multi.type', const [
      NirPortDef(id: 'in1', direction: 'input', label: 'in1'),
      NirPortDef(id: 'in2', direction: 'input', label: 'in2'),
    ]),
  };

  group('findNearestInputPort', () {
    test('single-input-port node bypasses the distance check (accepts even '
        'far from the port center, as long as inside the node rect)', () {
      final CanvasGraph graph = CanvasGraph(
        nodes: [
          _node(id: 'single', nirType: 'single.type', position: [0, 0]),
        ],
        edges: const [],
        metadata: const {},
      );

      // Node rect is (0,0)-(150,132) and its one input port sits at (15,88).
      // This point is inside the rect but far (>64) from that port.
      final NearestPortMatch? match = findNearestInputPort(
        graph,
        singlePortRegistry,
        const Offset(140, 10),
        excludeNodeId: 'none',
      );

      expect(match, isNotNull);
      expect(match!.nodeId, 'single');
      expect(match.port.id, 'in');
      expect(match.distance, greaterThan(64.0));
    });

    test('returns null when the point is outside every node rect', () {
      final CanvasGraph graph = CanvasGraph(
        nodes: [
          _node(id: 'single', nirType: 'single.type', position: [0, 0]),
        ],
        edges: const [],
        metadata: const {},
      );

      final NearestPortMatch? match = findNearestInputPort(
        graph,
        singlePortRegistry,
        const Offset(1000, 1000),
        excludeNodeId: 'none',
      );

      expect(match, isNull);
    });

    test('a multi-port node requires distance < maxDistance, and returns '
        'null when the point is too far from every port', () {
      final CanvasGraph graph = CanvasGraph(
        nodes: [
          _node(id: 'multi', nirType: 'multi.type', position: [300, 0]),
        ],
        edges: const [],
        metadata: const {},
      );

      // Ports sit at x=315, y=73.3 and y=102.7; a point at x=450 (still
      // inside the inflated rect, which extends to x=462) is >64 from both.
      final NearestPortMatch? tooFar = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(450, 20),
        excludeNodeId: 'none',
      );
      expect(tooFar, isNull);

      // A point near in1's computed position matches it.
      final NearestPortMatch? close = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(315, 74),
        excludeNodeId: 'none',
      );
      expect(close, isNotNull);
      expect(close!.port.id, 'in1');
    });

    test('isCompatible filters out an otherwise-nearest port, matching the '
        'next-nearest compatible one instead', () {
      final CanvasGraph graph = CanvasGraph(
        nodes: [
          _node(id: 'multi', nirType: 'multi.type', position: [300, 0]),
        ],
        edges: const [],
        metadata: const {},
      );

      // Exactly at in1's position: distance 0 to in1, ~29.3 to in2 --
      // both within maxDistance, so without a filter in1 always wins.
      final NearestPortMatch? unfiltered = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(315, 73.33),
        excludeNodeId: 'none',
      );
      expect(unfiltered!.port.id, 'in1');

      final NearestPortMatch? filtered = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(315, 73.33),
        excludeNodeId: 'none',
        isCompatible: (CanvasNode node, NirPortDef port) => port.id != 'in1',
      );
      expect(filtered, isNotNull);
      expect(filtered!.port.id, 'in2');
    });

    test('excludeNodeId is never matched, even when geometrically nearest', () {
      final CanvasGraph graph = CanvasGraph(
        nodes: [
          _node(id: 'nodeD', nirType: 'single.type', position: [0, 0]),
          _node(id: 'nodeE', nirType: 'single.type', position: [40, 0]),
        ],
        edges: const [],
        metadata: const {},
      );

      // (30,88) is inside both nodes' inflated rects. Without exclusion,
      // nodeD is checked first and single-port-bypasses regardless of
      // distance, so it always wins.
      final NearestPortMatch? withoutExclude = findNearestInputPort(
        graph,
        singlePortRegistry,
        const Offset(30, 88),
        excludeNodeId: 'none',
      );
      expect(withoutExclude!.nodeId, 'nodeD');

      final NearestPortMatch? withExclude = findNearestInputPort(
        graph,
        singlePortRegistry,
        const Offset(30, 88),
        excludeNodeId: 'nodeD',
      );
      expect(withExclude, isNotNull);
      expect(withExclude!.nodeId, 'nodeE');
    });

    // Regression coverage: findNearestInputPort used to always assume the
    // desktop left-edge port layout, even when called from mobile/vertical
    // mode (where the card already renders input ports along the *top*
    // edge, spread across the width) -- so a drag-release on mobile could
    // miss the port it visually landed on. isVertical: true must match that
    // same top-edge, width-spread layout.
    test('isVertical: true matches the top-edge, width-spread compact port '
        'layout instead of the desktop left-edge one', () {
      final CanvasGraph graph = CanvasGraph(
        nodes: [
          _node(id: 'multi', nirType: 'multi.type', position: [300, 0]),
        ],
        edges: const [],
        metadata: const {},
      );

      // Compact layout: in1 at x = 300 + 150*1/3 = 350, in2 at
      // x = 300 + 150*2/3 = 400, both at y = 15
      // (kCanvasPortHitTargetSize/2).
      final NearestPortMatch? matchesIn1 = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(350, 15),
        excludeNodeId: 'none',
        isVertical: true,
      );
      expect(matchesIn1, isNotNull);
      expect(matchesIn1!.port.id, 'in1');

      final NearestPortMatch? matchesIn2 = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(400, 15),
        excludeNodeId: 'none',
        isVertical: true,
      );
      expect(matchesIn2, isNotNull);
      expect(matchesIn2!.port.id, 'in2');

      // The same point, read with the desktop (default) formula, is nowhere
      // near either port's left-edge position and should not match in1.
      final NearestPortMatch? desktopReading = findNearestInputPort(
        graph,
        multiPortRegistry,
        const Offset(350, 15),
        excludeNodeId: 'none',
      );
      expect(desktopReading?.port.id, isNot('in1'));
    });
  });
}
