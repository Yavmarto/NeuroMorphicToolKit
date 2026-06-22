import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neurocnl_studio/shell_adapter.dart';
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
    return ModuleState(modules: [
      Module(
        id: 'Neurochip',
        name: 'NeuroChip',
        description: 'Execution, flashing, and diagnostics workspace',
        directory: '/tmp/neurochip',
        port: 8002,
        hasFrontend: true,
        status: ModuleStatus.running,
      ),
    ]);
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
          const Expanded(
            child: NeurocnlShellAdapter(
              initialLocation: '/unknown/path',
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleProvider.overrideWith(() => FakeModuleNotifier()),
          workspaceProvider.overrideWith(() => FakeWorkspaceNotifier()),
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
