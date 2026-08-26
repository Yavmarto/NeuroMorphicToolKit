import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';
import 'package:neurobench_frontend/shell_adapter.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

Future<void> _noopEditServer() async {}
Future<void> _noopReportError(NmtkFeatureErrorEvent event) async {}

void main() {
  testWidgets('legacy Neurobench session receives its root launch context', (
    WidgetTester tester,
  ) async {
    final launchContext = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurobench,
      backendUri: Uri.parse('http://127.0.0.1:9000/api/neurobench'),
      authentication: const NmtkFeatureAuthentication(adminToken: 'token'),
      initialLocation: '/reports',
      restorationState: const <String, Object?>{'tab': 'reports'},
      onNavigate: (_) async => true,
      onReportError: _noopReportError,
      onEditServer: _noopEditServer,
    );

    await tester.pumpWidget(
      NativeSurfaceRegistry.build(
        const WorkspaceSession(moduleId: 'Neurobench'),
        launchContext: launchContext,
      ),
    );

    final adapter = tester.widget<NeurobenchShellAdapter>(
      find.byType(NeurobenchShellAdapter),
    );
    expect(adapter.launchContext, same(launchContext));
  });

  test('unknown workspace IDs fail at the root boundary', () {
    final launchContext = NmtkFeatureLaunchContext(
      moduleId: NmtkModuleId.neurocnl,
      backendUri: Uri.parse('http://127.0.0.1:9000/api/neurocnl'),
      onNavigate: (_) async => false,
      onReportError: _noopReportError,
      onEditServer: _noopEditServer,
    );

    expect(
      () => NativeSurfaceRegistry.build(
        const WorkspaceSession(moduleId: 'unknown-feature'),
        launchContext: launchContext,
      ),
      throwsArgumentError,
    );
  });
}
