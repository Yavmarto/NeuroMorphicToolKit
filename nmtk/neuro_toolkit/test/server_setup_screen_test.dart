import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/backend_deployment_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_setup.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:nmtk_ui_core/app_theme.dart';
import 'package:nmtk_ui_core/models/akida_deployment_model.dart';
import 'package:nmtk_ui_core/models/pynq_deployment_model.dart';


void main() {
  testWidgets('shows setup unavailable guidance until control API is reachable',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        const ServerSetupScreen(
          message: 'Enter the host or base URL for the launcher control API.',
          onConnect: null,
          setupAvailable: false,
        ),
      ),
    );

    expect(find.text('Connect to a server'), findsOneWidget);
    expect(find.text('Set up a new server'), findsOneWidget);
    expect(
      find.textContaining('Connect to a launcher server first'),
      findsOneWidget,
    );
  });

  testWidgets('opens the embedded setup form from the connect screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        const ServerSetupScreen(
          message: 'Connect to another launcher server or set up a new one.',
          onConnect: null,
          setupAvailable: true,
        ),
        overrides: [
          backendDeploymentStateProvider.overrideWith(
            (ref) => FakeBackendDeploymentProvider(),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Set Up a New Server'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('backend-setup-form')), findsOne);
    expect(find.text('1. Choose where to run the backend'), findsOneWidget);
    expect(find.text('2. Choose deployment mode'), findsOneWidget);
  });
}

Widget _buildTestApp(
  Widget child, {
  List<Override> overrides = const <Override>[],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      title: 'Server setup test',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    ),
  );
}

class FakeBackendDeploymentProvider extends BackendDeploymentProvider {
  FakeBackendDeploymentProvider()
      : super(controlApiService: FakeControlApiService());
}

class FakeControlApiService extends ControlApiService {
  FakeControlApiService() : super(baseUri: Uri.parse('http://127.0.0.1:8090'));

  @override
  Future<LauncherControlSettings> fetchSettings() async {
    return const LauncherControlSettings(
      logLevel: 'info',
      mujocoAvailable: false,
      pythonAvailable: true,
      pynqBoards: <PynqPairedBoard>[],
      akidaHosts: <AkidaPairedHost>[],
      selectedAkidaHostId: null,
      backendDeploymentReady: false,
    );
  }

  @override
  Future<List<DeploymentTarget>> fetchDeploymentTargets() async {
    return const <DeploymentTarget>[];
  }

  @override
  Future<DeploymentPreflightResult> preflightDeploymentTarget(
    Map<String, dynamic> payload,
  ) async {
    return const DeploymentPreflightResult(
      status: 'ok',
      message: 'Ready',
      blockingFindings: <String>[],
      degradedFindings: <String>[],
      suggestedRecovery: '',
    );
  }
}
