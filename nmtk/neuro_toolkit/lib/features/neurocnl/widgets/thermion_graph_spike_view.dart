import 'package:flutter/material.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';

/// CEL-574 feasibility spike: renders [graph] as a static node-link scene
/// through Thermion/Filament instead of the CustomPainter canvas used by the
/// other Results > Brainviz tabs.
///
/// Additive only. Nothing in `results_brainviz_panel.dart`'s existing
/// CanvasGraph tab is touched; this view is reached from a separate mode
/// chip. Node spheres are merged into one draw call and edges into another,
/// which is the detail worth watching if this spike is extended to live
/// spike-event animation later — per-node native calls would not scale.
class ThermionGraphSpikeView extends StatelessWidget {
  const ThermionGraphSpikeView({super.key, required this.graph});

  final CanvasGraph graph;

  @override
  Widget build(BuildContext context) {
    if (graph.nodes.isEmpty) {
      return const Center(child: Text('No nodes to render.'));
    }
    return ViewerWidget(
      manipulatorType: ManipulatorType.ORBIT,
      background: const Color(0xFF14161A),
      initialCameraPosition: Vector3(0, 0, 9),
      directLight: DirectLight.sun(intensity: 110000, direction: Vector3(-1, -1.4, -1)),
      onViewerAvailable: (viewer) => _buildScene(viewer),
    );
  }

  Future<void> _buildScene(ThermionViewer viewer) async {
    final positions = _layoutPositions(graph);
    if (positions.isEmpty) return;

    final nodeMaterial = await viewer.app.createUnlitMaterialInstance();
    await nodeMaterial.setParameterFloat4('baseColorFactor', 0.42, 0.62, 0.98, 1.0);
    final nodeGeometry = _mergedNodeCubes(positions, radius: 0.09);
    await viewer.app.createGeometry(nodeGeometry, materialInstances: [nodeMaterial]);

    if (graph.edges.isNotEmpty) {
      final edgeMaterial = await viewer.app.createUnlitMaterialInstance();
      await edgeMaterial.setParameterFloat4('baseColorFactor', 0.55, 0.58, 0.66, 0.6);
      final edgeGeometry = _edgeLines(positions);
      if (edgeGeometry != null) {
        await viewer.app.createGeometry(edgeGeometry, materialInstances: [edgeMaterial]);
      }
    }
  }

  /// Maps each node's 2D canvas position into a centred, unit-scale 3D
  /// point so the merged geometry frames cleanly under [initialCameraPosition]
  /// regardless of the raw canvas pixel extents.
  Map<String, Vector3> _layoutPositions(CanvasGraph graph) {
    final nodes = graph.nodes.where((n) => n.position.length >= 2).toList();
    if (nodes.isEmpty) return const {};

    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final node in nodes) {
      final x = node.position[0];
      final y = node.position[1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final spanX = (maxX - minX).abs() < 1e-6 ? 1.0 : maxX - minX;
    final spanY = (maxY - minY).abs() < 1e-6 ? 1.0 : maxY - minY;
    final span = spanX > spanY ? spanX : spanY;
    const targetExtent = 6.0;
    final scale = targetExtent / span;
    final midX = (minX + maxX) / 2;
    final midY = (minY + maxY) / 2;

    return {
      for (final node in nodes)
        node.id: Vector3((node.position[0] - midX) * scale, (midY - node.position[1]) * scale, 0),
    };
  }

  Geometry _mergedNodeCubes(Map<String, Vector3> positions, {required double radius}) {
    final unitCube = CubeGeometry.cube();
    final verticesPerCube = unitCube.vertices.length ~/ 3;
    final indicesPerCube = unitCube.indices.length;

    final vertices = Float32List(positions.length * verticesPerCube * 3);
    final indices = Int32List(positions.length * indicesPerCube);

    var vOffset = 0;
    var iOffset = 0;
    var nodeIndex = 0;
    for (final center in positions.values) {
      for (var v = 0; v < verticesPerCube; v++) {
        vertices[vOffset + v * 3] = unitCube.vertices[v * 3] * radius + center.x;
        vertices[vOffset + v * 3 + 1] = unitCube.vertices[v * 3 + 1] * radius + center.y;
        vertices[vOffset + v * 3 + 2] = unitCube.vertices[v * 3 + 2] * radius + center.z;
      }
      final vertexBase = nodeIndex * verticesPerCube;
      for (var i = 0; i < indicesPerCube; i++) {
        indices[iOffset + i] = unitCube.indices[i] + vertexBase;
      }
      vOffset += verticesPerCube * 3;
      iOffset += indicesPerCube;
      nodeIndex++;
    }

    return Geometry(vertices, indices, indexType: IndexType.UINT);
  }

  Geometry? _edgeLines(Map<String, Vector3> positions) {
    final segments = <double>[];
    for (final edge in graph.edges) {
      final from = positions[edge.sourceNodeId];
      final to = positions[edge.targetNodeId];
      if (from == null || to == null) continue;
      segments
        ..addAll([from.x, from.y, from.z])
        ..addAll([to.x, to.y, to.z]);
    }
    if (segments.isEmpty) return null;

    final vertexCount = segments.length ~/ 3;
    return Geometry(
      Float32List.fromList(segments),
      List<int>.generate(vertexCount, (i) => i),
      primitiveType: PrimitiveType.LINES,
      indexType: IndexType.UINT,
    );
  }
}
