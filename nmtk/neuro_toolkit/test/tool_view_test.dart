import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakePlatformWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return _FakePlatformWebViewCookieManager(params);
  }
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(
      PlatformNavigationDelegateCreationParams params)
      : super.implementation(params);

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {}
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(PlatformWebViewControllerCreationParams params)
      : super.implementation(params);

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(PlatformWebViewWidgetCreationParams params)
      : super.implementation(params);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakePlatformWebViewCookieManager extends PlatformWebViewCookieManager {
  _FakePlatformWebViewCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) : super.implementation(params);
}

class _NoopProcessManager implements ProcessManager {
  final _statusController = StreamController<Module>.broadcast();

  @override
  Stream<Module> get statusUpdates => _statusController.stream;

  @override
  Future<void> init(List<Module> modules, [dynamic logLevel]) async {}

  @override
  Future<void> installModule(
    Module module, {
    void Function(double progress)? onProgress,
  }) async {}

  @override
  Future<void> startModule(Module module, {bool isRetry = false}) async {}

  @override
  Future<void> stopModule(String moduleId, {bool isFailure = false}) async {}

  @override
  void dispose() {
    _statusController.close();
  }

  @override
  Stream<String>? getOutput(String moduleId) => null;

  @override
  Future<void> saveModuleState(Module module) async {}

  @override
  set processRunner(ProcessRunner runner) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingModuleProvider extends ModuleProvider {
  _TrackingModuleProvider() : super(processManager: _NoopProcessManager());

  final List<String> launchedModuleIds = <String>[];

  @override
  Future<void> launchModule(String moduleId) async {
    launchedModuleIds.add(moduleId);
    final index = modules.indexWhere((module) => module.id == moduleId);
    if (index == -1) {
      return;
    }
    final nextModules = List<Module>.from(modules);
    nextModules[index] = nextModules[index].copyWith(
      status: ModuleStatus.starting,
      healthStatus: null,
    );
    modules = nextModules;
  }
}

class _FakeWorkspaceControlApiService extends ControlApiService {
  _FakeWorkspaceControlApiService({
    WorkspaceSnapshot initialSnapshot = const WorkspaceSnapshot(
      sessions: <WorkspaceSession>[],
      focusedModuleId: null,
    ),
  })  : _snapshot = initialSnapshot,
        super(baseUri: Uri.parse('http://127.0.0.1:8090'));

  WorkspaceSnapshot _snapshot;

  @override
  Future<WorkspaceSnapshot> fetchWorkspace() async => _snapshot;

  @override
  Future<WorkspaceSnapshot> createWorkspaceSession({
    required String moduleId,
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {
    final sessions = _snapshot.sessions
        .where((session) => session.moduleId != moduleId)
        .toList(growable: true)
      ..add(
        WorkspaceSession(
          moduleId: moduleId,
          surfaceMode: surfaceMode,
          deepLink: deepLink,
          restoreState: restoreState,
          readinessState: readinessState,
        ),
      );
    _snapshot = WorkspaceSnapshot(
      sessions: sessions,
      focusedModuleId: moduleId,
    );
    return _snapshot;
  }

  @override
  Future<WorkspaceSnapshot> updateWorkspace({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {
    _snapshot = WorkspaceSnapshot(
      sessions: List<WorkspaceSession>.from(sessions),
      focusedModuleId: focusedModuleId,
    );
    return _snapshot;
  }

  @override
  Future<WorkspaceSnapshot> deleteWorkspaceSession(String moduleId) async {
    final sessions = _snapshot.sessions
        .where((session) => session.moduleId != moduleId)
        .toList(growable: false);
    _snapshot = WorkspaceSnapshot(
      sessions: sessions,
      focusedModuleId: sessions.isEmpty ? null : sessions.last.moduleId,
    );
    return _snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WebViewPlatform.instance = _FakeWebViewPlatform();

  testWidgets('ToolView seeds all launcher tabs on startup',
      (WidgetTester tester) async {
    final moduleProvider = _TrackingModuleProvider();
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = [
      Module(
        id: 'neurocnl',
        name: 'NeuroStudio',
        description: 'Desc 1',
        directory: '/tmp/m1',
        port: 8000,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Desc 2',
        directory: '/tmp/m2',
        port: 8002,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
      Module(
        id: 'ndh',
        name: 'NDH',
        description: 'CLI only',
        directory: '/tmp/ndh',
        startStrategy: 'none',
        status: ModuleStatus.installed,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: _buildTestShell(const ToolViewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(NmtkDesktopScaffold), findsOneWidget);
    expect(find.text('NDH'), findsNothing);
    expect(workspaceProvider.sessions.map((session) => session.moduleId), [
      'neurocnl',
      'Neurochip',
    ]);
  });

  testWidgets(
      'ToolView forces embedded surfaces when control API uses a remote host',
      (WidgetTester tester) async {
    final moduleProvider = _TrackingModuleProvider();
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = [
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Desc 1',
        directory: '/tmp/m1',
        port: 9000,
        hasFrontend: true,
        startStrategy: 'none',
        status: ModuleStatus.running,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          launcherBootstrapStateProvider.overrideWithValue(
            LauncherBootstrapState.ready(
              Uri.parse('http://192.168.1.50:8090'),
            ),
          ),
          controlApiServiceProvider.overrideWithValue(
            ControlApiService(baseUri: Uri.parse('http://192.168.1.50:8090')),
          ),
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: _buildTestShell(const ToolViewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(workspaceProvider.sessions, hasLength(1));
    expect(workspaceProvider.sessions.single.moduleId, 'Neurochip');
    expect(workspaceProvider.sessions.single.surfaceMode, 'embedded');
  });

  testWidgets(
      'ToolView reconciles missing persisted sessions for eligible modules',
      (WidgetTester tester) async {
    final moduleProvider = _TrackingModuleProvider();
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(
        initialSnapshot: const WorkspaceSnapshot(
          sessions: <WorkspaceSession>[
            WorkspaceSession(
              moduleId: 'm1',
              surfaceMode: 'embedded',
              readinessState: 'warming_up',
            ),
          ],
          focusedModuleId: 'm1',
        ),
      ),
    );
    moduleProvider.modules = [
      Module(
        id: 'neurocnl',
        name: 'NeuroStudio',
        description: 'Desc 1',
        directory: '/tmp/m1',
        port: 8000,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.starting,
      ),
      Module(
        id: 'Neurobench',
        name: 'NeuroBench',
        description: 'Desc 2',
        directory: '/tmp/m2',
        port: 8003,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
      Module(
        id: 'Neurohub',
        name: 'NeuroHub',
        description: 'Desc 3',
        directory: '/tmp/m3',
        port: 8005,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: _buildTestShell(const ToolViewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(workspaceProvider.sessions.map((session) => session.moduleId), [
      'neurocnl',
      'Neurobench',
      'Neurohub',
    ]);
  });

  testWidgets('opening a second workspace session preserves focus state',
      (WidgetTester tester) async {
    final moduleProvider = _TrackingModuleProvider();
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = [
      Module(
        id: 'neurocnl',
        name: 'NeuroStudio',
        description: 'Desc 1',
        directory: '/tmp/m1',
        port: 8000,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Desc 2',
        directory: '/tmp/m2',
        port: 8002,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: _buildTestShell(const ToolViewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(moduleProvider.launchedModuleIds, contains('neurocnl'));

    await workspaceProvider.openSession(
      'Neurochip',
      surfaceMode: 'embedded',
      readinessState: 'opening',
    );
    await tester.pump();

    expect(workspaceProvider.focusedModuleId, 'Neurochip');
    expect(
      workspaceProvider.sessions.map((session) => session.moduleId),
      ['neurocnl', 'Neurochip'],
    );
  });

  testWidgets('ToolView shows launcher preflight error instead of polling',
      (WidgetTester tester) async {
    final moduleProvider =
        ModuleProvider(processManager: _NoopProcessManager());
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = [
      Module(
        id: 'Neurobench',
        name: 'NeuroBench',
        description: 'Benchmarking',
        directory: 'Neurobench',
        port: 8003,
        hasFrontend: true,
        status: ModuleStatus.error,
        preflightStatus: 'failed',
        preflightMessage:
            'Missing required dependency: fastapi (needed by app.main)',
      ),
    ];
    await workspaceProvider.openSession(
      'Neurobench',
      surfaceMode: 'embedded',
      readinessState: 'error',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: _buildTestShell(
          const ToolViewScreen(initialModuleId: 'Neurobench'),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Missing required dependency: fastapi (needed by app.main)'),
      findsOneWidget,
    );
    expect(find.text('Retry Start'), findsOneWidget);
    expect(find.textContaining('Checking http'), findsNothing);
  });

  testWidgets(
      'ToolView hides launcher-nav-disabled modules and falls back focus',
      (WidgetTester tester) async {
    final moduleProvider = _TrackingModuleProvider();
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(
        initialSnapshot: const WorkspaceSnapshot(
          sessions: <WorkspaceSession>[
            WorkspaceSession(
              moduleId: 'neurocnl',
              surfaceMode: 'embedded',
              readinessState: 'warming_up',
            ),
            WorkspaceSession(
              moduleId: 'Neurochip',
              surfaceMode: 'embedded',
              readinessState: 'warming_up',
            ),
          ],
          focusedModuleId: 'Neurochip',
        ),
      ),
    );
    moduleProvider.modules = [
      Module(
        id: 'neurocnl',
        name: 'NeuroStudio',
        description: 'Studio',
        directory: '/tmp/neurocnl',
        port: 8000,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Hardware runtime',
        directory: '/tmp/neurochip',
        port: 8002,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
        showInLauncherNav: false,
      ),
      Module(
        id: 'Neurobench',
        name: 'NeuroBench',
        description: 'Bench',
        directory: '/tmp/neurobench',
        port: 8003,
        hasFrontend: true,
        startStrategy: 'uvicorn',
        status: ModuleStatus.installed,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: _buildTestShell(const ToolViewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(workspaceProvider.focusedModuleId, 'neurocnl');
    expect(workspaceProvider.sessions.map((session) => session.moduleId), [
      'neurocnl',
      'Neurobench',
    ]);
    expect(moduleProvider.launchedModuleIds, contains('neurocnl'));
  });
}

Widget _buildTestShell(Widget home) {
  return ShadApp(
    theme: NmtkShadTheme.light,
    darkTheme: NmtkShadTheme.dark,
    themeMode: ThemeMode.dark,
    materialThemeBuilder: (_, __) => AppTheme.darkTheme,
    home: home,
  );
}
