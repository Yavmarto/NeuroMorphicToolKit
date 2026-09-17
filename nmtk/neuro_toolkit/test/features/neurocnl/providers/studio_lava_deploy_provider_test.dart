import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_lava_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_lava_deploy_service.dart';

class _FakeStudioLavaDeployService extends StudioLavaDeployService {
  _FakeStudioLavaDeployService({required this.exportResult})
    : super(
        apiClient: ApiClient(baseUrl: 'http://test'),
        neurochipClient: NeurochipClient(baseUrl: 'http://test'),
      );

  final Map<String, dynamic> exportResult;
  final String compileSessionId = 'lava-session-1';
  final Map<String, dynamic> runResult = const <String, dynamic>{
    'status': 'success',
  };

  String? lastValidatedSpec;
  Map<String, dynamic>? lastCompiledPayload;
  String? lastCompileRunConfig;
  String? lastRunSessionId;
  int? lastRunSteps;

  @override
  Future<Map<String, dynamic>> validate({
    required String spec,
    required int bitWidth,
  }) async {
    lastValidatedSpec = spec;
    return exportResult;
  }

  @override
  Future<String> compile({
    required Map<String, dynamic> deployPayload,
    required String runConfig,
  }) async {
    lastCompiledPayload = deployPayload;
    lastCompileRunConfig = runConfig;
    return compileSessionId;
  }

  @override
  Future<Map<String, dynamic>> run({
    required String sessionId,
    required int steps,
  }) async {
    lastRunSessionId = sessionId;
    lastRunSteps = steps;
    return runResult;
  }
}

void main() {
  const exportResult = <String, dynamic>{
    'support_state': 'exportable',
    'warnings': <String>[],
    'rejections': <String>[],
    'network_summary': <String, dynamic>{'n_neurons': 4},
    'deploy_payload': <String, dynamic>{
      'num_neurons': 4,
      'num_synapses': 4,
      'neuron_model': 'LIF',
      'populations': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'sensory', 'size': 2, 'threshold': 1.0},
        <String, dynamic>{'name': 'motor', 'size': 2, 'threshold': 1.0},
      ],
      'connections': <Map<String, dynamic>>[
        <String, dynamic>{
          'pre': 'sensory',
          'post': 'motor',
          'weight_count': 4,
          'weights': <List<double>>[
            <double>[1.0, 0.0],
            <double>[0.0, 1.0],
          ],
        },
      ],
      'weight_bit_width': 8,
      'network_depth': 2,
    },
  };

  test('validate records exportability result', () async {
    final service = _FakeStudioLavaDeployService(exportResult: exportResult);
    final container = ProviderContainer(
      overrides: [studioLavaDeployServiceProvider.overrideWithValue(service)],
    );
    final provider = container.read(
      studioLavaDeployControllerProvider.notifier,
    );

    await provider.validate('population lif');

    expect(service.lastValidatedSpec, 'population lif');
    expect(provider.state.exportResult?['support_state'], 'exportable');
    expect(
      provider.state.activityMessage,
      'Exportable for Lava simulator execution.',
    );
    expect(provider.state.errorMessage, isNull);
  });

  test('run compiles then runs simulator session', () async {
    final service = _FakeStudioLavaDeployService(exportResult: exportResult);
    final container = ProviderContainer(
      overrides: [studioLavaDeployServiceProvider.overrideWithValue(service)],
    );
    final provider = container.read(studioLavaDeployControllerProvider.notifier)
      ..setRunSteps(3);

    await provider.run('population lif');

    expect(service.lastValidatedSpec, 'population lif');
    expect(service.lastCompileRunConfig, 'sim');
    expect(service.lastRunSessionId, 'lava-session-1');
    expect(service.lastRunSteps, 3);
    expect(provider.state.runResult?['status'], 'success');
    expect(provider.state.activityMessage, 'Simulator run completed.');
  });
}
