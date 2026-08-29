import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/bulk_spike_frame.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' show VisualizationScale;

void main() {
  test(
    'NodeBulkData converts to a per-node VisualizationFrame with scale override',
    () {
      const nodeData = NodeBulkData(
        data: <double>[0, 1.5, 4, 2.5],
        densityGrid: <double>[0.1, 0.9],
        gridW: 2,
        gridH: 1,
        neuronCount: 10000,
      );

      final visualizationFrame = nodeData.toVisualizationFrame(
        simulationTimeMs: 33.3,
        scaleOverride: VisualizationScale.raster,
      );

      expect(visualizationFrame.scale, VisualizationScale.raster);
      expect(visualizationFrame.totalNeuronCount, 10000);
      expect(visualizationFrame.spikeData.length, 4);
      expect(visualizationFrame.densityGrid.length, 2);
    },
  );

  test(
    'NodeBulkData falls back to VisualizationScale.scaleFor without an override',
    () {
      const nodeData = NodeBulkData(
        data: <double>[],
        densityGrid: <double>[],
        gridW: 0,
        gridH: 0,
        neuronCount: 500,
      );

      final visualizationFrame = nodeData.toVisualizationFrame(
        simulationTimeMs: 0,
      );

      expect(visualizationFrame.scale, VisualizationScale.raster);
    },
  );

  test('BulkSpikeFrame.fromJson parses a node-partitioned payload', () {
    final frame = BulkSpikeFrame.fromJson({
      'nodes': {
        'n1': {
          'data': [0.0, 1.5],
          'density_grid': [0.2],
          'grid_w': 1,
          'grid_h': 1,
          'neuron_count': 6000,
        },
      },
      'scale_hint': 'particle',
    });

    expect(frame.scale, VisualizationScale.particle);
    expect(frame.isEmpty, isFalse);
    expect(frame.nodes.containsKey('n1'), isTrue);
    expect(frame.nodes['n1']!.neuronCount, 6000);
  });

  test('BulkSpikeFrame.fromJson defaults to raster scale and empty nodes', () {
    final frame = BulkSpikeFrame.fromJson(const {});

    expect(frame.scale, VisualizationScale.raster);
    expect(frame.isEmpty, isTrue);
  });
}
