import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neuro_toolkit/features/neurocnl/neurocnl_studio.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';

import 'app_robot.dart';

class FakeModuleNotifier extends ModuleNotifier {
  @override
  Future<ModuleState> build() async {
    return ModuleState(
      modules: [
        Module(
          id: 'Neurochip',
          name: 'NeuroChip',
          description: 'Execution, flashing, and diagnostics workspace',
          directory: '/tmp/neurochip',
          port: 8002,
          hasFrontend: true,
          status: ModuleStatus.running,
        ),
      ],
    );
  }
}

class FakeWorkspaceNotifier extends WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async {
    return const WorkspaceState(
      sessions: [
        WorkspaceSession(
          moduleId: 'Neurochip',
          surfaceMode: 'native',
          readinessState: 'ready',
        ),
      ],
      focusedModuleId: 'Neurochip',
    );
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
          Expanded(
            child: NeurocnlShellAdapter(
              launchContext: NmtkFeatureLaunchContext(
                moduleId: NmtkModuleId.neurocnl,
                backendUri: Uri.parse('http://127.0.0.1:9000/api/neurocnl'),
                onNavigate: (_) async => false,
                onReportError: (_) async {},
                onEditServer: _noopEditServer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _noopEditServer() async {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launcher workspace can open a native adapter surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleProvider.overrideWith(() => FakeModuleNotifier()),
          workspaceProvider.overrideWith(() => FakeWorkspaceNotifier()),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _LauncherAdapterHarness(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(MaterialApp),
      findsOneWidget,
      reason: 'NeuroStudio must inherit the root app instead of nesting one.',
    );

    final robot = AppRobot(tester);
    await robot.assertTextExists('NeuroChip');
    expect(find.byType(NeurocnlShellAdapter), findsOneWidget);
    expect(
      AppLocalizations.of(tester.element(find.byType(NeurocnlShellAdapter))),
      isNotNull,
    );
  });
}
