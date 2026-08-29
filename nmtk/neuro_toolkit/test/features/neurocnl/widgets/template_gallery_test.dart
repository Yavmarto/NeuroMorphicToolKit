// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart'
    as canvas_validation;
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/template_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart' as canvas_api;
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/template_gallery.dart';

import '../providers_test.mocks.dart';

class _TestTemplateController extends TemplateController {
  _TestTemplateController(this._templates);

  final List<CnlTemplate> _templates;

  @override
  AsyncValue<List<CnlTemplate>> build() {
    return AsyncValue.data(_templates);
  }

  @override
  Future<void> fetch() async {}
}

void main() {
  const template = CnlTemplate(
    id: 'example',
    name: 'Example Template',
    description: 'Replaces the current draft.',
    category: 'Foundations',
    tags: ['starter'],
    difficulty: 'beginner',
    validationBackend: 'nir',
    spec: 'The neuron MUST fire ONLY IF membrane potential exceeds 1.0',
  );

  late MockApiClient mockApi;
  late _FakeCanvasApiClient fakeCanvasApi;

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    ServerConfigService.debugResetForTests();
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
    mockApi = MockApiClient();
    fakeCanvasApi = _FakeCanvasApiClient();
    when(mockApi.parse(any)).thenAnswer(
      (_) async => const ParseResult(sentences: [], total: 0, errors: 0),
    );
    when(
      mockApi.validate(
        any,
        params: anyNamed('params'),
        backend: anyNamed('backend'),
      ),
    ).thenAnswer(
      (_) async => const ValidationResult(
        layer1: Layer1Result(overall: true, passed: [], failed: []),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: true,
      ),
    );
  });

  Widget buildGalleryApp(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TemplateGallery()),
      ),
    );
  }

  ProviderContainer buildContainer({NativeFileBackend? backend}) {
    return ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        canvas_sync.apiClientProvider.overrideWithValue(fakeCanvasApi),
        if (backend != null)
          nativeFileAdapterProvider.overrideWithValue(FileAdapter(backend)),
        templateProvider.overrideWith(
          () => _TestTemplateController(const [template]),
        ),
        workspaceBootstrapProvider.overrideWithValue(
          const WorkspaceBootstrap(
            initialRestoreState: <String, Object?>{
              'workspace': <String, Object?>{
                'files': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'draft-file',
                    'name': 'Draft.cnl',
                    'canonicalDocument': <String, Object?>{
                      'ir_json': <String, Object?>{},
                      'cnl_text': 'draft spec',
                    },
                    'dirty': true,
                    'isUntitled': false,
                    'cursorOffset': 10,
                    'selectionBase': 10,
                    'selectionExtent': 10,
                    'scrollOffset': 0.0,
                  },
                ],
                'activeFileId': 'draft-file',
              },
            },
          ),
        ),
      ],
    );
  }

  testWidgets(
    'template gallery keeps current draft when replacement is canceled',
    (WidgetTester tester) async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildGalleryApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Example Template'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Loading Example Template will replace unsaved changes in Draft.cnl.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(
        container
            .read(workspaceProvider)
            .activeFile
            ?.canonicalDocument
            ?.cnlText,
        'draft spec',
      );
    },
  );

  testWidgets('template gallery replaces the active draft after confirmation', (
    WidgetTester tester,
  ) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildGalleryApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Example Template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load template'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(
      container.read(workspaceProvider).activeFile?.canonicalDocument?.cnlText,
      template.spec,
    );
    // Validated twice: once automatically by CanonicalDocController.
    // updateFromCnl's internal runParseAndValidate call, and once more
    // explicitly by applyTemplateToWorkspace (which also passes the
    // template's validationBackend override). Both are expected under the
    // new single-path sync design.
    verify(
      mockApi.validate(
        template.spec,
        params: anyNamed('params'),
        backend: 'nir',
      ),
    ).called(2);
  });

  testWidgets('template gallery syncs loaded template into canvas graph', (
    WidgetTester tester,
  ) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    expect(container.read(canvasProvider).graph.nodes, isEmpty);

    await tester.pumpWidget(buildGalleryApp(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Example Template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load template'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final graph = container.read(canvasProvider).graph;
    expect(fakeCanvasApi.lastParsedSpec, template.spec);
    expect(graph.nodes.map((node) => node.id), containsAll(['pop_a', 'pop_b']));
    expect(graph.edges, hasLength(1));
  });

  testWidgets(
    'template gallery saves the active draft through the native adapter',
    (WidgetTester tester) async {
      final backend = _FakeNativeFileBackend(
        saveTextFileResult: const SaveResult(
          outcome: SaveOutcome.saved,
          path: '/tmp/Draft.cnl',
        ),
      );
      final container = buildContainer(backend: backend);
      addTearDown(container.dispose);

      await tester.pumpWidget(buildGalleryApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Example Template'));
      await tester.pumpAndSettle();
      final buttons = tester.widgetList<ZetaButton>(find.byType(ZetaButton));
      final saveButton = buttons.firstWhere(
        (b) => b.label == 'Save Active File',
      );
      saveButton.onPressed?.call();
      await tester.pumpAndSettle();

      expect(backend.lastTextSuggestedName, 'Draft.cnl');
      expect(backend.lastTextContents, 'draft spec');
      final activeFile = container.read(workspaceProvider).activeFile;
      expect(activeFile?.dirty, isFalse);
      expect(activeFile?.path, '/tmp/Draft.cnl');
    },
  );
}

class _FakeCanvasApiClient extends canvas_api.ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:8000');

  String? lastParsedSpec;

  @override
  Future<ParseCnlResponse> parseCnlCanonical(String specText) async {
    lastParsedSpec = specText;
    return ParseCnlResponse(
      document: CanonicalEditorDocument(
        irJson: const <String, dynamic>{},
        cnlText: specText,
        canvas: const canonical.CanvasProjection(
          nodes: [
            canonical.CanvasNode(id: 'pop_a', label: 'pop_a'),
            canonical.CanvasNode(id: 'pop_b', label: 'pop_b'),
          ],
          edges: [canonical.CanvasEdge(source: 'pop_a', target: 'pop_b')],
        ),
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canvas_validation.ValidationResult> validateGraph(
    CanvasGraph graph,
  ) async {
    return canvas_validation.ValidationResult(valid: true, errors: const []);
  }
}

class _FakeNativeFileBackend implements NativeFileBackend {
  _FakeNativeFileBackend({
    this.saveTextFileResult = const SaveResult(outcome: SaveOutcome.saved),
  });

  final SaveResult saveTextFileResult;

  String? lastTextSuggestedName;
  String? lastTextContents;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() async {
    return null;
  }

  @override
  Future<OpenedTextFile?> openWorkspaceFile() async {
    return null;
  }

  @override
  Future<OpenedBinaryFile?> openDatasetImport() async => null;

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    lastTextSuggestedName = suggestedName;
    lastTextContents = contents;
    return saveTextFileResult;
  }

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) async {
    return const SaveResult(outcome: SaveOutcome.saved);
  }

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) async {
    return const SaveResult(outcome: SaveOutcome.saved);
  }
}
