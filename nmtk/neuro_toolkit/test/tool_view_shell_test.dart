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
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';
import 'package:neuro_toolkit/widgets/module_loading_view.dart';

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
  Future<void> focusSession(String moduleId) async {}

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
          controlApiServiceProvider.overrideWithValue(
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

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NmtkTopAppBar), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
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
          controlApiServiceProvider.overrideWithValue(
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
}
