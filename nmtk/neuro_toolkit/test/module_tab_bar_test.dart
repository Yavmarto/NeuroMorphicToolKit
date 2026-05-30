import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';

class _NoopProcessManager implements ProcessManager {
  @override
  Stream<Module> get statusUpdates => const Stream<Module>.empty();

  @override
  void dispose() {}

  @override
  Stream<String>? getOutput(String moduleId) => null;

  @override
  Future<void> init(List<Module> modules, [dynamic logLevel]) async {}

  @override
  Future<void> installModule(
    Module module, {
    void Function(double progress)? onProgress,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  set processRunner(ProcessRunner runner) {}

  @override
  Future<void> saveModuleState(Module module) async {}

  @override
  Future<void> startModule(Module module, {bool isRetry = false}) async {}

  @override
  Future<void> stopModule(String moduleId, {bool isFailure = false}) async {}
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ModuleTabBar uses rounded launcher-style tabs',
      (WidgetTester tester) async {
    String? selectedModuleId;
    String? closedModuleId;
    final moduleProvider = ModuleProvider(
      processManager: _NoopProcessManager(),
    );
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = <Module>[
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'Authoring workspace',
        directory: 'neurocnl',
        hasFrontend: true,
      ),
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Execution, flashing, and diagnostics',
        directory: 'Neurochip',
        hasFrontend: true,
      ),
    ];

    await workspaceProvider.openSession(
      'neurocnl',
      surfaceMode: 'embedded',
      readinessState: 'ready',
    );
    await workspaceProvider.openSession(
      'Neurochip',
      surfaceMode: 'embedded',
      readinessState: 'ready',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ModuleTabBar(
              activeModuleId: 'neurocnl',
              onTabSelected: (id) {
                selectedModuleId = id;
              },
              onTabClosed: (id) {
                closedModuleId = id;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tokens = NmtkShellTokens.of(
      tester.element(find.byType(ModuleTabBar)),
    );
    final activeTab = tester.widget<Ink>(
      find.byKey(const ValueKey<String>('module-tab-neurocnl')),
    );
    final inactiveTab = tester.widget<Ink>(
      find.byKey(const ValueKey<String>('module-tab-Neurochip')),
    );

    final activeDecoration = activeTab.decoration! as BoxDecoration;
    final inactiveDecoration = inactiveTab.decoration! as BoxDecoration;

    expect(
      activeDecoration.borderRadius,
      BorderRadius.circular(tokens.radiusMd),
    );
    expect(
      inactiveDecoration.borderRadius,
      BorderRadius.circular(tokens.radiusMd),
    );
    expect(activeDecoration.color, isNot(equals(Colors.transparent)));
    expect(inactiveDecoration.color, isNot(equals(Colors.transparent)));

    expect(
        tester.getSize(find.byTooltip('Close CNL Studio')), const Size(44.0, 41.0));
    expect(
        tester.getSize(find.byTooltip('Close NeuroChip')), const Size(44.0, 41.0));

    await tester.tap(find.text('NeuroChip'));
    await tester.pump();
    expect(selectedModuleId, 'Neurochip');

    await tester.tap(find.byTooltip('Close CNL Studio'));
    await tester.pump();
    expect(closedModuleId, 'neurocnl');
  });

  testWidgets('ModuleTabBar exposes tab semantics',
      (WidgetTester tester) async {
    final semanticsHandle = tester.ensureSemantics();

    final moduleProvider = ModuleProvider(
      processManager: _NoopProcessManager(),
    );
    final workspaceProvider = WorkspaceProvider(
      controlApiService: _FakeWorkspaceControlApiService(),
    );
    moduleProvider.modules = <Module>[
      Module(
        id: 'neurocnl',
        name: 'CNL Studio',
        description: 'Authoring workspace',
        directory: 'neurocnl',
        hasFrontend: true,
      ),
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Execution, flashing, and diagnostics',
        directory: 'Neurochip',
        hasFrontend: true,
      ),
    ];

    await workspaceProvider.openSession(
      'neurocnl',
      surfaceMode: 'embedded',
      readinessState: 'ready',
    );
    await workspaceProvider.openSession(
      'Neurochip',
      surfaceMode: 'embedded',
      readinessState: 'ready',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleStateProvider.overrideWith((ref) => moduleProvider),
          workspaceStateProvider.overrideWith((ref) => workspaceProvider),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ModuleTabBar(
              activeModuleId: 'neurocnl',
              onTabSelected: (_) {},
              onTabClosed: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeSemantics = tester.getSemantics(
      find.byKey(const ValueKey<String>('module-tab-neurocnl')),
    );
    final inactiveSemantics = tester.getSemantics(
      find.byKey(const ValueKey<String>('module-tab-Neurochip')),
    );

    expect(activeSemantics.label, contains('CNL Studio module tab'));
    expect(activeSemantics.flagsCollection.isButton, isTrue);
    expect(activeSemantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(inactiveSemantics.label, contains('NeuroChip module tab'));
    expect(inactiveSemantics.flagsCollection.isButton, isTrue);
    
    semanticsHandle.dispose();
  });
}
