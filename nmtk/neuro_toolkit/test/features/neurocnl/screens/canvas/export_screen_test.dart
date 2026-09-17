import 'package:riverpod_annotation/riverpod_annotation.dart';
// ignore_for_file: unused_element
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    show CanonicalEditorDocument;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart' as pipeline_api;
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_export_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/export_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' as pipeline_client;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';

/// setDocument triggers PipelineController.runParseAndValidate, which uses a
/// *different* apiClientProvider (api_provider.dart) than canvas export's own
/// (canvas/sync_provider.dart, overridden per-test below with a
/// request-throwing mock). Throwing here too keeps every test in this file
/// making zero real HTTP calls, not just the ones the mock client covers.
class _FakePipelineApi extends pipeline_client.ApiClient {
  _FakePipelineApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseResult> parse(String spec) async {
    throw StateError('unexpected');
  }

  @override
  Future<ValidationResult> validate(
    String spec, {
    Map<String, dynamic>? params,
    String backend = 'nir',
  }) async {
    throw StateError('unexpected');
  }
}

// Minimal canvas graph reused across tests.
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

ProviderContainer _makeContainer({
  required http.Client httpClient,
  NativeFileBackend? nativeFileBackend,
}) {
  return ProviderContainer(
    overrides: <Override>[
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test', httpClient: httpClient),
      ),
      pipeline_api.apiClientProvider.overrideWithValue(_FakePipelineApi()),
      if (nativeFileBackend != null)
        nativeFileAdapterProvider.overrideWithValue(
          FileAdapter(nativeFileBackend),
        ),
    ],
  );
}

Widget _buildHarness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: ExportScreen())),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ExportScreen renders format dropdown and export button for CNL format',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // CNL preflight is handled inline in the provider — no HTTP needed.
      final container = _makeContainer(
        httpClient: MockClient((_) async => throw StateError('unexpected')),
      );
      addTearDown(container.dispose);

      container.read(canvasProvider.notifier).setGraph(_testGraph);

      await tester.pumpWidget(_buildHarness(container));
      await tester.pumpAndSettle();

      expect(find.text('Export Design'), findsOneWidget);
      expect(find.byKey(const Key('export-format-dropdown')), findsOneWidget);
      expect(find.byKey(const Key('export-submit-button')), findsOneWidget);
      // The CNL preflight immediately sets backendSupport to 'supported'.
      expect(
        container.read(exportProvider).backendSupport?.verdict,
        'supported',
      );
    },
  );

  testWidgets(
    'ExportScreen exports CNL spec locally without making HTTP requests',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const canonicalCnl =
          'The neuron MUST fire ONLY IF membrane potential exceeds 0.8';

      final container = _makeContainer(
        httpClient: MockClient((_) async => throw StateError('unexpected')),
      );
      addTearDown(container.dispose);

      container.read(canvasProvider.notifier).setGraph(_testGraph);
      // Seed the CNL spec directly on the canonical doc (synchronous, no
      // backend call) — specTextProvider.notifier.set() now routes through a
      // real parse round-trip, which this test's httpClient deliberately
      // throws on to prove the *export* path itself makes no HTTP requests.
      container
          .read(canonicalDocProvider.notifier)
          .setDocument(
            const CanonicalEditorDocument(irJson: {}, cnlText: canonicalCnl),
          );

      await tester.pumpWidget(_buildHarness(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-submit-button')));
      await tester.pumpAndSettle();

      final exportState = container.read(exportProvider);
      expect(exportState.data, canonicalCnl);
      expect(exportState.format, 'cnl');
      expect(exportState.error, isNull);

      expect(find.byKey(const Key('export-result-title')), findsOneWidget);
      expect(find.text('Exported CNL:'), findsOneWidget);
      expect(find.text(canonicalCnl), findsOneWidget);
    },
  );

  // Tests the non-CNL preflight + export path directly via the notifier so we
  // don't rely on DropdownButton overlay interactions in the headless environment.
  test(
    'ExportController runs HTTP preflight then export for a non-CNL format',
    () async {
      const pythonOutput = '# Generated Nengo code\nimport nengo';
      var preflightCalled = false;
      var exportCalled = false;

      final container = _makeContainer(
        httpClient: MockClient((request) async {
          // Preflight: POST /api/neurosim/export/python?preflight=true
          if (request.method == 'POST' &&
              request.url.path == '/api/neurosim/export/python' &&
              request.url.queryParameters['preflight'] == 'true') {
            preflightCalled = true;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'backend_support': <String, dynamic>{
                  'backend': 'nengo',
                  'verdict': 'supported',
                  'warnings': <String>[],
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }

          // Export: POST /api/neurosim/export/python (no preflight query param)
          if (request.method == 'POST' &&
              request.url.path == '/api/neurosim/export/python' &&
              !request.url.queryParameters.containsKey('preflight')) {
            exportCalled = true;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'content': pythonOutput,
                'backend_support': <String, dynamic>{
                  'backend': 'nengo',
                  'verdict': 'supported',
                  'warnings': <String>[],
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }

          throw StateError(
            'Unexpected request: ${request.method} ${request.url}',
          );
        }),
      );
      addTearDown(container.dispose);

      container.read(canvasProvider.notifier).setGraph(_testGraph);
      final graphJson = container.read(canvasProvider).graph.toJson();

      // Step 1: preflight for the 'python' format.
      await container
          .read(exportProvider.notifier)
          .preflight('python', graphJson);
      expect(preflightCalled, isTrue);

      final afterPreflight = container.read(exportProvider);
      expect(afterPreflight.backendSupport?.verdict, 'supported');
      expect(afterPreflight.isLoading, isFalse);
      expect(afterPreflight.error, isNull);

      // Step 2: export.
      await container.read(exportProvider.notifier).export('python', graphJson);
      expect(exportCalled, isTrue);

      final afterExport = container.read(exportProvider);
      expect(afterExport.data, pythonOutput);
      expect(afterExport.format, 'python');
      expect(afterExport.error, isNull);
    },
  );

  testWidgets('ExportScreen offers NIR in the format dropdown', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _makeContainer(
      httpClient: MockClient((_) async => throw StateError('unexpected')),
    );
    addTearDown(container.dispose);
    container.read(canvasProvider.notifier).setGraph(_testGraph);

    await tester.pumpWidget(_buildHarness(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('export-format-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('NIR (.nir)'), findsWidgets);
  });

  test('ExportController decodes NIR exports into a binary artifact', () async {
    final nirBytes = Uint8List.fromList(<int>[0x89, 0x48, 0x44, 0x46]);
    final encoded = base64Encode(nirBytes);

    final container = _makeContainer(
      httpClient: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/neurosim/export/nir' &&
            request.url.queryParameters['preflight'] == 'true') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'backend_support': <String, dynamic>{
                'backend': 'nir',
                'verdict': 'supported',
                'warnings': <String>[],
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }

        if (request.method == 'POST' &&
            request.url.path == '/api/neurosim/export/nir' &&
            !request.url.queryParameters.containsKey('preflight')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'content': encoded,
              'backend_support': <String, dynamic>{
                'backend': 'nir',
                'verdict': 'supported',
                'warnings': <String>[],
              },
            }),
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
    container.read(canvasProvider.notifier).setGraph(_testGraph);

    final graphJson = container.read(canvasProvider).graph.toJson();
    await container.read(exportProvider.notifier).preflight('nir', graphJson);
    await container.read(exportProvider.notifier).export('nir', graphJson);

    final state = container.read(exportProvider);
    expect(state.format, 'nir');
    expect(state.data, isNull);
    expect(state.artifact?.filename, 'network.nir');
    expect(state.artifact?.bytes, nirBytes);
  });
}

class _FakeNativeFileBackend implements NativeFileBackend {
  String? lastBinarySuggestedName;
  Uint8List? lastBinaryBytes;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() async => null;

  @override
  Future<OpenedTextFile?> openWorkspaceFile() async => null;

  @override
  Future<OpenedBinaryFile?> openDatasetImport() async => null;

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) async {
    lastBinarySuggestedName = suggestedName;
    lastBinaryBytes = bytes;
    return const SaveResult(
      outcome: SaveOutcome.saved,
      path: '/tmp/network.nir',
    );
  }

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    return const SaveResult(outcome: SaveOutcome.saved);
  }

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) async {
    return const SaveResult(outcome: SaveOutcome.saved);
  }
}
