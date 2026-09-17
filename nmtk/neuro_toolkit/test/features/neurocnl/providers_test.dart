import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart' as cd;
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart' as canvas_api;
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import 'providers_test.mocks.dart';

class _FakeCanonicalApi extends canvas_api.ApiClient {
  _FakeCanonicalApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<cd.ParseCnlResponse> parseCnlCanonical(String specText) async =>
      cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: const {},
          cnlText: specText,
        ),
        diagnostics: const [],
      );
}

/// Trivial in-memory stand-in for the plain [ApiClient] so the reactive
/// `runParseAndValidate` side effect that [CanonicalDocController] fires
/// after every document publish resolves instantly instead of attempting a
/// real network call (and outliving `ProviderContainer.dispose()` in tests
/// that don't care about parse/validate outcomes).
class _FakeWorkspaceApi extends ApiClient {
  _FakeWorkspaceApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseResult> parse(String spec) async =>
      const ParseResult(sentences: [], total: 0, errors: 0);

  @override
  Future<ValidationResult> validate(
    String spec, {
    Map<String, dynamic>? params,
    String backend = 'nir',
  }) async => const ValidationResult(
    layer1: Layer1Result(overall: true, passed: [], failed: []),
    layer2: Layer2Result(
      overall: true,
      checksPassed: [],
      checksFailed: [],
      neuronsFound: [],
    ),
    overall: true,
  );
}

@GenerateMocks([ApiClient])
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
    // Write synchronously, as _persist did before it was debounced — otherwise
    // the debounce timer is still pending when the test ends.
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
  });

  group('SpecTextController', () {
    test('initial state is empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(specTextProvider), '');
    });

    test('set updates state immediately', () async {
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(_FakeCanonicalApi()),
          apiClientProvider.overrideWithValue(_FakeWorkspaceApi()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(specTextProvider.notifier).set('new spec');
      expect(container.read(specTextProvider), 'new spec');
      // `set` triggers a fire-and-forget runParseAndValidate (parse+validate
      // stages) via CanonicalDocController._publishDocument; let it fully
      // settle before the container is disposed by addTearDown.
      await pumpEventQueue();
    });

    test('update writes state', () async {
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(_FakeCanonicalApi()),
          apiClientProvider.overrideWithValue(_FakeWorkspaceApi()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(specTextProvider.notifier).update('updated spec');

      expect(container.read(specTextProvider), 'updated spec');
    });
  });

  group('PipelineController', () {
    late MockApiClient mockApi;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ServerConfigService.debugResetForTests();
      await ServerConfigService.initialize();

      mockApi = MockApiClient();
      when(
        mockApi.ensureWorkspace(workspacePath: anyNamed('workspacePath')),
      ).thenAnswer((_) async => '/tmp/ws');
      container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is idle', () {
      final state = container.read(pipelineProvider);
      expect(state.parseStatus, StepStatus.idle);
      expect(state.validateStatus, StepStatus.idle);
    });

    test('runParseAndValidate updates state correctly on success', () async {
      const parseResult = ParseResult(sentences: [], total: 0, errors: 0);
      const validateResult = ValidationResult(
        layer1: Layer1Result(overall: true, passed: [], failed: []),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: true,
        backendSupport: BackendSupportResult(
          backend: 'nengo',
          verdict: 'faithful',
        ),
      );

      when(mockApi.parse(any)).thenAnswer((_) async => parseResult);
      when(
        mockApi.validate(
          any,
          params: anyNamed('params'),
          backend: anyNamed('backend'),
        ),
      ).thenAnswer((_) async => validateResult);

      final notifier = container.read(pipelineProvider.notifier);
      final future = notifier.runParseAndValidate('test spec');

      // Check running state
      expect(container.read(pipelineProvider).parseStatus, StepStatus.running);

      await future;

      final state = container.read(pipelineProvider);
      expect(state.parseStatus, StepStatus.success);
      expect(state.validateStatus, StepStatus.success);
      expect(state.parseResult, parseResult);
      expect(state.validateResult, validateResult);
    });

    test(
      'runParseAndValidate writes results to the active workspace document',
      () async {
        const parseResult = ParseResult(sentences: [], total: 0, errors: 0);
        const validateResult = ValidationResult(
          layer1: Layer1Result(overall: true, passed: [], failed: []),
          layer2: Layer2Result(
            overall: true,
            checksPassed: [],
            checksFailed: [],
            neuronsFound: [],
          ),
          overall: true,
          backendSupport: BackendSupportResult(
            backend: 'nir',
            verdict: 'approximate',
          ),
        );

        when(mockApi.parse(any)).thenAnswer((_) async => parseResult);
        when(
          mockApi.validate(
            any,
            params: anyNamed('params'),
            backend: anyNamed('backend'),
          ),
        ).thenAnswer((_) async => validateResult);

        await container
            .read(pipelineProvider.notifier)
            .runParseAndValidate('test spec');

        final activeFile = container.read(workspaceProvider).activeFile!;
        expect(activeFile.pipelineState, isNotNull);
        expect(activeFile.pipelineState!.parseResult, parseResult);
        expect(activeFile.pipelineState!.validateResult?.overall, isTrue);
      },
    );

    test('initialization restores cached backend support payload', () async {
      const validateResult = ValidationResult(
        layer1: Layer1Result(overall: true, passed: [], failed: []),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: true,
        backendSupport: BackendSupportResult(
          backend: 'loihi',
          verdict: 'approximate',
          warnings: [
            'Declared network_timestep differs from backend timing resolution.',
          ],
        ),
      );

      await ServerConfigService.setString(
        'cached_validate_result',
        jsonEncode(validateResult.toJson()),
      );

      final restoredContainer = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
      addTearDown(restoredContainer.dispose);

      final state = restoredContainer.read(pipelineProvider);
      expect(state.validateResult, isNotNull);
      expect(state.validateResult!.backendSupport, isNotNull);
      expect(state.validateResult!.backendSupport!.backend, 'loihi');
      expect(state.validateResult!.backendSupport!.verdict, 'approximate');
    });

    test(
      'runGenerateAndSimulate marks preview ready from generate output',
      () async {
        const generateResult = GenerateResult(
          network: NetworkGraph(nodes: [], edges: []),
          cnlDocument: 'round-trip cnl',
          nirCode: 'nir',
        );

        when(mockApi.generate(any)).thenAnswer((_) async => generateResult);
        when(mockApi.simulate(any, duration: anyNamed('duration'))).thenAnswer(
          (_) async => const SimulationResult(
            duration: 1.0,
            dt: 0.001,
            timesteps: 1000,
            wallTimeSeconds: 0.1,
            probes: {},
            summary: SimulationSummary(
              sensorySpikeCount: 0,
              motorSpikeCount: 0,
              sensoryMeanRate: 0,
              motorMeanRate: 0,
            ),
          ),
        );

        final notifier = container.read(pipelineProvider.notifier);
        final future = notifier.runGenerateAndSimulate('test spec');

        expect(
          container.read(pipelineProvider).generateStatus,
          StepStatus.running,
        );

        await future;

        final state = container.read(pipelineProvider);
        expect(state.generateStatus, StepStatus.success);
        expect(state.simulateStatus, StepStatus.success);
        expect(state.generateResult, generateResult);
        expect(state.simulateResult, isNotNull);
      },
    );

    test(
      'runGenerateAndSimulate stores generate-backed preview cache',
      () async {
        const generateResult = GenerateResult(
          network: NetworkGraph(nodes: [], edges: []),
          cnlDocument: 'round-trip cnl',
          nirCode: 'nir',
        );
        container
            .read(canonicalDocProvider.notifier)
            .setDocument(
              const cd.CanonicalEditorDocument(
                irJson: {},
                cnlText: 'test spec',
              ),
            );
        when(mockApi.generate(any)).thenAnswer((_) async => generateResult);
        when(mockApi.simulate(any, duration: anyNamed('duration'))).thenAnswer(
          (_) async => const SimulationResult(
            duration: 1.0,
            dt: 0.001,
            timesteps: 1000,
            wallTimeSeconds: 0.1,
            probes: {},
            summary: SimulationSummary(
              sensorySpikeCount: 0,
              motorSpikeCount: 0,
              sensoryMeanRate: 0,
              motorMeanRate: 0,
            ),
          ),
        );

        await container
            .read(pipelineProvider.notifier)
            .runGenerateAndSimulate('test spec');

        final cache = container
            .read(workspaceProvider)
            .activeFile
            ?.pipelineCache;
        expect(cache, isNotNull);
        expect(cache!.isValidForContent('test spec'), isTrue);
        expect(cache.generateResult.nirCode, 'nir');
        expect(cache.simulationResult, isNotNull);
      },
    );

    test('hydrateCachedResultsForFile restores valid cached results', () {
      const generateResult = GenerateResult(
        network: NetworkGraph(nodes: [], edges: []),
        cnlDocument: 'round-trip cnl',
        nirCode: 'nir',
      );
      const simulateResult = SimulationResult(
        duration: 1.0,
        dt: 0.001,
        timesteps: 1000,
        wallTimeSeconds: 0.1,
        probes: {},
        summary: SimulationSummary(
          sensorySpikeCount: 0,
          motorSpikeCount: 0,
          sensoryMeanRate: 0,
          motorMeanRate: 0,
        ),
      );
      const content = 'cached spec';
      final file = WorkspaceFile(
        id: 'cached',
        name: 'Cached.cnl',
        canonicalDocument: const cd.CanonicalEditorDocument(
          irJson: {},
          cnlText: content,
        ),
        pipelineCache: WorkspacePipelineCache(
          sourceHash: WorkspacePipelineCache.sourceHashFor(content),
          generatedAt: '2026-05-11T12:00:00.000',
          simulatedAt: '2026-05-11T12:00:01.000',
          generateResult: generateResult,
          simulationResult: simulateResult,
        ),
      );

      container
          .read(pipelineProvider.notifier)
          .hydrateCachedResultsForFile(file);

      final state = container.read(pipelineProvider);
      expect(state.generateStatus, StepStatus.success);
      expect(state.simulateStatus, StepStatus.success);
      expect(state.generateResult?.cnlDocument, 'round-trip cnl');
      expect(state.simulateResult?.duration, 1.0);
    });

    test('hydrateCachedResultsForFile ignores stale cached results', () {
      const generateResult = GenerateResult(
        network: NetworkGraph(nodes: [], edges: []),
        cnlDocument: 'round-trip cnl',
        nirCode: 'nir',
      );
      final file = WorkspaceFile(
        id: 'stale',
        name: 'Stale.cnl',
        canonicalDocument: const cd.CanonicalEditorDocument(
          irJson: {},
          cnlText: 'edited spec',
        ),
        pipelineCache: WorkspacePipelineCache(
          sourceHash: WorkspacePipelineCache.sourceHashFor('old spec'),
          generatedAt: '2026-05-11T12:00:00.000',
          generateResult: generateResult,
        ),
      );

      container
          .read(pipelineProvider.notifier)
          .hydrateCachedResultsForFile(file);

      final state = container.read(pipelineProvider);
      expect(state.generateStatus, StepStatus.idle);
      expect(state.simulateStatus, StepStatus.idle);
      expect(state.generateResult, isNull);
      expect(state.simulateResult, isNull);
    });

    test('runGenerateAndSimulate sets error state if generate fails', () async {
      when(mockApi.generate(any)).thenThrow(Exception('Generate Error'));

      final notifier = container.read(pipelineProvider.notifier);
      await notifier.runGenerateAndSimulate('test spec');

      final state = container.read(pipelineProvider);
      expect(state.generateStatus, StepStatus.error);
      expect(state.errorMessage, contains('Generate failed'));
    });

    test('reset clears state correctly', () async {
      final notifier = container.read(pipelineProvider.notifier);

      // Manually set some state (simplest via a successful run or just checking default is same)
      // Here we just check it returns to initial.
      notifier.reset();

      final state = container.read(pipelineProvider);
      expect(state.parseStatus, StepStatus.idle);
      expect(state.validateStatus, StepStatus.idle);
      expect(state.generateStatus, StepStatus.idle);
      expect(state.simulateStatus, StepStatus.idle);
      expect(state.parseResult, isNull);
    });

    test('runParseAndValidate sets error state if parse fails', () async {
      when(mockApi.parse(any)).thenThrow(Exception('API Error'));

      final notifier = container.read(pipelineProvider.notifier);
      await notifier.runParseAndValidate('test spec');

      final state = container.read(pipelineProvider);
      expect(state.parseStatus, StepStatus.error);
      expect(state.errorMessage, contains('Parse failed'));
    });
  });

  group('WorkspaceController', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ServerConfigService.debugResetForTests();
      await ServerConfigService.initialize();
    });

    test('legacy cached spec becomes one untitled file', () async {
      await ServerConfigService.setString('cached_spec_text', 'legacy spec');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(workspaceProvider);
      expect(state.files, hasLength(1));
      expect(state.activeFile?.name, 'Untitled 1');
      expect(state.activeFile?.isUntitled, isTrue);
    });

    test(
      'restore payload hydrates workspace and deep link overrides panel and focus',
      () {
        final container = ProviderContainer(
          overrides: [
            workspaceBootstrapProvider.overrideWithValue(
              const WorkspaceBootstrap(
                initialLocation:
                    '/?panel=validation&validation=layer2:missing-neuron',
                initialRestoreState: <String, Object?>{
                  'workspace': <String, Object?>{
                    'files': <Map<String, Object?>>[
                      <String, Object?>{
                        'id': 'file-a',
                        'name': 'A.cnl',
                        'content': 'alpha',
                        'dirty': false,
                        'isUntitled': false,
                        'cursorOffset': 1,
                        'selectionBase': 1,
                        'selectionExtent': 1,
                        'scrollOffset': 4.0,
                      },
                      <String, Object?>{
                        'id': 'file-b',
                        'name': 'B.cnl',
                        'content': 'beta',
                        'dirty': true,
                        'isUntitled': false,
                        'cursorOffset': 2,
                        'selectionBase': 2,
                        'selectionExtent': 2,
                        'scrollOffset': 8.0,
                      },
                    ],
                    'activeFileId': 'file-b',
                    'activePanel': 'network',
                    'validationFocus': <String, Object?>{
                      'section': 'layer1',
                      'itemId': 'old-item',
                    },
                    'splitRatio': 0.63,
                  },
                },
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final state = container.read(workspaceProvider);
        expect(state.activeFileId, 'file-b');
        expect(state.activePanel, 'validation');
        expect(state.validationFocus?.section, 'layer2');
        expect(state.validationFocus?.itemId, 'missing-neuron');
        expect(state.splitRatio, 0.63);
      },
    );

    test('deploy deep link selects deploy panel and pipeline step', () {
      final container = ProviderContainer(
        overrides: [
          workspaceBootstrapProvider.overrideWithValue(
            const WorkspaceBootstrap(
              initialLocation: '/?panel=deploy&target=akida',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(workspaceProvider);
      expect(state.activePanel, 'deploy');
      expect(state.activePipelineStep, 'deployHardware');
      expect(state.selectedDeployTarget, 'akida');
    });

    test(
      'legacy flat cached WorkspaceState (pre-canvas-section format) still restores',
      () async {
        await ServerConfigService.setString(
          WorkspaceController.workspaceStorageKey,
          jsonEncode(<String, Object?>{
            'activeFileId': 'legacy-file',
            'files': <Map<String, Object?>>[
              <String, Object?>{'id': 'legacy-file'},
            ],
          }),
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(workspaceProvider.notifier);
        expect(notifier.hasPendingWorkspaceResume, isTrue);
        notifier.resumeCachedWorkspace();

        final state = container.read(workspaceProvider);
        expect(state.activeFileId, 'legacy-file');
        expect(notifier.consumePendingCanvasRestorePayload(), isNull);
      },
    );

    test('cold resume exposes only the compact result snapshot', () async {
      final cached = <String, Object?>{
        'version': 1,
        'workspace': <String, Object?>{
          'activeFileId': 'file-a',
          'files': <Map<String, Object?>>[
            <String, Object?>{'id': 'file-a'},
          ],
        },
        'resultSnapshot': <String, Object?>{
          'schemaVersion': 1,
          'id': 'snapshot-1',
          'completedAt': '2026-08-10T12:00:00.000Z',
          'provenance': <String, Object?>{
            'workspaceName': 'Cached',
            'modelFingerprint': 'model-a',
          },
          'platforms': <String, Object?>{},
          'selection': <String, Object?>{'view': 'architecture'},
          'isPartial': false,
        },
        'canvas': <String, Object?>{
          'simulationResults': <String, Object?>{
            'status': 'large-buffer-must-not-restore',
          },
        },
      };
      await ServerConfigService.setString(
        WorkspaceController.workspaceStorageKey,
        jsonEncode(cached),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(workspaceProvider.notifier);
      container.read(workspaceProvider);

      expect(notifier.consumePendingResultRestorePayload(), isNull);
      notifier.resumeCachedWorkspace();
      final result = notifier.consumePendingResultRestorePayload();
      expect((result!['resultSnapshot'] as Map)['id'], 'snapshot-1');
      expect(notifier.consumePendingCanvasRestorePayload(), isNull);
    });

    test(
      'legacy cached canvas history is offered as a result migration',
      () async {
        await ServerConfigService.setString(
          WorkspaceController.workspaceStorageKey,
          jsonEncode(<String, Object?>{
            'workspace': <String, Object?>{
              'activeFileId': 'file-a',
              'files': <Map<String, Object?>>[
                <String, Object?>{'id': 'file-a'},
              ],
            },
            'canvas': <String, Object?>{
              'trainingHistory': <String, Object?>{
                'lava_sim': <Object?>[
                  <String, Object?>{'epoch': 1, 'loss': 0.1},
                ],
              },
            },
          }),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(workspaceProvider.notifier);
        container.read(workspaceProvider);
        notifier.resumeCachedWorkspace();

        final result = notifier.consumePendingResultRestorePayload();
        expect(
          (result!['legacyTrainingHistory'] as Map).containsKey('lava_sim'),
          isTrue,
        );
        expect(notifier.consumePendingCanvasRestorePayload(), isNull);
      },
    );

    test(
      'cached canvas section is exposed via consumePendingCanvasRestorePayload '
      'and survives a later workspace-only persist',
      () async {
        final initialState = <String, Object?>{
          'version': 1,
          'workspace': <String, Object?>{},
          'canvas': <String, Object?>{
            'pipeline': <String, Object?>{'foo': 'bar'},
            'pipelinePhases': <String, Object?>{'baz': 'qux'},
          },
        };
        await ServerConfigService.setString(
          WorkspaceController.workspaceStorageKey,
          jsonEncode(initialState),
        );

        final container = ProviderContainer(
          overrides: [
            workspaceBootstrapProvider.overrideWithValue(
              WorkspaceBootstrap(initialRestoreState: initialState),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Triggers build()/_buildInitialState(), which must stash the
        // cached 'canvas' section for the studio screen's startup hook.
        container.read(workspaceProvider);

        final canvasPayload = container
            .read(workspaceProvider.notifier)
            .consumePendingCanvasRestorePayload();
        expect(canvasPayload, isNotNull);
        expect((canvasPayload!['canvas'] as Map)['pipeline'], <String, Object?>{
          'foo': 'bar',
        });

        // Consumed exactly once.
        expect(
          container
              .read(workspaceProvider.notifier)
              .consumePendingCanvasRestorePayload(),
          isNull,
        );

        // A workspace-only mutation (e.g. recordActivity) re-persists via
        // _persist(); it must preserve the 'canvas' section already on
        // disk rather than clobbering it with a canvas-less blob.
        container
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'export',
              title: 'export',
              detail: 'detail',
              status: 'success',
            );
        await pumpEventQueue();

        final persisted =
            jsonDecode(
                  ServerConfigService.getString(
                    WorkspaceController.workspaceStorageKey,
                  )!,
                )
                as Map<String, dynamic>;
        expect((persisted['canvas'] as Map)['pipeline'], <String, Object?>{
          'foo': 'bar',
        });
      },
    );

    test('workspaceFilePath threads through replaceFromWorkspacePayload and '
        'clears when explicitly passed null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(workspaceProvider.notifier)
          .replaceFromWorkspacePayload(
            <String, Object?>{
              'workspace': <String, Object?>{'files': <Object?>[]},
            },
            sourceFileName: 'session.nmtk',
            sourceFilePath: '/tmp/session.nmtk',
          );
      expect(
        container.read(workspaceProvider).workspaceFilePath,
        '/tmp/session.nmtk',
      );

      // A Hub asset has no local file — must explicitly clear a
      // previously-recorded path rather than leaving it stale.
      container.read(workspaceProvider.notifier).replaceFromWorkspacePayload(
        <String, Object?>{
          'workspace': <String, Object?>{'files': <Object?>[]},
        },
        sourceFileName: 'hub-asset',
      );
      expect(container.read(workspaceProvider).workspaceFilePath, isNull);
    });

    test('autosave writes through to the recorded workspace file path, in '
        'addition to the local-storage cache', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'workspace_provider_test',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final path = '${tempDir.path}/session.nmtk';

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(workspaceProvider.notifier).recordWorkspaceFilePath(path);
      container
          .read(workspaceProvider.notifier)
          .recordActivity(
            kind: 'export',
            title: 'export',
            detail: 'detail',
            status: 'success',
          );

      await pumpEventQueue();

      expect(File(path).existsSync(), isTrue);
      final decoded =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(decoded['workspace'], isNotNull);

      // The local-storage cache must still be written too — file
      // write-through is additive, not a replacement.
      expect(
        ServerConfigService.getString(WorkspaceController.workspaceStorageKey),
        isNotNull,
      );
    });

    test('autosave file write-through is a silent no-op when no file has been '
        'opened or saved yet (never-saved workspace)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(workspaceProvider).workspaceFilePath, isNull);

      // Must not throw even with no path recorded.
      container
          .read(workspaceProvider.notifier)
          .recordActivity(
            kind: 'export',
            title: 'export',
            detail: 'detail',
            status: 'success',
          );
      await pumpEventQueue();

      expect(container.read(workspaceProvider).workspaceFilePath, isNull);
    });

    test('recordActivity persists recent desktop export history', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(workspaceProvider.notifier)
          .recordActivity(
            kind: 'export',
            title: 'CNL export',
            detail: 'Saved to /tmp/spec.cnl',
            status: 'success',
            panelId: 'artifacts',
          );

      final state = container.read(workspaceProvider);
      expect(state.recentActivities, hasLength(1));
      expect(state.recentActivities.first.title, 'CNL export');
      expect(state.recentActivities.first.panelId, 'artifacts');
    });

    // 'importFiles preserves order and activates the last imported file' was
    // deleted: WorkspaceController.importFiles was removed as confirmed dead
    // code (zero real callers) during the sync-architecture refactor.

    test(
      'markActiveFileSavedAs records path, name, and clears dirty state',
      () async {
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(_FakeWorkspaceApi())],
        );
        addTearDown(container.dispose);
        container
            .read(canonicalDocProvider.notifier)
            .setDocument(
              const cd.CanonicalEditorDocument(
                irJson: {},
                cnlText: 'changed spec',
              ),
            );
        // setDocument fires a fire-and-forget runParseAndValidate against the
        // real (unmocked) apiClientProvider; let it fail and settle before
        // the container is disposed so it doesn't throw post-dispose.
        await pumpEventQueue();

        container
            .read(workspaceProvider.notifier)
            .markActiveFileSavedAs(name: 'Saved.cnl', path: '/tmp/Saved.cnl');

        final activeFile = container.read(workspaceProvider).activeFile;
        expect(activeFile?.name, 'Saved.cnl');
        expect(activeFile?.path, '/tmp/Saved.cnl');
        expect(activeFile?.dirty, isFalse);
        expect(activeFile?.isUntitled, isFalse);
      },
    );

    test('replaceFromWorkspacePayload hydrates existing restore shape', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(workspaceProvider.notifier).replaceFromWorkspacePayload(
        const <String, Object?>{
          'version': 1,
          'workspace': <String, Object?>{
            'files': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'file-a',
                'name': 'A.cnl',
                'path': '/tmp/A.cnl',
                'content': 'alpha',
                'dirty': false,
                'isUntitled': false,
              },
            ],
            'activeFileId': 'file-a',
            'activePanel': 'validation',
          },
        },
      );

      final state = container.read(workspaceProvider);
      expect(state.files, hasLength(1));
      expect(state.activeFile?.name, 'A.cnl');
      expect(state.activeFile?.path, '/tmp/A.cnl');
      expect(state.activePanel, 'validation');
    });

    test(
      'replaceFromWorkspacePayload rejects payloads without workspace object',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          () => container
              .read(workspaceProvider.notifier)
              .replaceFromWorkspacePayload(const <String, Object?>{}),
          throwsFormatException,
        );
      },
    );

    test(
      'savePipelineCacheForActiveFile stores generated preview data',
      () async {
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(_FakeWorkspaceApi())],
        );
        addTearDown(container.dispose);
        container
            .read(canonicalDocProvider.notifier)
            .setDocument(
              const cd.CanonicalEditorDocument(
                irJson: {},
                cnlText: 'cacheable spec',
              ),
            );
        // setDocument fires a fire-and-forget runParseAndValidate against the
        // real (unmocked) apiClientProvider; let it settle before disposing.
        await pumpEventQueue();

        container
            .read(workspaceProvider.notifier)
            .savePipelineCacheForActiveFile(
              generateResult: const GenerateResult(
                network: NetworkGraph(
                  nodes: <NetworkNode>[],
                  edges: <NetworkEdge>[],
                ),
                cnlDocument: 'round-trip cnl',
                nirCode: 'nir code',
              ),
            );

        final cache = container
            .read(workspaceProvider)
            .activeFile
            ?.pipelineCache;
        expect(cache, isNotNull);
        expect(cache!.isValidForContent('cacheable spec'), isTrue);
        expect(cache.generateResult.cnlDocument, 'round-trip cnl');
        expect(cache.simulationResult, isNull);
      },
    );

    test(
      'saveNirArtifactForActiveFile stores a content-scoped cached artifact',
      () async {
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(_FakeWorkspaceApi())],
        );
        addTearDown(container.dispose);
        container
            .read(canonicalDocProvider.notifier)
            .setDocument(
              const cd.CanonicalEditorDocument(
                irJson: {},
                cnlText: 'cacheable spec',
              ),
            );
        // setDocument fires a fire-and-forget runParseAndValidate against the
        // real (unmocked) apiClientProvider; let it settle before disposing.
        await pumpEventQueue();

        container
            .read(workspaceProvider.notifier)
            .saveNirArtifactForActiveFile(
              ExportArtifact.binary(
                filename: 'network.nir',
                mimeType: 'application/octet-stream',
                payload: Uint8List.fromList(const <int>[0x89, 0x48]),
              ),
            );

        expect(
          container.read(workspaceProvider).activeFile?.pipelineCache,
          isNull,
        );
        final artifactCache = container
            .read(workspaceProvider)
            .activeFile
            ?.nirArtifactCache;
        expect(artifactCache, isNotNull);
        expect(artifactCache!.filename, 'network.nir');
        expect(artifactCache.isValidForContent('cacheable spec'), isTrue);
        expect(artifactCache.payloadBytes, <int>[0x89, 0x48]);
      },
    );

    test('editing active file clears cached pipeline results', () async {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_FakeWorkspaceApi())],
      );
      addTearDown(container.dispose);
      container
          .read(canonicalDocProvider.notifier)
          .setDocument(
            const cd.CanonicalEditorDocument(
              irJson: {},
              cnlText: 'cacheable spec',
            ),
          );
      // setDocument fires a fire-and-forget runParseAndValidate against the
      // real (unmocked) apiClientProvider; let it settle before disposing.
      await pumpEventQueue();
      container
          .read(workspaceProvider.notifier)
          .savePipelineCacheForActiveFile(
            generateResult: const GenerateResult(
              network: NetworkGraph(
                nodes: <NetworkNode>[],
                edges: <NetworkEdge>[],
              ),
              cnlDocument: 'round-trip cnl',
              nirCode: 'nir code',
            ),
          );
      container
          .read(workspaceProvider.notifier)
          .saveNirArtifactForActiveFile(
            ExportArtifact.binary(
              filename: 'network.nir',
              mimeType: 'application/octet-stream',
              payload: Uint8List.fromList(const <int>[0x89, 0x48]),
            ),
          );

      container
          .read(canonicalDocProvider.notifier)
          .setDocument(
            const cd.CanonicalEditorDocument(
              irJson: {},
              cnlText: 'edited spec',
            ),
          );
      await pumpEventQueue();

      expect(
        container.read(workspaceProvider).activeFile?.pipelineCache,
        isNull,
      );
      expect(
        container.read(workspaceProvider).activeFile?.nirArtifactCache,
        isNull,
      );
    });
  });
}
