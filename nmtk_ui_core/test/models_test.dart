import 'package:flutter/material.dart';
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
      const frame = SensorFrame(timestamp: 100.0, emgChannels: [1.0]);
      expect(frame.timestamp, 100.0);
    });
  });

  group('BulkSpikeFrame', () {
    test('fromJson parses a node-partitioned payload', () {
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

      expect(frame.isEmpty, isFalse);
      expect(frame.scale, VisualizationScale.density);
      expect(frame.nodes['pop_a']!.neuronCount, 6000);
      expect(frame.nodes['pop_a']!.data, [0.0, 10.0, 1.0, 20.0]);
    });

    test('fromJson defaults to raster scale and empty nodes when absent', () {
      final frame = BulkSpikeFrame.fromJson(const {});

      expect(frame.isEmpty, isTrue);
      expect(frame.scale, VisualizationScale.raster);
    });
  });

  group('NodeBulkData', () {
    test(
      'toVisualizationFrame carries neuronCount and honors a scale override',
      () {
        const nodeData = NodeBulkData(
          data: [0.0, 5.0],
          densityGrid: [0.9],
          gridW: 1,
          gridH: 1,
          neuronCount: 2000,
        );

        final frame = nodeData.toVisualizationFrame(
          simulationTimeMs: 12.0,
          scaleOverride: VisualizationScale.particle,
        );

        expect(frame.totalNeuronCount, 2000);
        expect(frame.scale, VisualizationScale.particle);
        expect(frame.simulationTimeMs, 12.0);
      },
    );
  });

  group('PynqNetworkResponse', () {
    test('fromJson parses exportable state and deploy payload', () {
      final json = {
        'support_state': 'exportable',
        'warnings': <String>[],
        'rejections': <String>[],
        'network_summary': {'n_neurons': 100, 'n_synapses': 200},
        'deploy_payload': {
          'weights': [1, 2, 3],
          'config': {'threshold': 1.0, 'bit_width': 8, 'scale_factor': 127.0},
          'bitstream_path': '/opt/overlays/snn_overlay.bit',
          'overlay_id': 'snn_overlay_v1',
          'overlay_version': '1.0.1',
          'weight_bit_width': 8,
          'max_supported_neurons': 256,
          'max_supported_synapses': 15360,
          'dma_ip_name': 'axi_dma_0',
          'snn_ip_name': 'snn_engine_0',
          'contract_digest': 'abc123',
          'register_map': {
            'base_address': 1073741824,
            'control_reg_offset': 0,
            'status_reg_offset': 4,
            'population_count_offset': 8,
            'input_neuron_count_offset': 12,
            'output_neuron_count_offset': 16,
            'timestep_count_offset': 20,
            'threshold_base_offset': 256,
            'neuron_base_offset': 256,
            'weight_base_offset': 4096,
            'dma_channel': 'axi_dma_0',
            'input_buffer_addr': 0,
            'output_buffer_addr': 0,
            'timestep_us': 1000,
            'addr_range': 65536,
          },
        },
      };
      final response = PynqNetworkResponse.fromJson(json);

      expect(response.supportState, PynqSupportState.exportable);
      expect(response.warnings, isEmpty);
      expect(response.rejectionReasons, isEmpty);
      expect(response.networkSummary?['n_neurons'], 100);
      expect(response.deployPayload, isNotNull);
      expect(response.deployPayload!.weightCount, 3);
      expect(response.deployPayload!.config.bitWidth, 8);
      expect(response.deployPayload!.overlayVersion, '1.0.1');
      expect(response.deployPayload!.maxSupportedSynapses, 15360);
      expect(response.deployPayload!.registerMap.dmaChannel, 'axi_dma_0');
      expect(response.deployPayload!.registerMap.populationCountOffset, 8);
      expect(response.deployPayload!.registerMap.thresholdBaseOffset, 256);

      final roundTrip = response.deployPayload!.toJson();
      final roundTripRegisterMap =
          roundTrip['register_map'] as Map<String, dynamic>;
      expect(roundTrip['overlay_id'], 'snn_overlay_v1');
      expect(roundTrip['overlay_version'], '1.0.1');
      expect(roundTrip['weight_bit_width'], 8);
      expect(roundTrip['max_supported_neurons'], 256);
      expect(roundTrip['max_supported_synapses'], 15360);
      expect(roundTrip['dma_ip_name'], 'axi_dma_0');
      expect(roundTrip['snn_ip_name'], 'snn_engine_0');
      expect(roundTrip['contract_digest'], 'abc123');
      expect(roundTripRegisterMap['population_count_offset'], 8);
      expect(roundTripRegisterMap['input_neuron_count_offset'], 12);
      expect(roundTripRegisterMap['output_neuron_count_offset'], 16);
      expect(roundTripRegisterMap['timestep_count_offset'], 20);
      expect(roundTripRegisterMap['threshold_base_offset'], 256);
      expect(roundTripRegisterMap['addr_range'], 65536);
    });

    test('fromJson parses exportable_with_warnings state', () {
      final json = {
        'support_state': 'exportable_with_warnings',
        'warnings': ['Network uses 205/256 neurons (>80% capacity)'],
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

    test('fromJson parses deploy payload when present', () {
      final json = {
        'support_state': 'exportable',
        'warnings': <String>[],
        'rejections': <String>[],
        'network_summary': {'n_neurons': 100},
        'deploy_payload': {
          'weights': [1, 2, 3],
          'config': {'bit_width': 8},
          'bitstream_path': 'snn_overlay.bit',
          'register_map': {'weight_base_offset': 4096},
        },
      };
      final response = PynqNetworkResponse.fromJson(json);

      expect(response.deployPayload, isNotNull);
      expect(response.deployPayload!.weights, [1.0, 2.0, 3.0]);
      expect(response.deployPayload!.config.bitWidth, 8);
      expect(response.deployPayload!.registerMap.weightBaseOffset, 4096);
    });
  });

  group('PynqSupportState', () {
    test('fromString returns notExportable for unknown values', () {
      expect(
        PynqSupportState.fromString('bogus'),
        PynqSupportState.notExportable,
      );
    });

    test('labels and icons are non-null for all states', () {
      final tokens = NmtkShellTokens.fromColorScheme(
        const ColorScheme.light(),
        Brightness.light,
      );
      for (final state in PynqSupportState.values) {
        expect(state.label.isNotEmpty, isTrue);
        expect(state.icon, isNotNull);
        expect(state.colorFor(tokens), isNotNull);
      }
    });
  });

  group('PynqDeployJob', () {
    test('fromJson parses configured state', () {
      final json = {
        'state': 'configured',
        'bitstream_path': '/overlays/snn_overlay.bit',
        'runtime_mode': 'simulator',
      };
      final job = PynqDeployJob.fromJson(json);

      expect(job.status, PynqDeployJobStatus.configured);
      expect(job.bitstreamPath, '/overlays/snn_overlay.bit');
      expect(job.runtimeMode, PynqBackendRuntimeMode.simulator);
    });

    test('fromJson parses not_initialised state', () {
      final json = {'state': 'not_initialised', 'bitstream_path': null};
      final job = PynqDeployJob.fromJson(json);

      expect(job.status, PynqDeployJobStatus.notInitialised);
      expect(job.bitstreamPath, isNull);
      expect(job.runtimeMode, PynqBackendRuntimeMode.unknown);
    });

    test('progressFraction is 1.0 for configured', () {
      expect(PynqDeployJobStatus.configured.progressFraction, 1.0);
    });

    test('progressFraction is 0.0 for failed', () {
      expect(PynqDeployJobStatus.failed.progressFraction, 0.0);
    });
  });

  group('PynqPairedBoard', () {
    test('fromJson parses paired board state', () {
      final json = {
        'id': 'board-1',
        'displayName': 'Lab PYNQ',
        'host': '192.168.1.50',
        'sshPort': 22,
        'username': 'xilinx',
        'authMode': 'ssh_key',
        'credentialRef': 'runtime-key',
        'runtimeApiUrl': 'http://192.168.1.50:8002',
        'runtimeApiUrlOverride': 'http://192.168.1.60:8002',
        'overlayVersion': '2026.04.14',
        'state': 'ready',
        'lastPreflightStatus': 'ok',
        'lastPreflightMessage': 'Ready',
        'lastRuntimeMode': 'hardware',
        'hasPassword': false,
        'sshKeyPath': '/Users/test/.ssh/pynq',
      };
      final board = PynqPairedBoard.fromJson(json);

      expect(board.id, 'board-1');
      expect(board.state, PynqBoardState.ready);
      expect(board.authMode, PynqBoardAuthMode.sshKey);
      expect(board.runtimeApiUrlOverride, 'http://192.168.1.60:8002');
      expect(board.isReady, isTrue);
    });

    test('toJson and copyWith preserve runtime API override separately', () {
      const board = PynqPairedBoard(
        id: 'board-1',
        displayName: 'Lab PYNQ',
        host: '192.168.1.50',
        sshPort: 22,
        username: 'xilinx',
        authMode: PynqBoardAuthMode.password,
        credentialRef: '',
        runtimeApiUrl: 'http://192.168.1.50:8002',
        runtimeApiUrlOverride: 'http://192.168.1.60:8002',
        overlayVersion: '',
        state: PynqBoardState.ready,
        lastPreflightStatus: 'ok',
        lastPreflightMessage: 'Ready',
        lastRuntimeMode: 'hardware',
        hasPassword: true,
        sshKeyPath: '',
      );

      final updated = board.copyWith(runtimeApiUrlOverride: '');
      final payload = board.toJson();

      expect(updated.runtimeApiUrlOverride, isEmpty);
      expect(payload['runtimeApiUrlOverride'], 'http://192.168.1.60:8002');
      expect(payload.containsKey('runtimeApiUrl'), isFalse);
    });

    test('fromJson parses preflight_failed board state', () {
      final json = {
        'id': 'board-1',
        'displayName': 'Lab PYNQ',
        'host': '192.168.1.50',
        'sshPort': 22,
        'username': 'xilinx',
        'authMode': 'password',
        'credentialRef': '',
        'runtimeApiUrl': 'http://192.168.1.50:8002',
        'overlayVersion': '',
        'state': 'preflight_failed',
        'lastPreflightStatus': 'failed',
        'lastPreflightMessage': 'Runtime probe failed.',
        'lastRuntimeMode': 'hardware',
        'hasPassword': true,
        'sshKeyPath': '',
      };
      final board = PynqPairedBoard.fromJson(json);

      expect(board.state, PynqBoardState.preflightFailed);
      expect(board.state.apiValue, 'preflight_failed');
      expect(board.state.label, 'Preflight Failed');
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
          {'label': 'zero_input', 'passed': true, 'execution_time_us': 38.0},
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

  group('AkidaSdkVerification', () {
    test('fromJson parses environment checks for simulator-only hosts', () {
      final verification = AkidaSdkVerification.fromJson({
        'sdk_available': false,
        'sdk_status': 'not_available',
        'sdk_issues': ['unsupported_os', 'sdk_not_available'],
        'state': 'not_initialised',
        'runtime_target': 'software_fallback',
        'environment_checks': {
          'host_supported': false,
          'python_supported': true,
          'tensorflow_available': false,
          'cnn2snn_available': false,
          'akida_models_available': false,
          'recommended_runtime': 'simulator_only',
        },
      });

      expect(verification.environmentChecks, isNotNull);
      expect(verification.environmentChecks!.hostSupported, isFalse);
      expect(
        verification.environmentChecks!.recommendedRuntimeMode,
        AkidaRuntimeMode.simulatorOnly,
      );
      expect(verification.runtimeMode, AkidaRuntimeMode.simulatorOnly);
      expect(
        verification.environmentChecks!.recommendedRuntime,
        'simulator_only',
      );
    });
  });

  group('AkidaPairedHost', () {
    test('fromJson parses remote host metadata and capability snapshot', () {
      final host = AkidaPairedHost.fromJson({
        'id': 'akida-host-1',
        'displayName': 'Linux Akida Host',
        'runtimeApiUrl': 'http://192.168.1.60:8002',
        'authMode': 'bearer_token',
        'credentialRef': 'akida-token',
        'hostOs': 'linux',
        'pythonVersion': '3.11.8',
        'runtimeMode': 'remote_sdk',
        'state': 'ready',
        'lastReadinessMessage': 'Remote SDK ready',
        'lastVerifiedAt': '2026-04-23T09:00:00Z',
        'capabilitySnapshot': {
          'hostSupported': true,
          'pythonSupported': true,
          'tensorflowAvailable': true,
          'cnn2snnAvailable': true,
          'akidaModelsAvailable': true,
          'recommendedRuntime': 'remote_sdk',
        },
      });

      expect(host.id, 'akida-host-1');
      expect(host.authMode, AkidaHostAuthMode.bearerToken);
      expect(host.runtimeMode, AkidaRuntimeMode.remoteSdk);
      expect(host.state, AkidaPairedHostState.ready);
      expect(host.isReady, isTrue);
      expect(
        host.capabilitySnapshot?.recommendedRuntimeMode,
        AkidaRuntimeMode.remoteSdk,
      );
    });

    test('toJson and copyWith preserve simulator-only runtime state', () {
      const host = AkidaPairedHost(
        id: 'akida-host-1',
        displayName: 'Linux Akida Host',
        host: '192.168.1.60',
        sshPort: 22,
        username: 'operator',
        runtimeApiUrl: 'http://192.168.1.60:8002',
        controlApiUrl: 'http://192.168.1.60:8091',
        authMode: AkidaHostAuthMode.none,
        credentialRef: '',
        password: '',
        hasPassword: false,
        sshKeyPath: '',
        remoteInstallRoot: '/opt/neurochip-akida-host',
        serviceUser: 'neurochip',
        hostOs: 'linux',
        pythonVersion: '3.11.8',
        runtimeMode: AkidaRuntimeMode.remoteSdk,
        state: AkidaPairedHostState.ready,
        lastReadinessMessage: 'Remote SDK ready',
        lastVerifiedAt: '2026-04-23T09:00:00Z',
      );

      final updated = host.copyWith(
        runtimeMode: AkidaRuntimeMode.simulatorOnly,
        state: AkidaPairedHostState.simulatorOnly,
      );
      final payload = updated.toJson();

      expect(updated.runtimeMode, AkidaRuntimeMode.simulatorOnly);
      expect(updated.state, AkidaPairedHostState.simulatorOnly);
      expect(payload['runtimeMode'], 'simulator_only');
      expect(payload['state'], 'simulator_only');
    });
  });
}
