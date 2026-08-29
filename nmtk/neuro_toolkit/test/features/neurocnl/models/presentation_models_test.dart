import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/bulk_spike_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/models/energy_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/quantization_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sensor_frame.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' show VisualizationScale;

void main() {
  group('EnergyReport', () {
    test('decodes the backend payload', () {
      final report = EnergyReport.fromJson({
        'per_ensemble_pj': {'E1': 10.5, 'E2': 20.0},
        'total_pj': 30.5,
        'ops_count': 1000,
      });

      expect(report.perEnsemblePj, {'E1': 10.5, 'E2': 20.0});
      expect(report.totalPj, 30.5);
      expect(report.opsCount, 1000);
    });
  });

  group('QuantizationReport', () {
    test('decodes the backend payload', () {
      final report = QuantizationReport.fromJson({
        'bit_widths': [8, 4],
        'accuracy_drops': [0.01, 0.05],
        'sparsity': [0.5, 0.8],
      });

      expect(report.bitWidths, [8, 4]);
      expect(report.accuracyDrops, [0.01, 0.05]);
      expect(report.sparsity, [0.5, 0.8]);
    });
  });

  group('SensorFrame', () {
    test('decodes optional hardware fields', () {
      final frame = SensorFrame.fromJson({
        'timestamp': 123.456,
        'emg_channels': [0.1, 0.2, 0.3],
        'eeg_bands': {'alpha': 0.5},
        'proximity': 10.0,
      });

      expect(frame.timestamp, 123.456);
      expect(frame.eegBands?['alpha'], 0.5);
      expect(frame.proximity, 10.0);
    });
  });

  group('BulkSpikeFrame', () {
    test('decodes bulk-node payloads and keeps the renderer scale', () {
      final frame = BulkSpikeFrame.fromJson({
        'nodes': {
          'pop_a': {
            'data': [0.0, 10.0, 1.0, 20.0],
            'density_grid': [0.5],
            'grid_w': 1,
            'grid_h': 1,
            'neuron_count': 6000,
          },
        },
        'scale_hint': 'density',
      });

      expect(frame.scale, VisualizationScale.density);
      expect(frame.nodes['pop_a']!.neuronCount, 6000);
    });
  });
}
