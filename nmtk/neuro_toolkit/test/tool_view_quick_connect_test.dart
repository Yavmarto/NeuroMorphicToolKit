import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_app_host.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';

class MockLauncherBootstrapNotifier extends LauncherBootstrapNotifier {
  @override
  Future<LauncherBootstrapData> build() async {
    return LauncherBootstrapData.needsSetup(message: 'Needs setup');
  }

  @override
  Future<String?> connectToLauncher(String rawInput) async {
    return null; // Return null to indicate success
  }
}

class _FakeModuleNotifier extends ModuleNotifier {
  @override
  Future<ModuleState> build() async => const ModuleState(modules: []);
}

class _FakeWorkspaceNotifier extends WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async =>
      const WorkspaceState(sessions: [], focusedModuleId: null);
}

void main() {
  testWidgets('Quick connect dismisses popup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          selectedControlApiServiceProvider.overrideWithValue(
            ControlApiService(
              baseUri: Uri.parse('http://192.168.2.90:8090'),
              analyticsService: AnalyticsService(),
            ),
          ),
          launcherBootstrapProvider
              .overrideWith(() => MockLauncherBootstrapNotifier()),
          moduleProvider.overrideWith(() => _FakeModuleNotifier()),
          workspaceProvider.overrideWith(() => _FakeWorkspaceNotifier()),
          backendVersionProvider.overrideWith((_) async => 'dev'),
        ],
        child: const MaterialApp(home: LauncherAppHost()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(BackendSetupScreen), findsOneWidget);
    expect(
      find.text('192.168.2.90 · Development build · Checking'),
      findsOneWidget,
    );

    // Type in the quick connect field
    await tester.enterText(find.byType(TextField).first, '192.168.1.10');
    await tester.pump();

    // Tap the quick connect button
    await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(BackendSetupScreen), findsNothing);
  });
}
