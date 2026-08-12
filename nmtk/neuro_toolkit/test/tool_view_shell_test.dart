import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';
import 'package:neuro_toolkit/widgets/module_loading_view.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

class _FakeModuleNotifier extends ModuleNotifier {
  @override
  Future<ModuleState> build() async {
    return ModuleState(
      modules: [
        Module(
          id: 'neurocnl',
          name: 'NeuroStudio',
          description: 'CNL compiler and visual design suite',
          directory: 'neurocnl',
          hasFrontend: true,
          status: ModuleStatus.starting,
        ),
        Module(
          id: 'Neurobench',
          name: 'Bench',
          description: 'SNN benchmarking workspace',
          directory: 'Neurobench',
          hasFrontend: true,
          status: ModuleStatus.starting,
        ),
      ],
    );
  }
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async {
    return const WorkspaceState(
      sessions: [
        WorkspaceSession(
          moduleId: 'neurocnl',
          surfaceMode: 'embedded',
          readinessState: 'warming_up',
        ),
        WorkspaceSession(
          moduleId: 'Neurobench',
          surfaceMode: 'embedded',
          readinessState: 'warming_up',
        ),
      ],
      focusedModuleId: 'neurocnl',
    );
  }

  @override
  Future<void> ensureDefaultSessionsOnce({
    required List<WorkspaceSession> sessions,
    required String? focusedModuleId,
  }) async {}

  @override
  Future<void> openSession(
    String moduleId, {
    required String surfaceMode,
    String? deepLink,
    Map<String, dynamic> restoreState = const <String, dynamic>{},
    String readinessState = 'opening',
  }) async {}

  @override
  Future<void> focusSession(String moduleId) async {
    state =
        state.whenData((value) => value.copyWith(focusedModuleId: moduleId));
  }

  @override
  Future<void> updateSession(
    String moduleId, {
    String? deepLink,
    Map<String, dynamic>? restoreState,
    String? readinessState,
  }) async {}

  @override
  Future<void> closeSession(String moduleId) async {}
}

void main() {
  testWidgets('ToolViewScreen uses top bar workspace chrome', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          selectedControlApiServiceProvider.overrideWithValue(
            ControlApiService(
              baseUri: Uri.parse('http://localhost:9000'),
              analyticsService: AnalyticsService(),
            ),
          ),
          moduleProvider.overrideWith(_FakeModuleNotifier.new),
          workspaceProvider.overrideWith(_FakeWorkspaceNotifier.new),
        ],
        child: const MaterialApp(home: ToolViewScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NmtkTopAppBar), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
  });

  testWidgets('Profile button opens the profile dialog', (tester) async {
    final observer = _RecordingNavigatorObserver();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: const Scaffold(
          body: LauncherProfileButton(iconColor: Colors.black),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byTooltip('Profile'));

    expect(observer.pushedRoutes, hasLength(2));
    expect(observer.pushedRoutes.last, isA<DialogRoute<void>>());
  });

  testWidgets('narrow launcher mounts only the active module surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          selectedControlApiServiceProvider.overrideWithValue(
            ControlApiService(
              baseUri: Uri.parse('http://localhost:9000'),
              analyticsService: AnalyticsService(),
            ),
          ),
          moduleProvider.overrideWith(() => _FakeModuleNotifier()),
          workspaceProvider.overrideWith(() => _FakeWorkspaceNotifier()),
        ],
        child: const MaterialApp(home: ToolViewScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // An IndexedStack used to mount both waiting surfaces here. The narrow
    // layout must retain only the currently selected module's frontend.
    expect(find.byType(ModuleLoadingView), findsOneWidget);
    expect(find.text('Waiting for NeuroStudio'), findsOneWidget);
    expect(find.text('Waiting for Bench'), findsNothing);
  });

  testWidgets('typed launcher navigation focuses an eligible module', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          selectedControlApiServiceProvider.overrideWithValue(
            ControlApiService(
              baseUri: Uri.parse('http://localhost:9000'),
              analyticsService: AnalyticsService(),
            ),
          ),
          moduleProvider.overrideWith(_FakeModuleNotifier.new),
          workspaceProvider.overrideWith(_FakeWorkspaceNotifier.new),
        ],
        child: const MaterialApp(home: ToolViewScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ToolViewScreen)),
    );
    container
        .read(launcherNavigationProvider.notifier)
        .openModule('Neurobench');
    expect(
      container.read(launcherNavigationProvider)?.moduleId,
      'Neurobench',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(workspaceProvider).value?.focusedModuleId,
      'Neurobench',
    );

    expect(find.text('Waiting for Bench'), findsOneWidget);
    expect(find.text('Waiting for NeuroStudio'), findsNothing);
  });
}
