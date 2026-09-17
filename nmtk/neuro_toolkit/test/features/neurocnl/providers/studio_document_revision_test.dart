import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    as canonical;
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import '../providers_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  test(
    'switching files hydrates pipeline state from the active document',
    () async {
      SharedPreferences.setMockInitialValues({});
      ServerConfigService.debugResetForTests();
      await ServerConfigService.initialize();

      final mockApi = MockApiClient();
      when(
        mockApi.ensureWorkspace(workspacePath: anyNamed('workspacePath')),
      ).thenAnswer((_) async => '/tmp/ws');
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
      addTearDown(container.dispose);

      const parseResultA = ParseResult(sentences: [], total: 0, errors: 0);
      const validateResultA = ValidationResult(
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
      const parseResultB = ParseResult(sentences: [], total: 0, errors: 1);
      const validateResultB = ValidationResult(
        layer1: Layer1Result(overall: false, passed: [], failed: []),
        layer2: Layer2Result(
          overall: false,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: false,
        backendSupport: BackendSupportResult(
          backend: 'nir',
          verdict: 'unsupported',
        ),
      );

      when(mockApi.parse('spec a')).thenAnswer((_) async => parseResultA);
      when(
        mockApi.validate(
          'spec a',
          params: anyNamed('params'),
          backend: anyNamed('backend'),
        ),
      ).thenAnswer((_) async => validateResultA);
      when(mockApi.parse('spec b')).thenAnswer((_) async => parseResultB);
      when(
        mockApi.validate(
          'spec b',
          params: anyNamed('params'),
          backend: anyNamed('backend'),
        ),
      ).thenAnswer((_) async => validateResultB);

      final workspace = container.read(workspaceProvider.notifier);
      workspace.setActiveFileCanonicalDocument(
        const canonical.CanonicalEditorDocument(
          irJson: <String, dynamic>{},
          cnlText: 'spec a',
        ),
      );
      final fileAId = container.read(workspaceProvider).activeFileId;
      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate('spec a');

      workspace.createUntitledFile();
      workspace.setActiveFileCanonicalDocument(
        const canonical.CanonicalEditorDocument(
          irJson: <String, dynamic>{},
          cnlText: 'spec b',
        ),
      );
      final fileBId = container.read(workspaceProvider).activeFileId;
      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate('spec b');

      workspace.setActiveFile(fileAId);
      final fileAState = container.read(pipelineProvider);
      expect(fileAState.parseResult?.errors, 0);
      expect(fileAState.validateResult?.overall, isTrue);

      workspace.setActiveFile(fileBId);
      final fileBState = container.read(pipelineProvider);
      expect(fileBState.parseResult?.errors, 1);
      expect(fileBState.validateResult?.overall, isFalse);
    },
  );

  test(
    'stale parse result does not overwrite newer document revision',
    () async {
      SharedPreferences.setMockInitialValues({});
      ServerConfigService.debugResetForTests();
      await ServerConfigService.initialize();

      final mockApi = MockApiClient();
      when(
        mockApi.ensureWorkspace(workspacePath: anyNamed('workspacePath')),
      ).thenAnswer((_) async => '/tmp/ws');
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(mockApi)],
      );
      addTearDown(container.dispose);

      final oldParseCompleter = Completer<ParseResult>();
      const oldParseResult = ParseResult(sentences: [], total: 0, errors: 0);
      const newParseResult = ParseResult(sentences: [], total: 0, errors: 1);
      const newValidateResult = ValidationResult(
        layer1: Layer1Result(overall: false, passed: [], failed: []),
        layer2: Layer2Result(
          overall: false,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: false,
        backendSupport: BackendSupportResult(
          backend: 'nir',
          verdict: 'unsupported',
        ),
      );

      when(mockApi.parse('old')).thenAnswer((_) => oldParseCompleter.future);
      when(mockApi.parse('new')).thenAnswer((_) async => newParseResult);
      when(
        mockApi.validate(
          'new',
          params: anyNamed('params'),
          backend: anyNamed('backend'),
        ),
      ).thenAnswer((_) async => newValidateResult);

      final workspace = container.read(workspaceProvider.notifier);
      workspace.setActiveFileCanonicalDocument(
        const canonical.CanonicalEditorDocument(
          irJson: <String, dynamic>{},
          cnlText: 'old',
        ),
      );
      final oldRevision = container
          .read(workspaceProvider)
          .activeFile!
          .revision;

      final oldFuture = container
          .read(pipelineProvider.notifier)
          .runParseAndValidate('old');

      workspace.setActiveFileCanonicalDocument(
        const canonical.CanonicalEditorDocument(
          irJson: <String, dynamic>{},
          cnlText: 'new',
        ),
      );
      final newRevision = container
          .read(workspaceProvider)
          .activeFile!
          .revision;
      expect(newRevision, greaterThan(oldRevision));

      await container
          .read(pipelineProvider.notifier)
          .runParseAndValidate('new');

      oldParseCompleter.complete(oldParseResult);
      await oldFuture;

      final activeFile = container.read(workspaceProvider).activeFile!;
      expect(activeFile.canonicalDocument?.cnlText, 'new');
      expect(activeFile.revision, newRevision);
      expect(activeFile.pipelineState!.parseResult?.errors, 1);
      expect(activeFile.pipelineState!.validateResult?.overall, isFalse);
      verifyNever(
        mockApi.validate(
          'old',
          params: anyNamed('params'),
          backend: anyNamed('backend'),
        ),
      );
    },
  );

  // 'stale canvas sync does not overwrite newer document revision' was
  // deleted: it exercised StudioSyncNotifier.syncCnlToCanvas from the old
  // studio_sync_notifier.dart reconciler, which no longer exists — CNL/canvas
  // sync is now unified inside CanonicalDocController.updateFromCnl, which
  // uses the same generation-counter staleness guard. That guard is already
  // covered for the unified path by
  // test/providers/canonical_doc_provider_test.dart
  // ("canonicalDocProvider — generation counter (supersession)").
}
