import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';

class _MockProcessManager implements ProcessManager {
  @override
  Stream<Module> get statusUpdates => const Stream<Module>.empty();

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
  void dispose() {}

  @override
  Stream<String>? getOutput(String moduleId) => null;

  @override
  Future<void> saveModuleState(Module module) async {}

  @override
  set processRunner(ProcessRunner runner) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWorkspaceControlApiService extends ControlApiService {
  _FakeWorkspaceControlApiService()
      : super(baseUri: Uri.parse('http://127.0.0.1:8090'));

  WorkspaceSnapshot _snapshot = const WorkspaceSnapshot(
    sessions: <WorkspaceSession>[],
    focusedModuleId: null,
  );

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
  testWidgets('ToolViewScreen shows persisted workspace sidebar items',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final moduleProvider =
        ModuleProvider(processManager: _MockProcessManager());
    final controlApiService = _FakeWorkspaceControlApiService();
    final workspaceProvider = WorkspaceProvider(
      controlApiService: controlApiService,
    );
    moduleProvider.modules = [
      Module(
        id: 'neurocnl',
        name: 'NeuroStudio',
        description: 'Desc 1',
        directory: '/tmp/m1',
        port: 8001,
        hasFrontend: true,
        // starting → shows loading state; avoids rendering the native surface
        // adapter which requires module-specific Riverpod provider scopes.
        status: ModuleStatus.starting,
      ),
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Desc 2',
        directory: '/tmp/m2',
        port: 8002,
        hasFrontend: true,
        status: ModuleStatus.starting,
      ),
    ];
    await workspaceProvider.openSession(
      'neurocnl',
      surfaceMode: 'native',
      readinessState: 'opening',
    );
    await workspaceProvider.openSession(
      'Neurochip',
      surfaceMode: 'native',
      readinessState: 'opening',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          controlApiServiceProvider.overrideWithValue(controlApiService),
          settingsStateProvider.overrideWith((ref) => SettingsProvider()),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: ShadApp(
          theme: NmtkShadTheme.light,
          darkTheme: NmtkShadTheme.dark,
          themeMode: ThemeMode.dark,
          materialThemeBuilder: (_, __) => AppTheme.darkTheme,
          home: const ToolViewScreen(),
        ),
      ),
    );

    await tester.pump();
    // NmtkDesktopScaffold replaces ModuleTabBar: modules appear as sidebar items.
    expect(find.byType(NmtkDesktopScaffold), findsOneWidget);
    expect(
      workspaceProvider.sessions.map((session) => session.moduleId),
      ['neurocnl', 'Neurochip'],
    );
  });
}
