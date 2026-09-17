import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/pipeline_cnl_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

/// Builds a container with [apiClientProvider] overridden by a client whose
/// responses are driven by [handler].
ProviderContainer _makeContainer(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = ApiClient(
    baseUrl: 'http://test/api',
    httpClient: MockClient(handler),
  );
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
}

http.Response _jsonResponse(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('PipelineCnlController render', () {
    test('renders CNL text for the initial default pipeline config', () async {
      final container = _makeContainer((request) async {
        return _jsonResponse({
          'cnl_text': 'Train the network for 50 epochs.',
          'diagnostics': <String>[],
        });
      });
      addTearDown(container.dispose);

      // A persistent listener keeps this autoDispose provider alive across
      // the awaited HTTP round trip triggered by build()'s initial render.
      container.listen(pipelineCnlProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(pipelineCnlProvider);
      expect(state.value, 'Train the network for 50 epochs.');
    });

    test('re-renders (debounced) when pipeline config changes', () async {
      var requestCount = 0;
      final container = _makeContainer((request) async {
        requestCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final cfg = body['pipeline_config'] as Map<String, dynamic>;
        return _jsonResponse({
          'cnl_text': 'Train the network for ${cfg['epochs']} epochs.',
          'diagnostics': <String>[],
        });
      });
      addTearDown(container.dispose);

      // A persistent listener keeps this autoDispose provider alive across
      // the awaited HTTP round trip (a bare .read() would let it dispose
      // itself the moment the synchronous read call returns).
      container.listen(pipelineCnlProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(pipelineCnlProvider).value, contains('50'));

      container
          .read(canvasProvider.notifier)
          .updatePipeline(const PipelineConfig(epochs: 12));
      // Debounce is 300ms.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(container.read(pipelineCnlProvider).value, contains('12'));
      expect(requestCount, greaterThanOrEqualTo(2));
    });

    test('discards a stale response overtaken by a newer render', () async {
      final completers = <Completer<void>>[];
      var callIndex = 0;
      final container = _makeContainer((request) async {
        final index = callIndex++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final cfg = body['pipeline_config'] as Map<String, dynamic>;
        if (index == 0) {
          // First (initial) render: hang until released, so the second
          // render's response can arrive first.
          final completer = Completer<void>();
          completers.add(completer);
          await completer.future;
        }
        return _jsonResponse({
          'cnl_text': 'Train the network for ${cfg['epochs']} epochs.',
          'diagnostics': <String>[],
        });
      });
      addTearDown(container.dispose);

      // Kicks off the slow initial render; the listener keeps it alive.
      container.listen(pipelineCnlProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      container
          .read(canvasProvider.notifier)
          .updatePipeline(const PipelineConfig(epochs: 99));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // Release the slow first response after the second has already landed.
      completers.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The stale (epochs=50) response must not clobber the newer one.
      expect(container.read(pipelineCnlProvider).value, contains('99'));
    });
  });

  group('PipelineCnlController.applyCnlText', () {
    test('applies parsed config onto canvasProvider.pipeline', () async {
      final container = _makeContainer((request) async {
        if (request.url.path == '/api/notebook/generate-pipeline-cnl') {
          return _jsonResponse({'cnl_text': '', 'diagnostics': <String>[]});
        }
        return _jsonResponse({
          'pipeline_config': {'epochs': 7, 'optimizer': 'SGD'},
          'diagnostics': <String>[],
        });
      });
      addTearDown(container.dispose);
      container.listen(pipelineCnlProvider, (_, _) {});

      await container
          .read(pipelineCnlProvider.notifier)
          .applyCnlText('Train the network for 7 epochs with SGD optimizer.');

      expect(container.read(canvasProvider).pipeline.epochs, 7);
      expect(
        container.read(canvasProvider).pipeline.optimizer,
        PipelineOptimizer.sgd,
      );
      expect(
        container.read(pipelineCnlProvider).value,
        'Train the network for 7 epochs with SGD optimizer.',
      );
    });

    test(
      'a fail-closed parse error throws and leaves pipeline config untouched',
      () async {
        final container = _makeContainer((request) async {
          if (request.url.path == '/api/notebook/generate-pipeline-cnl') {
            return _jsonResponse({'cnl_text': '', 'diagnostics': <String>[]});
          }
          return _jsonResponse({'detail': 'unknown_optimizer_phrase'}, 422);
        });
        addTearDown(container.dispose);
        container.listen(pipelineCnlProvider, (_, _) {});

        final before = container.read(canvasProvider).pipeline;

        await expectLater(
          container
              .read(pipelineCnlProvider.notifier)
              .applyCnlText(
                'Train the network for 5 epochs with foo optimizer.',
              ),
          throwsA(isA<ApiException>()),
        );

        expect(container.read(canvasProvider).pipeline, equals(before));
      },
    );
  });
}
