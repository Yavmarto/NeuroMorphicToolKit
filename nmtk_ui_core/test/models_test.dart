import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('EnergyReport', () {
    test('fromJson creates a valid object', () {
      final json = {
        'per_ensemble_pj': {'E1': 10.5, 'E2': 20.0},
        'total_pj': 30.5,
        'ops_count': 1000,
      };
      final report = EnergyReport.fromJson(json);

      expect(report.perEnsemblePj['E1'], 10.5);
      expect(report.perEnsemblePj['E2'], 20.0);
      expect(report.totalPj, 30.5);
      expect(report.opsCount, 1000);
    });

    test('constructor creates a valid object', () {
      const report = EnergyReport(
        perEnsemblePj: {'E1': 5.0},
        totalPj: 5.0,
        opsCount: 50,
      );
      expect(report.totalPj, 5.0);
    });

    // Test serialization/deserialization logic fully (mocking toJSON if we had it)
    // Here we ensure all fields map precisely from untyped maps
  });

  group('QuantizationReport', () {
    test('fromJson creates a valid object', () {
      final json = {
        'bit_widths': [8, 4],
        'accuracy_drops': [0.01, 0.05],
        'sparsity': [0.5, 0.8],
      };
      final report = QuantizationReport.fromJson(json);

      expect(report.bitWidths, [8, 4]);
      expect(report.accuracyDrops, [0.01, 0.05]);
      expect(report.sparsity, [0.5, 0.8]);
    });

    test('constructor creates a valid object', () {
      const report = QuantizationReport(
        bitWidths: [8],
        accuracyDrops: [0.02],
        sparsity: [0.3],
      );
      expect(report.bitWidths, [8]);
    });
  });

  group('SensorFrame', () {
    test('fromJson creates a valid object with all fields', () {
      final json = {
        'timestamp': 123.456,
        'emg_channels': [0.1, 0.2, 0.3],
        'eeg_bands': {'alpha': 0.5, 'beta': 0.2},
        'proximity': 10.0,
      };
      final frame = SensorFrame.fromJson(json);

      expect(frame.timestamp, 123.456);
      expect(frame.emgChannels, [0.1, 0.2, 0.3]);
      expect(frame.eegBands?['alpha'], 0.5);
      expect(frame.proximity, 10.0);
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'timestamp': 0.0,
        'emg_channels': [0.0],
      };
      final frame = SensorFrame.fromJson(json);

      expect(frame.eegBands, isNull);
      expect(frame.proximity, isNull);
    });

    test('constructor creates a valid object', () {
      const frame = SensorFrame(
        timestamp: 100.0,
        emgChannels: [1.0],
      );
      expect(frame.timestamp, 100.0);
    });
  });
}
