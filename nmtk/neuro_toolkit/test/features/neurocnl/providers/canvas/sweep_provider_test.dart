import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/sweep.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sweep_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';

// Minimal sweep request used across tests.
final _testGraph = CanvasGraph(
  nodes: <CanvasNode>[
    CanvasNode(
      id: 'n1',
      componentId: 'lif',
      parameters: const <String, dynamic>{'threshold': 1.0},
      position: const <double>[0, 0],
    ),
  ],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{
    'zoom': 1.0,
    'pan': <double>[0.0, 0.0],
  },
);

SweepRequest _makeSweepRequest() => SweepRequest(
  graph: _testGraph,
  parameterPath: 'nodes[0].parameters.threshold',
  start: 0.5,
  end: 2.0,
  steps: 4,
);

ProviderContainer _makeContainer(http.Client httpClient) {
  final container = ProviderContainer(
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test', httpClient: httpClient),
      ),
    ],
  );
  return container;
}

// Builds a synchronous (no job_id) sweep API response payload.
Map<String, dynamic> _sweepResponse({
  List<double> paramValues = const <double>[0.5, 1.0, 1.5, 2.0],
}) {
  return <String, dynamic>{
    'job_id': null,
    'status': 'completed',
    'error': null,
    'parameter_path': 'nodes[0].parameters.threshold',
    'backend_support': <String, dynamic>{
      'backend': 'nengo',
      'verdict': 'supported',
      'warnings': <String>[],
    },
    'generator_fidelity': null,
    'steps': paramValues.map((v) {
      return <String, dynamic>{
        'parameter_value': v,
        'result': <String, dynamic>{
          'job_id': null,
          'status': 'completed',
          'error': null,
          'results': <String, dynamic>{'spike_counts': <String, dynamic>{}},
          'metrics': null,
          'backend_support': null,
          'generator_fidelity': null,
        },
      };
    }).toList(),
  };
}

void main() {
  test('SweepController runs a sweep and populates results', () async {
    final container = _makeContainer(
      MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/neurosim/sweep') {
          return http.Response(
            jsonEncode(_sweepResponse()),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }),
    );
    addTearDown(container.dispose);

    await container.read(sweepProvider.notifier).runSweep(_makeSweepRequest());

    final state = container.read(sweepProvider);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.results, isNotNull);
    expect(state.results!.status, 'completed');
    expect(state.results!.steps!.length, 4);
    expect(state.results!.steps!.first.parameterValue, 0.5);
    expect(state.results!.steps!.last.parameterValue, 2.0);
    expect(state.backendSupport?.verdict, 'supported');
  });

  test('SweepController polls until a job completes', () async {
    var callCount = 0;
    const jobId = 'sweep-job-42';

    final container = _makeContainer(
      MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/neurosim/sweep') {
          callCount += 1;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'job_id': jobId,
              'status': 'queued',
              'error': null,
              'parameter_path': 'nodes[0].parameters.threshold',
              'backend_support': null,
              'generator_fidelity': null,
              'steps': null,
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        if (request.method == 'GET' &&
            request.url.path == '/api/neurosim/sweep/$jobId') {
          callCount += 1;
          // First poll: still running; second poll: completed.
          final isComplete = callCount >= 3;
          return http.Response(
            jsonEncode(
              isComplete
                  ? _sweepResponse()
                  : <String, dynamic>{
                      'job_id': jobId,
                      'status': 'running',
                      'error': null,
                      'parameter_path': 'nodes[0].parameters.threshold',
                      'backend_support': null,
                      'generator_fidelity': null,
                      'steps': null,
                    },
            ),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }),
    );
    addTearDown(container.dispose);
    // Keep the autoDispose sweepProvider alive across the polling loop's
    // real Future.delayed gaps — without an active listener it would be
    // disposed mid-flight once control yields to a macrotask.
    container.listen(sweepProvider, (_, _) {});

    await container.read(sweepProvider.notifier).runSweep(_makeSweepRequest());

    final state = container.read(sweepProvider);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.results!.status, 'completed');
    expect(state.results!.steps!.length, 4);
    // Initial POST + at least one status poll should have occurred.
    expect(callCount, greaterThanOrEqualTo(2));
  });

  test('SweepController surfaces an API error message', () async {
    final container = _makeContainer(
      MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'job_id': null,
            'status': 'failed',
            'error': 'Backend does not support sweep for this topology.',
            'parameter_path': 'nodes[0].parameters.threshold',
            'backend_support': <String, dynamic>{
              'backend': 'nengo',
              'verdict': 'unsupported',
              'warnings': <String>['Topology requires a recurrent connection.'],
            },
            'generator_fidelity': null,
            'steps': null,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(container.dispose);

    await container.read(sweepProvider.notifier).runSweep(_makeSweepRequest());

    final state = container.read(sweepProvider);
    expect(state.isLoading, isFalse);
    expect(state.error, isNotNull);
    expect(state.error, contains('Backend does not support sweep'));
    expect(state.backendSupport?.verdict, 'unsupported');
  });

  test('SweepController reset clears previous results and errors', () async {
    final container = _makeContainer(
      MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'job_id': null,
            'status': 'failed',
            'error': 'Some error',
            'parameter_path': 'nodes[0].parameters.threshold',
            'backend_support': null,
            'generator_fidelity': null,
            'steps': null,
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(container.dispose);

    await container.read(sweepProvider.notifier).runSweep(_makeSweepRequest());

    expect(container.read(sweepProvider).error, isNotNull);

    container.read(sweepProvider.notifier).reset();

    final state = container.read(sweepProvider);
    expect(state.isLoading, isFalse);
    expect(state.error, isNull);
    expect(state.results, isNull);
    expect(state.backendSupport, isNull);
  });
}
