import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_app_host.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart';

const _readySettings = LauncherControlSettings(
  logLevel: 'info',
  mujocoAvailable: false,
  pythonAvailable: true,
  pynqBoards: [],
  akidaHosts: [],
  selectedAkidaHostId: null,
  backendDeploymentReady: true,
);

class _StaticBootstrapNotifier extends LauncherBootstrapNotifier {
  _StaticBootstrapNotifier(this.selection);

  final LauncherBootstrapData selection;

  @override
  Future<LauncherBootstrapData> build() async => selection;

  void select(LauncherBootstrapData next) {
    state = AsyncData(next);
  }
}

class _EmptyModuleNotifier extends ModuleNotifier {
  @override
  Future<ModuleState> build() async => const ModuleState();
}

class _EmptyWorkspaceNotifier extends WorkspaceNotifier {
  @override
  Future<WorkspaceState> build() async => const WorkspaceState();
}

class _StaticConnectionNotifier extends ServerConnectionNotifier {
  @override
  ServerConnectionState build() {
    final baseUri = ref.watch(selectedControlApiServiceProvider)?.baseUri;
    if (baseUri == null) {
      return const ServerConnectionState.disconnected();
    }
    return ServerConnectionState(
      phase: ServerConnectionPhase.connected,
      baseUri: baseUri,
    );
  }
}

void main() {
  testWidgets(
    'phone startup shows the workspace under one dismissible setup sheet',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsServiceProvider.overrideWithValue(AnalyticsService()),
            launcherBootstrapProvider.overrideWith(
              () => _StaticBootstrapNotifier(
                LauncherBootstrapData.needsSetup(
                  message: 'The saved server could not be reached.',
                  suggestedInstallHost: '192.168.2.90',
                ),
              ),
            ),
            moduleProvider.overrideWith(_EmptyModuleNotifier.new),
            workspaceProvider.overrideWith(_EmptyWorkspaceNotifier.new),
            serverConnectionProvider.overrideWith(
              _StaticConnectionNotifier.new,
            ),
            backendVersionProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: LauncherAppHost()),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ToolViewScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BackendSetupScreen), findsOneWidget);
      expect(
        find.text('The saved server could not be reached.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '192.168.2.90',
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BackendSetupScreen), findsNothing);
      expect(find.byType(ToolViewScreen), findsOneWidget);
    },
  );

  testWidgets('a successful saved-server bootstrap opens no setup popup', (
    tester,
  ) async {
    final baseUri = Uri.parse('http://192.168.2.90:8090');
    late _StaticBootstrapNotifier bootstrapNotifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
          launcherBootstrapProvider.overrideWith(() {
            bootstrapNotifier = _StaticBootstrapNotifier(
              LauncherBootstrapData.ready(
                bootstrapState: LauncherBootstrapState.ready(baseUri),
                controlApiService: ControlApiService(baseUri: baseUri),
                launcherSettings: _readySettings,
              ),
            );
            return bootstrapNotifier;
          }),
          moduleProvider.overrideWith(_EmptyModuleNotifier.new),
          workspaceProvider.overrideWith(_EmptyWorkspaceNotifier.new),
          serverConnectionProvider.overrideWith(_StaticConnectionNotifier.new),
          backendVersionProvider.overrideWith((ref) async => '1.2.0'),
        ],
        child: const MaterialApp(home: LauncherAppHost()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ToolViewScreen), findsOneWidget);
    expect(find.byType(BackendSetupScreen), findsNothing);

    bootstrapNotifier.select(
      LauncherBootstrapData.needsSetup(message: 'Connection lost.'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackendSetupScreen), findsNothing);
  });
}
