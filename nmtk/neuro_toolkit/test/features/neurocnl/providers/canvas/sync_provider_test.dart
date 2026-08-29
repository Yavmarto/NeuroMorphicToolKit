import 'package:riverpod_annotation/riverpod_annotation.dart';
// ignore_for_file: unused_element
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    show CanonicalEditorDocument;
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a container whose apiClientProvider is backed by [httpClient] and
/// whose pipelineProvider is a no-op stub (avoids post-dispose async errors).
ProviderContainer _makeContainer({required http.Client httpClient}) {
  return ProviderContainer(
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test', httpClient: httpClient),
      ),
      pipelineProvider.overrideWith(
        () => _NoOpPipelineController(const PipelineState()),
      ),
    ],
  );
}

/// No-op PipelineController that ignores runParseAndValidate to prevent
/// post-dispose async errors in unit tests.
///
/// runParseAndValidate is a concrete inherited method, so noSuchMethod never
/// intercepts it — it must be overridden directly.
class _NoOpPipelineController extends PipelineController {
  _NoOpPipelineController(this._initialState);
  final PipelineState _initialState;

  @override
  PipelineState build() => _initialState;

  @override
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {}
}

/// A [ParseCnlResponse]-shaped JSON body with the given [cnlText].
Map<String, dynamic> _canonicalResponse(String cnlText) => <String, dynamic>{
  'document': <String, dynamic>{
    'ir_json': <String, dynamic>{
      'populations': <String, dynamic>{},
      'connections': <dynamic>[],
      'metadata': <String, dynamic>{},
    },
    'cnl_text': cnlText,
    'fidelity_annotations': <dynamic>[],
    'canvas': <String, dynamic>{
      'nodes': <dynamic>[],
      'edges': <dynamic>[],
      'read_only_annotations': <dynamic>[],
    },
  },
  'diagnostics': <dynamic>[],
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('canvasSyncIssueProvider — initial state', () {
    test('is null at construction', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(canvasSyncIssueProvider), isNull);
    });
  });

  group('apiClientProvider — wires to ApiClient', () {
    test('provides an ApiClient instance', () {
      final container = _makeContainer(
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      addTearDown(container.dispose);
      final client = container.read(apiClientProvider);
      expect(client, isA<ApiClient>());
    });
  });

  group('canonicalDocProvider.updateFromCanvas — comment preservation', () {
    /// Mock that handles both /canvas-to-canonical and /parse-cnl-canonical
    /// with an empty canvas, returning the given [cnlText].
    http.Client mockCanonical(String cnlText) {
      return MockClient((request) async {
        if (request.method == 'POST' &&
            (request.url.path.endsWith('/canvas-to-canonical') ||
                request.url.path.endsWith('/parse-cnl-canonical'))) {
          return http.Response(
            jsonEncode(_canonicalResponse(cnlText)),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/validate')) {
          return http.Response(
            jsonEncode(<String, dynamic>{'valid': true, 'errors': <dynamic>[]}),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      });
    }

    CanvasGraph oneNodeGraph() => CanvasGraph(
      nodes: [
        CanvasNode(
          id: 'n1',
          componentId: 'lif_population',
          parameters: const {},
          position: const [0, 0],
        ),
      ],
      edges: const <CanvasEdge>[],
      metadata: const <String, dynamic>{},
    );

    test('updateFromCanvas re-injects user comments absent from the API '
        'response', () async {
      final container = _makeContainer(
        httpClient: mockCanonical('affine layer with 4 units'),
      );
      addTearDown(container.dispose);

      // Seed the previous doc with a comment the backend regeneration
      // (mocked above) does not echo back.
      container
          .read(canonicalDocProvider.notifier)
          .setDocument(
            const _TestDoc(cnlText: '# my important note\naffine layer'),
          );

      await container
          .read(canonicalDocProvider.notifier)
          .updateFromCanvas(oneNodeGraph());

      final cnlText = container.read(canonicalDocProvider).value?.cnlText;
      expect(cnlText, contains('# my important note'));
      expect(cnlText, contains('affine layer with 4 units'));
    });

    test('updateFromCanvas does not duplicate a comment already present in the '
        'API response', () async {
      final container = _makeContainer(
        httpClient: mockCanonical('# already there\naffine layer'),
      );
      addTearDown(container.dispose);

      container
          .read(canonicalDocProvider.notifier)
          .setDocument(const _TestDoc(cnlText: '# already there\nold text'));

      await container
          .read(canonicalDocProvider.notifier)
          .updateFromCanvas(oneNodeGraph());

      final cnlText = container.read(canonicalDocProvider).value?.cnlText;
      // Exactly one occurrence — not re-appended on top of itself.
      expect('# already there'.allMatches(cnlText ?? '').length, 1);
    });
  });
}

/// Shorthand constructor for a canonical doc with only [cnlText] set —
/// the other fields (irJson, canvas) are irrelevant to comment-preservation
/// assertions.
class _TestDoc extends CanonicalEditorDocument {
  const _TestDoc({required super.cnlText}) : super(irJson: const {});
}
