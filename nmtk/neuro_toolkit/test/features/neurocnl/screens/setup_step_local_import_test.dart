import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart' show CnlTemplate;
import 'package:neuro_toolkit/features/neurocnl/models/launcher_diagnostics.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/launcher_diagnostics_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/target_availability_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/template_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/studio_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
    RunningNotebookTasksNotifier.debugSetPollInterval(null);
  });

  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({});
    WebViewPlatform.instance = _FakeWebViewPlatform();
    ServerConfigService.debugResetForTests();
  });

  testWidgets('import from device selects the imported dataset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ImportRecordingApiClient();
    final backend = _ImportNativeFileBackend(
      openDatasetImportResult: OpenedBinaryFile(
        name: 'events.aedat',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        path: '/tmp/events.aedat',
      ),
    );

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        nativeFileAdapterProvider.overrideWithValue(FileAdapter(backend)),
        templateControllerProvider.overrideWithValue(const AsyncData([])),
        targetAvailabilityProvider.overrideWith(
          (ref) async => <String, bool>{},
        ),
        launcherDiagnosticsProvider.overrideWith(
          (ref) async => LauncherDiagnostics.unavailable('test'),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StudioScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(workspaceProvider.notifier)
        .setActivePipelineStep('selectData');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final importButton = find
        .byKey(const Key('setup-import-dataset-button'))
        .first;
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final workspace = container.read(workspaceProvider);
    expect(workspace.selectedDataset, 'local-events-aedat');
    expect(workspace.selectedDatasetPath, '/data/local/events.aedat');
    expect(api.importCalls, 1);
    expect(api.lastImportFilename, 'events.aedat');
    expect(api.lastImportServerPath, '/tmp/events.aedat');

    container.dispose();
    await tester.pump();
  });
}

class _ImportRecordingApiClient extends ApiClient {
  _ImportRecordingApiClient() : super(baseUrl: 'http://test');

  int importCalls = 0;
  String? lastImportFilename;
  String? lastImportServerPath;

  @override
  Future<List<CnlTemplate>> getTemplates() async => const [];

  @override
  Future<String> ensureWorkspace({required String workspacePath}) async {
    return 'ok';
  }

  @override
  Future<void> syncWorkspace({
    required String slug,
    required String name,
    required Map<String, dynamic> config,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) return null;
    return Future.value(null);
  }

  @override
  Future<DatasetCatalogList> listDatasets() async {
    return const DatasetCatalogList(
      firebaseAvailable: false,
      datasets: [],
      folders: [],
    );
  }

  @override
  Future<DatasetEntry> importLocalDataset({
    required String filename,
    required Uint8List bytes,
    String? serverPath,
  }) async {
    importCalls += 1;
    lastImportFilename = filename;
    lastImportServerPath = serverPath;
    return const DatasetEntry(
      id: 'local-events-aedat',
      label: 'events.aedat',
      description: 'Imported from this device (events.aedat).',
      storagePath: 'local://events.aedat',
      folderPath: 'local/',
      status: DatasetServerStatus.ready,
      localPath: '/data/local/events.aedat',
      source: 'local',
      format: 'aedat',
    );
  }
}

class _ImportNativeFileBackend implements NativeFileBackend {
  _ImportNativeFileBackend({required this.openDatasetImportResult});

  final OpenedBinaryFile? openDatasetImportResult;

  @override
  Future<OpenedBinaryFile?> openDatasetImport() async =>
      openDatasetImportResult;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() async => null;

  @override
  Future<OpenedTextFile?> openWorkspaceFile() async => null;

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) async {
    return const SaveResult(outcome: SaveOutcome.saved);
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

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakeWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakeWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    throw UnimplementedError();
  }
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
