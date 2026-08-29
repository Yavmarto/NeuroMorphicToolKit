import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart' as cd;
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart' as pipeline_api;
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart' as pipeline_client;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

class _FakeCanonicalApi extends ApiClient {
  _FakeCanonicalApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<cd.ParseCnlResponse> parseCnlCanonical(String specText) async =>
      cd.ParseCnlResponse(
        document: cd.CanonicalEditorDocument(
          irJson: const {},
          cnlText: specText,
          canvas: const cd.CanvasProjection(
            nodes: [cd.CanvasNode(id: 'n1', label: 'N1', size: 1)],
            edges: [],
          ),
        ),
        diagnostics: const [],
      );
}

/// updateFromCnl now also triggers PipelineController.runParseAndValidate,
/// which uses a *different* apiClientProvider (api_provider.dart). Throwing
/// keeps this container hermetic — PipelineController catches it.
class _FakePipelineApi extends pipeline_client.ApiClient {
  _FakePipelineApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseResult> parse(String spec) async {
    throw Exception('not mocked in this test');
  }

  @override
  Future<ValidationResult> validate(
    String spec, {
    Map<String, dynamic>? params,
    String backend = 'nir',
  }) async {
    throw Exception('not mocked in this test');
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  test('WorkspaceFile document state preserves canonicalDocument plus '
      'derived branches', () {
    const file = WorkspaceFile(
      id: 'file-1',
      name: 'Spec 1',
      canonicalDocument: cd.CanonicalEditorDocument(
        irJson: {},
        cnlText: 'threshold=1.0',
      ),
    );

    expect(file.canonicalDocument?.cnlText, 'threshold=1.0');
    expect(file.pipelineState, isNull);
    expect(file.revision, 0);
  });

  test(
    'updateFromCnl stores canonical document on active workspace file',
    () async {
      final container = ProviderContainer(
        overrides: [
          canvas_sync.apiClientProvider.overrideWithValue(_FakeCanonicalApi()),
          pipeline_api.apiClientProvider.overrideWithValue(_FakePipelineApi()),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(canonicalDocProvider.notifier)
          .updateFromCnl('threshold=1.0');

      final activeFile = container.read(workspaceProvider).activeFile!;
      expect(activeFile.canonicalDocument, isNotNull);
      expect(activeFile.canonicalDocument!.cnlText, 'threshold=1.0');
    },
  );
}
