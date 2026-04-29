import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neurochip/shell_adapter.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';

import 'app_robot.dart';

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

class _LauncherAdapterHarness extends StatelessWidget {
  const _LauncherAdapterHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ModuleTabBar(
            activeModuleId: 'Neurochip',
            onTabSelected: (_) {},
            onTabClosed: (_) {},
          ),
          const Expanded(
            child: NeurochipShellAdapter(
              initialDeepLink: '/unknown/path',
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launcher workspace can open a native adapter surface',
      (WidgetTester tester) async {
    final moduleProvider =
        ModuleProvider(processManager: _MockProcessManager());
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = <Module>[
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Execution, flashing, and diagnostics workspace',
        directory: '/tmp/neurochip',
        port: 8002,
        hasFrontend: true,
        status: ModuleStatus.running,
      ),
    ];
    await workspaceProvider.openSession(
      'Neurochip',
      surfaceMode: 'native',
      readinessState: 'ready',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: const MaterialApp(
          home: _LauncherAdapterHarness(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final robot = AppRobot(tester);
    await robot.assertTextExists('NeuroChip');
    await robot.tap('NeuroChip');
    await robot.assertTextExists('Execution Status');
    await robot.tap('Execution Status');
    await robot.assertTextExists('Neurochip execution workspace');
  });
}
