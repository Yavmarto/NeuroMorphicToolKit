import 'dart:typed_data';
import 'package:flutter/widgets.dart';

enum VisualizationScale {
  raster,
  particle,
  density;

  static VisualizationScale scaleFor(int neuronCount) {
    if (neuronCount <= 1000) return VisualizationScale.raster;
    if (neuronCount <= 100000) return VisualizationScale.particle;
    return VisualizationScale.density;
  }
}

class VisualizationFrame {
  final int totalNeuronCount;
  final Float32List spikeData;
  final Float32List densityGrid;
  final int gridW;
  final int gridH;
  final double simulationTimeMs;
  final VisualizationScale scale;

  VisualizationFrame({
    required this.totalNeuronCount,
    required this.spikeData,
    required this.densityGrid,
    required this.gridW,
    required this.gridH,
    required this.simulationTimeMs,
    required this.scale,
  });
}

abstract class NeuronRenderer {
  /// Push a new frame of spikes.
  void pushFrame(VisualizationFrame frame);

  /// Attach to canvas with a given size. Triggers async init if needed.
  void attach(Size size);

  /// Build the Flutter widget surface.
  Widget buildSurface(BuildContext context);

  void dispose();
}
