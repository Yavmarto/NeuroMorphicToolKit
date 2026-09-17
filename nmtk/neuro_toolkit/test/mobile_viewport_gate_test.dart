// Mobile viewport overflow baseline (CEL-73), gate for CEL-72.
//
// Pumps a handful of live entry-point screens at three mobile viewports
// (360x640, 390x844, 414x896) and fails on a RenderFlex overflow. This is a
// BASELINE: known overflows found while writing this suite are marked
// `skip:` with the pixel amount rather than fixed here — fixing them is
// scoped to child issues under CEL-72.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurobench/models/workbench_tab.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/neurobench_mobile_wizard.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/provision/provision_notifier.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_connect_screen.dart';
import 'package:neuro_toolkit/screens/server_setup_screen.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';

import 'helpers/mobile_viewport.dart';

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
    state = state.whenData(
      (value) => value.copyWith(focusedModuleId: moduleId),
    );
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

class _StubConnectNotifier extends ConnectNotifier {
  @override
  ConnectState build() => const ConnectState();

  @override
  Future<void> connect(ConnectRequest request) async {}
}

class _StubProvisionNotifier extends ProvisionNotifier {
  @override
  ProvisionState build() => const ProvisionState();

  @override
  Future<void> provision(ProvisionRequest request) async {}
}

void main() {
  group('mobile viewport overflow baseline', () {
    testMobileViewports(
      'ToolViewScreen',
      (context) => ProviderScope(
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
      // ToolViewScreen's loading surface keeps an indeterminate spinner
      // animating (see test/tool_view_shell_test.dart, which uses bounded
      // pumps for the same reason) — pumpAndSettle never converges here.
      settleDuration: const Duration(seconds: 1),
    );

    testMobileViewports(
      'ServerConnectScreen',
      (context) => ProviderScope(
        overrides: [
          connectNotifierProvider.overrideWith(_StubConnectNotifier.new),
        ],
        child: const MaterialApp(home: ServerConnectScreen()),
      ),
    );

    testMobileViewports(
      'ServerSetupScreen',
      (context) => ProviderScope(
        overrides: [
          provisionNotifierProvider.overrideWith(_StubProvisionNotifier.new),
        ],
        child: const MaterialApp(home: ServerSetupScreen()),
      ),
    );

    testMobileViewports(
      'NeurobenchMobileWizard',
      (context) => const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NeurobenchMobileWizard(
              activeBenchmark: null,
              initialTab: NeurobenchWorkbenchTab.configure,
              onTabChanged: _noopTabChanged,
            ),
          ),
        ),
      ),
    );
  });
}

void _noopTabChanged(NeurobenchWorkbenchTab _) {}
