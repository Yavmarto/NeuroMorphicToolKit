import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient({
    this.websocketMessages = const <PreviewSocketMessage>[],
    this.websocketError,
    this.runPreviewResponse,
    this.pollResponses = const <PreviewResponse>[],
  }) : super(baseUrl: 'http://test');

  final List<PreviewSocketMessage> websocketMessages;
  final Object? websocketError;
  final PreviewResponse? runPreviewResponse;
  final List<PreviewResponse> pollResponses;

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async {
    return ValidationResult(valid: true, errors: const <ValidationError>[]);
  }

  @override
  Stream<PreviewSocketMessage> streamPreview(CanvasGraph graph) async* {
    if (websocketError != null) {
      throw websocketError!;
    }
    for (final message in websocketMessages) {
      yield message;
    }
  }

  @override
  Future<PreviewResponse> runPreview(CanvasGraph graph) async {
    return runPreviewResponse ??
        const PreviewResponse(
          status: 'completed',
          results: <String, dynamic>{},
        );
  }

  @override
  Future<PreviewResponse> getSimulationStatus(String jobId) async {
    if (pollResponses.isEmpty) {
      throw StateError('No poll response configured.');
    }
    return pollResponses.removeAt(0);
  }
}

CanvasGraph _testGraph() => CanvasGraph(
  nodes: <CanvasNode>[
    CanvasNode(
      id: 'n1',
      componentId: 'lif_population',
      parameters: const <String, dynamic>{'name': 'n1'},
      position: const <double>[0, 0],
    ),
  ],
  edges: const <CanvasEdge>[],
  metadata: const <String, dynamic>{},
);

PreviewPlayback _testPlayback() => const PreviewPlayback(
  durationMs: 100.0,
  sampleCount: 10,
  nodes: <PreviewNodePlayback>[
    PreviewNodePlayback(
      nodeId: 'n1',
      spikeTrains: <String, List<double>>{
        'n1:0': <double>[10.0, 30.0],
      },
      voltageTraces: <String, List<double>>{
        'n1:0': <double>[0.1, 0.2, 0.3],
      },
      spikeCount: 2,
    ),
  ],
  spikeEvents: <PreviewSpikeEvent>[
    PreviewSpikeEvent(
      nodeId: 'n1',
      neuronId: 'n1:0',
      neuronIndex: 0,
      timeMs: 10.0,
    ),
  ],
  summary: PreviewPlaybackSummary(totalSpikes: 2, activeNodeCount: 1),
);

PreviewResponse _completedResponse() => PreviewResponse(
  jobId: 'job-1',
  status: 'completed',
  results: const <String, dynamic>{'n1': <String, dynamic>{}},
  playback: _testPlayback(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'SimulationController prefers websocket streaming when available',
    () async {
      final container = ProviderContainer(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(
            _FakeCanvasApiClient(
              websocketMessages: <PreviewSocketMessage>[
                PreviewSocketMessage.fromJson(const <String, dynamic>{
                  'type': 'status',
                  'status': 'starting',
                }),
                PreviewSocketMessage.fromJson(<String, dynamic>{
                  'type': 'frame',
                  'status': 'running',
                  'current_time_ms': 50.0,
                  'playback': _testPlayback().toJson(),
                }),
                PreviewSocketMessage.fromJson(<String, dynamic>{
                  'type': 'completion',
                  'status': 'completed',
                  'response': _completedResponse().toJson(),
                }),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(canvasProvider.notifier).setGraph(_testGraph());
      await container.read(simulationProvider.notifier).runPreview();

      final state = container.read(simulationProvider);
      expect(state.transportMode, PreviewTransportMode.webSocket);
      expect(state.status, SimulationStatus.completed);
      expect(state.playback, isNotNull);
      expect(state.selectedNodeId, 'n1');
    },
  );

  test(
    'SimulationController falls back to polling when websocket fails',
    () async {
      final container = ProviderContainer(
        overrides: <Override>[
          apiClientProvider.overrideWithValue(
            _FakeCanvasApiClient(
              websocketError: StateError('socket unavailable'),
              runPreviewResponse: const PreviewResponse(
                jobId: 'job-2',
                status: 'queued',
                results: <String, dynamic>{},
              ),
              pollResponses: <PreviewResponse>[_completedResponse()],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Keep the autoDispose simulationProvider alive across the polling
      // fallback's real Future.delayed gap — without an active listener it
      // would be disposed mid-flight (Riverpod's zero-duration dispose
      // timer gets a chance to fire once control yields to a macrotask).
      container.listen(simulationProvider, (_, _) {});

      container.read(canvasProvider.notifier).setGraph(_testGraph());
      await container.read(simulationProvider.notifier).runPreview();

      final state = container.read(simulationProvider);
      expect(state.transportMode, PreviewTransportMode.polling);
      expect(state.status, SimulationStatus.completed);
      expect(state.playback, isNotNull);
    },
  );

  test('SimulationController restores and steps preview playback', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(simulationProvider.notifier)
        .restoreSnapshot(
          resultsJson: _completedResponse().toJson(),
          currentTime: 10.0,
        );
    container.read(simulationProvider.notifier).stepForward();

    final state = container.read(simulationProvider);
    expect(state.currentTime, greaterThan(10.0));
    expect(
      state.status == SimulationStatus.paused ||
          state.status == SimulationStatus.completed,
      isTrue,
    );
  });
}
