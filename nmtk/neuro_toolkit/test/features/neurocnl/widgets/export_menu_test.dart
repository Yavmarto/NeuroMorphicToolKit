import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart' as cd;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart'
    as canvas_client;
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/export_menu.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Always returns the same fixed set of picked files, regardless of the
/// requested extensions — used to simulate a user picking a JSON config
/// through the native file dialog without touching the real platform
/// channel.
class _FakeFilePickerGateway implements NativeFileDialogGateway {
  _FakeFilePickerGateway(this.files);

  final List<PickedFileData>? files;

  @override
  Future<List<PickedFileData>?> pickFiles({
    required bool allowMultiple,
    required List<String> allowedExtensions,
    bool loadBytes = true,
  }) async => files;

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) async => null;
}

/// specTextProvider.notifier.set() now routes through a real backend parse
/// call (canonicalDocProvider.updateFromCnl) — this fake echoes the spec
/// straight back so tests stay hermetic and the set() actually resolves.
class _EchoCanvasApiClient extends canvas_client.ApiClient {
  _EchoCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<cd.ParseCnlResponse> parseCnlCanonical(String specText) async =>
      cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: const {},
          cnlText: specText,
        ),
        diagnostics: const [],
      );

  /// Canvas mutations (addNode/updateNodeParameters) push the graph back
  /// through this canonical round-trip too — echo it straight back (rather
  /// than hitting a real, unreachable backend) so hyperparameter-import
  /// tests stay hermetic and don't race canvasProvider's mirror-back logic
  /// into wiping the graph on a failed request.
  @override
  Future<cd.ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: const {},
          canvas: cd.CanvasProjection(
            nodes: graph.nodes.map(_echoCanonicalNode).toList(),
          ),
        ),
        diagnostics: const [],
      );
}

/// Converts a live [CanvasNode] into the canonical-doc's [cd.CanvasNode]
/// shape so [_EchoCanvasApiClient.canvasToCanonical] can round-trip it
/// losslessly through `canvasGraphFromCanonical` (which special-cases
/// `n_neurons`/`threshold`/`tau` from the canonical node's top-level
/// fields rather than its `parameters` map).
cd.CanvasNode _echoCanonicalNode(CanvasNode node) => cd.CanvasNode(
  id: node.id,
  label: node.label ?? node.id,
  nirType: node.nirType,
  size: (node.parameters['n_neurons'] as num?)?.toInt() ?? 1,
  threshold: (node.parameters['threshold'] as num?)?.toDouble(),
  tau: (node.parameters['tau'] as num?)?.toDouble(),
  parameters: node.parameters,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'neurocnl_server_url': 'http://localhost:8000',
    });
    await ServerConfigService.initialize();
    // Write synchronously, as _persist did before it was debounced — otherwise
    // the debounce timer is still pending when the test ends.
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
  });

  Future<ProviderContainer> pumpMenu(
    WidgetTester tester, {
    required DownloadResult result,
  }) async {
    final container = ProviderContainer(
      overrides: [
        canvas_sync.apiClientProvider.overrideWithValue(_EchoCanvasApiClient()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(specTextProvider.notifier)
        .set(
          'The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              NmtkNotificationCenter(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            appBar: AppBar(
              actions: [ExportMenu(downloadFileOverride: (_) async => result)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Export menu shows a fallback dialog without navigating away', (
    WidgetTester tester,
  ) async {
    await pumpMenu(
      tester,
      result: const DownloadResult(
        status: DownloadStatus.fallback,
        message: 'Browser blocked automatic download.',
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download .cnl').last);
    await tester.pumpAndSettle();

    expect(find.text('Desktop export requires browser assist'), findsOneWidget);
    expect(find.text('Browser blocked automatic download.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Export menu reports saved file success', (
    WidgetTester tester,
  ) async {
    await pumpMenu(
      tester,
      result: const DownloadResult(
        status: DownloadStatus.downloaded,
        path: '/tmp/spec.cnl',
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download .cnl').last);
    await tester.pump();

    expect(find.text('Saved to /tmp/spec.cnl'), findsOneWidget);
  });

  testWidgets('Export menu saves desktop exports through the native adapter', (
    WidgetTester tester,
  ) async {
    final backend = _FakeNativeFileBackend(
      saveTextFileResult: const SaveResult(
        outcome: SaveOutcome.saved,
        path: '/tmp/spec.cnl',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        nativeFileAdapterProvider.overrideWithValue(FileAdapter(backend)),
        canvas_sync.apiClientProvider.overrideWithValue(_EchoCanvasApiClient()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(specTextProvider.notifier)
        .set(
          'The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              NmtkNotificationCenter(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: ExportMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download .cnl').last);
    await tester.pumpAndSettle();

    expect(backend.lastTextSuggestedName, 'spec.cnl');
    expect(backend.lastTextContents, contains('sensory neuron'));
    expect(find.text('Saved to /tmp/spec.cnl'), findsOneWidget);
  });

  group('Import Config... braille hyperparameter mapping', () {
    const referenceJson = {
      'nb_hidden': 128,
      'alpha_r': 0.91,
      'beta_r': 0.82,
      'alpha_out': 0.93,
      'beta_out': 0.84,
      'lr': 0.002,
      'slope': 30.0,
      'reg_l1': 2e-5,
      'reg_l2': 3e-5,
    };

    Future<ProviderContainer> pumpPanelWithNodes(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(
            _EchoCanvasApiClient(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(canvasProvider.notifier);
      notifier.addNode(
        CanvasNode(
          id: 'rsyn1',
          componentId: 'cnl.RSynaptic',
          nirType: 'cnl.RSynaptic',
          parameters: const {},
          position: const [0, 0],
        ),
      );
      notifier.addNode(
        CanvasNode(
          id: 'syn1',
          componentId: 'cnl.Synaptic',
          nirType: 'cnl.Synaptic',
          parameters: const {},
          position: const [200, 0],
        ),
      );
      notifier.addPipelineDagNode(
        PipelinePhaseId.train,
        const PipelineDagNode(
          id: 'adam1',
          type: PipelineDagNodeType.adamOptimiser,
        ),
      );
      notifier.addPipelineDagNode(
        PipelinePhaseId.train,
        const PipelineDagNode(
          id: 'surr1',
          type: PipelineDagNodeType.surrogateBackward,
        ),
      );
      notifier.addPipelineDagNode(
        PipelinePhaseId.train,
        const PipelineDagNode(id: 'l1_1', type: PipelineDagNodeType.l1SpikeReg),
      );
      notifier.addPipelineDagNode(
        PipelinePhaseId.train,
        const PipelineDagNode(id: 'l2_1', type: PipelineDagNodeType.l2SpikeReg),
      );

      final gateway = _FakeFilePickerGateway([
        PickedFileData(
          name: 'braille_config.json',
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(referenceJson))),
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                NmtkNotificationCenter(child: child ?? const SizedBox.shrink()),
            home: Scaffold(
              body: NeurocnlExportWorkspacePanel(
                filePickerGatewayOverride: gateway,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets(
      'applies the 9 mapped hyperparameters to the architecture graph and '
      'training DAG, and surfaces applied/skipped counts',
      (tester) async {
        final container = await pumpPanelWithNodes(tester);

        await tester.tap(find.text('Import Config...'));
        await tester.pumpAndSettle();

        final state = container.read(canvasProvider);
        final rsyn = state.graph.nodes.firstWhere((n) => n.id == 'rsyn1');
        final syn = state.graph.nodes.firstWhere((n) => n.id == 'syn1');
        expect(rsyn.parameters['n_neurons'], 128);
        expect(rsyn.parameters['alpha'], 0.91);
        expect(rsyn.parameters['beta'], 0.82);
        expect(syn.parameters['alpha'], 0.93);
        expect(syn.parameters['beta'], 0.84);

        final trainNodes = state.pipelinePhases.train.nodes;
        final adam = trainNodes.firstWhere((n) => n.id == 'adam1');
        final surr = trainNodes.firstWhere((n) => n.id == 'surr1');
        final l1 = trainNodes.firstWhere((n) => n.id == 'l1_1');
        final l2 = trainNodes.firstWhere((n) => n.id == 'l2_1');
        expect(adam.parameters['lr'], 0.002);
        expect(surr.parameters['slope'], 30.0);
        expect(l1.parameters['weight'], 2e-5);
        expect(l2.parameters['weight'], 3e-5);

        // Applied/skipped summary surfaces via the snackbar...
        expect(
          find.textContaining('9 hyperparameters applied'),
          findsOneWidget,
        );

        // ...and via the Recent Activity log.
        final activities = container.read(workspaceProvider).recentActivities;
        expect(
          activities.any(
            (a) =>
                a.kind == 'import' &&
                a.detail.contains('nb_hidden -> cnl.RSynaptic.n_neurons'),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'reports skipped keys when a required node type is missing, without '
      'crashing and without clobbering the keys that did apply',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            canvas_sync.apiClientProvider.overrideWithValue(
              _EchoCanvasApiClient(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final gateway = _FakeFilePickerGateway([
          PickedFileData(
            name: 'braille_config.json',
            bytes: Uint8List.fromList(utf8.encode(jsonEncode(referenceJson))),
          ),
        ]);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => NmtkNotificationCenter(
                child: child ?? const SizedBox.shrink(),
              ),
              home: Scaffold(
                body: NeurocnlExportWorkspacePanel(
                  filePickerGatewayOverride: gateway,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Force a genuinely empty architecture graph (and no train DAG
        // nodes) for this container regardless of whatever a prior test's
        // workspace/canonical-doc round trip may have seeded — this test's
        // whole point is exercising the "no matching node at all" path.
        container.read(canvasProvider.notifier).resetGraph();
        await tester.pumpAndSettle();
        expect(container.read(canvasProvider).graph.nodes, isEmpty);
        expect(
          container.read(canvasProvider).pipelinePhases.train.nodes,
          isEmpty,
        );

        await tester.tap(find.text('Import Config...'));
        await tester.pumpAndSettle();

        expect(find.textContaining('9 skipped'), findsOneWidget);

        final state = container.read(canvasProvider);
        expect(state.graph.nodes, isEmpty);
        expect(state.pipelinePhases.train.nodes, isEmpty);
      },
    );
  });
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
