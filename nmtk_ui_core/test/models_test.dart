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

  group('PynqNetworkResponse', () {
    test('fromJson parses exportable state', () {
      final json = {
        'support_state': 'exportable',
        'warnings': <String>[],
        'rejections': <String>[],
        'network_summary': {'n_neurons': 100, 'n_synapses': 200},
      };
      final response = PynqNetworkResponse.fromJson(json);

      expect(response.supportState, PynqSupportState.exportable);
      expect(response.warnings, isEmpty);
      expect(response.rejectionReasons, isEmpty);
      expect(response.networkSummary?['n_neurons'], 100);
    });

    test('fromJson parses exportable_with_warnings state', () {
      final json = {
        'support_state': 'exportable_with_warnings',
        'warnings': ['Network uses 52429/65536 neurons (>80% capacity)'],
        'rejections': <String>[],
        'network_summary': null,
      };
      final response = PynqNetworkResponse.fromJson(json);

      expect(response.supportState, PynqSupportState.exportableWithWarnings);
      expect(response.warnings.length, 1);
    });

    test('fromJson parses not_exportable state', () {
      final json = {
        'support_state': 'not_exportable',
        'warnings': <String>[],
        'rejections': ['Exceeds neuron capacity'],
        'network_summary': null,
      };
      final response = PynqNetworkResponse.fromJson(json);

      expect(response.supportState, PynqSupportState.notExportable);
      expect(response.rejectionReasons.length, 1);
    });
  });

  group('PynqSupportState', () {
    test('fromString returns notExportable for unknown values', () {
      expect(PynqSupportState.fromString('bogus'), PynqSupportState.notExportable);
    });

    test('labels and icons are non-null for all states', () {
      for (final state in PynqSupportState.values) {
        expect(state.label.isNotEmpty, isTrue);
        expect(state.icon, isNotNull);
        expect(state.color, isNotNull);
      }
    });
  });

  group('PynqDeployJob', () {
    test('fromJson parses configured state', () {
      final json = {
        'state': 'configured',
        'bitstream_path': '/overlays/snn_overlay.bit',
      };
      final job = PynqDeployJob.fromJson(json);

      expect(job.status, PynqDeployJobStatus.configured);
      expect(job.bitstreamPath, '/overlays/snn_overlay.bit');
    });

    test('fromJson parses not_initialised state', () {
      final json = {'state': 'not_initialised', 'bitstream_path': null};
      final job = PynqDeployJob.fromJson(json);

      expect(job.status, PynqDeployJobStatus.notInitialised);
      expect(job.bitstreamPath, isNull);
    });

    test('progressFraction is 1.0 for configured', () {
      expect(PynqDeployJobStatus.configured.progressFraction, 1.0);
    });

    test('progressFraction is 0.0 for failed', () {
      expect(PynqDeployJobStatus.failed.progressFraction, 0.0);
    });
  });

  group('PynqSitlVerifyResult', () {
    test('fromJson parses a passing verification', () {
      final json = {
        'passed': true,
        'total_cases': 3,
        'passed_cases': 3,
        'mean_exec_us': 42.5,
        'max_exec_us': 58.1,
        'summary': 'All 3 cases passed',
        'steps': [
          {
            'label': 'zero_input',
            'passed': true,
            'execution_time_us': 38.0,
          },
        ],
      };
      final result = PynqSitlVerifyResult.fromJson(json);

      expect(result.passed, isTrue);
      expect(result.totalCases, 3);
      expect(result.passedCases, 3);
      expect(result.meanExecUs, 42.5);
      expect(result.steps.length, 1);
      expect(result.steps.first.label, 'zero_input');
      expect(result.steps.first.passed, isTrue);
    });

    test('fromJson parses a failing verification', () {
      final json = {
        'passed': false,
        'total_cases': 2,
        'passed_cases': 1,
        'mean_exec_us': 50.0,
        'max_exec_us': 70.0,
        'summary': '1/2 cases failed',
        'steps': <Object>[],
      };
      final result = PynqSitlVerifyResult.fromJson(json);

      expect(result.passed, isFalse);
      expect(result.passedCases, 1);
    });
  });
}
