import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';

class _FakeDeploymentService implements DeploymentService {
  @override
  Future<DeploymentSnapshot> load() async => const DeploymentSnapshot();

  @override
  Future<DeploymentPreflightResult> preflight(
    DeploymentRequest request,
  ) async {
    return const DeploymentPreflightResult(
      status: 'ok',
      message: 'ready',
      blockingFindings: [],
      degradedFindings: [],
      suggestedRecovery: '',
    );
  }

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob> cancelJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob> fetchJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<DeploymentJob?> retryJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<void> retryJupyter(String targetId) {
    throw UnimplementedError();
  }
}

Widget _harness({bool? localDeploymentAvailable}) {
  return ProviderScope(
    overrides: [
      deploymentServiceProvider.overrideWithValue(_FakeDeploymentService()),
    ],
    child: MaterialApp(
      home: BackendSetupScreen(
        localDeploymentAvailable: localDeploymentAvailable,
        onDeploymentReady: (_) async {},
      ),
    ),
  );
}

void main() {
  testWidgets('setup opens the deployment form without launcher connection UI',
      (tester) async {
    await tester.pumpWidget(_harness(localDeploymentAvailable: true));
    await tester.pump();

    expect(find.text('Set up your backend'), findsOneWidget);
    expect(find.byType(BackendSetupForm), findsOneWidget);
    expect(find.text('Connect to server'), findsNothing);
    expect(find.text('Server address'), findsNothing);
    expect(find.text('Save & Retry'), findsNothing);
    expect(find.text('Step 1 — Python'), findsNothing);
  });

  testWidgets('mobile omits the impossible local deployment target',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness(localDeploymentAvailable: false));
    await tester.pump();

    expect(find.text('This machine'), findsNothing);
    expect(find.text('Remote server'), findsOneWidget);
    expect(find.text('Existing Kubernetes cluster'), findsOneWidget);
  });

  testWidgets(
      'quick-connect card connects directly to an already-running '
      'server by host', (tester) async {
    DeploymentTarget? connected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deploymentServiceProvider.overrideWithValue(_FakeDeploymentService()),
        ],
        child: MaterialApp(
          home: BackendSetupScreen(
            localDeploymentAvailable: true,
            onDeploymentReady: (target) async {
              connected = target;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Already have a server running?'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      '192.168.2.51',
    );
    await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
    await tester.pumpAndSettle();

    expect(connected, isNotNull);
    expect(connected!.host, '192.168.2.51');
    expect(connected!.targetType, 'remote_host');
  });

  testWidgets('quick-connect preserves input and shows an actionable failure',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deploymentServiceProvider.overrideWithValue(_FakeDeploymentService()),
        ],
        child: MaterialApp(
          home: BackendSetupScreen(
            localDeploymentAvailable: true,
            onQuickConnect: (_) async =>
                'The launcher host could not be reached. Check the address.',
            onDeploymentReady: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    final input = find.byType(TextField).first;
    await tester.enterText(input, 'http://192.168.2.51:8090');
    await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('backend-setup-quick-connect-error')),
      findsOneWidget,
    );
    expect(find.textContaining('could not be reached'), findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'http://192.168.2.51:8090',
    );
  });
}
