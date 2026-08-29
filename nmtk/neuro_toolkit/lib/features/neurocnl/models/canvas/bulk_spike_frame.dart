import 'dart:typed_data';

import 'package:nmtk_ui_core/visualization/renderer_interface.dart';

/// Per-node compact spike payload within a NeuroCNL bulk (large-network) frame.
/// Mirrors `NodeBulkData` in
/// neurocnl/neurosim/contracts/design_contracts.py.
class NodeBulkData {
  final List<double> data; // flat [local_neuron_idx, time_ms, ...]
  final List<double> densityGrid;
  final int gridW;
  final int gridH;
  final int neuronCount;

  const NodeBulkData({
    required this.data,
    required this.densityGrid,
    required this.gridW,
    required this.gridH,
    required this.neuronCount,
  });

  factory NodeBulkData.fromJson(Map<String, dynamic> json) {
    return NodeBulkData(
      data: (json['data'] as List? ?? const [])
          .map((v) => (v as num).toDouble())
          .toList(),
      densityGrid: (json['density_grid'] as List? ?? const [])
          .map((v) => (v as num).toDouble())
          .toList(),
      gridW: (json['grid_w'] as num?)?.toInt() ?? 0,
      gridH: (json['grid_h'] as num?)?.toInt() ?? 0,
      neuronCount: (json['neuron_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to a per-node [VisualizationFrame] for a single-node renderer.
  VisualizationFrame toVisualizationFrame({
    required double simulationTimeMs,
    VisualizationScale? scaleOverride,
  }) {
    return VisualizationFrame(
      totalNeuronCount: neuronCount,
      spikeData: Float32List.fromList(data),
      densityGrid: Float32List.fromList(densityGrid),
      gridW: gridW,
      gridH: gridH,
      simulationTimeMs: simulationTimeMs,
      scale: scaleOverride ?? VisualizationScale.scaleFor(neuronCount),
    );
  }
}

/// Node-partitioned compact spike payload for large-scale previews
/// (network-wide neuron count > 5 000). Mirrors `BulkSpikeFrame` in
/// neurocnl/neurosim/contracts/design_contracts.py.
class BulkSpikeFrame {
  final Map<String, NodeBulkData> nodes;
  final String scaleHint;

  const BulkSpikeFrame({required this.nodes, required this.scaleHint});

  factory BulkSpikeFrame.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'] as Map<String, dynamic>? ?? const {};
    return BulkSpikeFrame(
      nodes: rawNodes.map(
        (key, value) =>
            MapEntry(key, NodeBulkData.fromJson(value as Map<String, dynamic>)),
      ),
      scaleHint: json['scale_hint'] as String? ?? 'raster',
    );
  }

  VisualizationScale get scale => switch (scaleHint) {
    'particle' => VisualizationScale.particle,
    'density' => VisualizationScale.density,
    _ => VisualizationScale.raster,
  };

  bool get isEmpty => nodes.isEmpty;
}
