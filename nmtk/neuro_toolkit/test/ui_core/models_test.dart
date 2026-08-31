import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  group('PynqNetworkResponse', () {
    test('fromJson parses exportable state and deploy payload', () {
      final json = {
        'support_state': 'exportable',
        'warnings': <String>[],
        'rejections': <String>[],
        'network_summary': {'n_neurons': 100, 'n_synapses': 200},
        'deploy_payload': {
          'weights': [1, 2, 3],
          'config': {
            'threshold': 1.0,
            'bit_width': 8,
            'scale_factor': 127.0,
            'timestep_us': 1000,
          },
          'bitstream_path': '/opt/overlays/snn_overlay.bit',
          'overlay_id': 'snn_overlay_v2',
          'overlay_version': '2.0.0',
          'weight_bit_width': 8,
          'max_supported_neurons': 4096,
          'max_supported_synapses': 262144,
          'dma_ip_name': 'axi_dma_0',
          'snn_ip_name': 'snn_engine_0',
          'contract_digest': 'abc123',
          // The overlay-v2 map as the backend resolves it from the `.hwh`.
          'register_map': {
            'resolved_from_hwh': true,
            'base_address': 1073741824,
            'control_reg_offset': 0,
            'global_interrupt_enable_offset': 4,
            'interrupt_enable_offset': 8,
            'interrupt_status_offset': 12,
            'weights_ptr_offset': 16,
            'layer_config_ptr_offset': 28,
            'layer_count_offset': 40,
            'weight_count_offset': 48,
            'timestep_count_offset': 56,
            'dma_channel': 'axi_dma_0',
            'timestep_us': 1000,
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
      expect(response.deployPayload!.overlayVersion, '2.0.0');
      expect(response.deployPayload!.maxSupportedSynapses, 262144);
      expect(response.deployPayload!.registerMap.dmaChannel, 'axi_dma_0');

      final roundTrip = response.deployPayload!.toJson();
      expect(roundTrip['overlay_id'], 'snn_overlay_v2');
      expect(roundTrip['overlay_version'], '2.0.0');
      expect(roundTrip['weight_bit_width'], 8);
      expect(roundTrip['max_supported_neurons'], 4096);
      expect(roundTrip['max_supported_synapses'], 262144);
      expect(roundTrip['dma_ip_name'], 'axi_dma_0');
      expect(roundTrip['snn_ip_name'], 'snn_engine_0');
      expect(roundTrip['contract_digest'], 'abc123');

      // The board rejects a deploy whose register map is not *equal* to the
      // manifest it has installed, so the map has to come back exactly as it
      // arrived — no key added, none dropped, none renamed.
      final payloadJson = json['deploy_payload'] as Map<String, dynamic>;
      expect(roundTrip['register_map'], equals(payloadJson['register_map']));
      // Same rule for config: `timestep_us` has no field here and still has to
      // reach the board.
      expect(roundTrip['config'], equals(payloadJson['config']));
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
          'register_map': {'weights_ptr_offset': 16},
        },
      };
      final response = PynqNetworkResponse.fromJson(json);

      expect(response.deployPayload, isNotNull);
      expect(response.deployPayload!.weights, [1.0, 2.0, 3.0]);
      expect(response.deployPayload!.config.bitWidth, 8);
      expect(
        response.deployPayload!.registerMap.values['weights_ptr_offset'],
        16,
      );
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

  group('PynqRunResult', () {
    test('reads an all-zero frame as a silent run, not ten spikes', () {
      // The board's answer to the screenshot's run: one word per output neuron,
      // all zero. Reporting `outputSpikes.length` as the spike total said
      // "Output spikes 10" for a network that fired nothing.
      final result = PynqRunResult.fromJson({
        'status': 'success',
        'output_spikes': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        'timesteps': 1,
        'execution_time_us': 36420.0,
        'output_neurons': 10,
        'kernel_reported_done': true,
      });

      expect(result.outputNeurons, 10);
      expect(result.frameWidth, 10);
      expect(result.totalSpikes, 0);
      expect(result.predictedClass, isNull);
    });

    test('folds a multi-timestep stream into per-neuron spike counts', () {
      final result = PynqRunResult.fromJson({
        'status': 'success',
        'output_spikes': [
          0, 0, 1, // t0 — neuron 2
          0, 1, 1, // t1 — neurons 1 and 2
        ],
        'timesteps': 2,
        'execution_time_us': 1000.0,
        'output_neurons': 3,
      });

      expect(result.spikeCountsPerNeuron, [0, 1, 2]);
      expect(result.totalSpikes, 3);
      expect(result.predictedClass, 2);
    });

    test('an older runtime that omits the new fields is not flagged', () {
      final result = PynqRunResult.fromJson({
        'status': 'success',
        'output_spikes': [1, 0, 0, 1],
        'timesteps': 2,
        'execution_time_us': 500.0,
      });

      expect(result.kernelReportedDone, isTrue);
      // No width reported, but the stream divides evenly by the timesteps:
      // [1, 0] at t0 and [0, 1] at t1, so each neuron fired once.
      expect(result.frameWidth, 2);
      expect(result.spikeCountsPerNeuron, [1, 1]);
    });

    test('carries a kernel that never reported done', () {
      final result = PynqRunResult.fromJson({
        'status': 'success',
        'output_spikes': [0, 0],
        'timesteps': 1,
        'execution_time_us': 10.0,
        'output_neurons': 2,
        'kernel_reported_done': false,
      });

      expect(result.status, 'success');
      expect(result.kernelReportedDone, isFalse);
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
