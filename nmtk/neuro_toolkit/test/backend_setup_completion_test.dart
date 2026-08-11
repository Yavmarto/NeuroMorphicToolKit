import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/src/features/deployment/domain/deployment_state.dart';
import 'package:neuro_toolkit/src/features/deployment/presentation/deployment_notifier.dart';

class _FakeDeploymentNotifier extends BackendDeploymentNotifier {
  _FakeDeploymentNotifier(this.initialState);

  final DeploymentState initialState;

  static const _queuedJob = DeploymentJob(
    id: 'new-server-job',
    targetId: 'new-server',
    mode: 'standalone',
    stage: 'deploying',
    percent: 50,
    stageLabel: 'Deploying',
    logs: [],
  );
  static const _target = DeploymentTarget(
    id: 'new-server',
    displayName: 'New server',
    targetType: 'remote_host',
    mode: 'docker',
    authMode: 'ssh_key',
    host: '192.168.2.34',
    backendPort: 9000,
  );

  @override
  Future<DeploymentState> build() async => initialState;

  @override
  Future<DeploymentPreflightResult> preflight({
    required String targetType,
    required String mode,
    required String displayName,
    String host = '',
    String username = '',
    int sshPort = 22,
    String authMethod = 'ssh_key',
    String sshPassword = '',
    String sshPrivateKey = '',
    int backendPort = 9000,
    String namespace = '',
    String context = '',
    String apiServer = '',
    String containerEngine = 'docker',
    String kubeconfig = '',
  }) async =>
      const DeploymentPreflightResult(
        status: 'ok',
        message: 'Ready',
        blockingFindings: [],
        degradedFindings: [],
        suggestedRecovery: '',
      );

  @override
  Future<DeploymentJob> deploy({
    required String targetType,
    required String mode,
    required String displayName,
    String host = '',
    String username = '',
    int sshPort = 22,
    String authMethod = 'ssh_key',
    String sshPassword = '',
    String sshPrivateKey = '',
    int backendPort = 9000,
    String namespace = '',
    String context = '',
    String apiServer = '',
    String containerEngine = 'docker',
    String kubeconfig = '',
    bool cleanInstall = false,
  }) async {
    state = AsyncData(initialState.copyWith(
      targets: const [_target],
      activeJob: _queuedJob,
    ));
    return _queuedJob;
  }

  void completeDeployment() {
    state = AsyncData(
      initialState.copyWith(
        targets: const [_target],
        isReady: true,
        activeJob: DeploymentJob(
          id: _queuedJob.id,
          targetId: _queuedJob.targetId,
          mode: _queuedJob.mode,
          stage: 'completed',
          percent: 100,
          stageLabel: 'Deployed',
          logs: [],
        ),
      ),
    );
  }

  @override
  Future<DeploymentJob?> recoverActiveJob() async {
    final failedJob = state.value?.activeJob;
    if (failedJob == null) return null;
    final recovered = DeploymentJob(
      id: 'recovered-${failedJob.id}',
      targetId: failedJob.targetId,
      mode: failedJob.mode,
      stage: 'deploying',
      percent: 50,
      stageLabel: 'Recovering',
      logs: const [],
    );
    state = AsyncData(initialState.copyWith(activeJob: recovered));
    return recovered;
  }

  bool retryJupyterCalled = false;

  @override
  Future<void> retryJupyter() async {
    retryJupyterCalled = true;
    final failedJob = state.value?.activeJob;
    if (failedJob == null) return;
    state = AsyncData(
      initialState.copyWith(activeJob: failedJob.copyWith(error: '')),
    );
  }
}

Widget _buildHarness({
  required _FakeDeploymentNotifier notifier,
  required Future<void> Function(DeploymentTarget target) onDeploymentReady,
}) {
  return ProviderScope(
    overrides: [
      backendDeploymentProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      home: Scaffold(
        // BackendSetupForm is embedded inside BackendSetupScreen's
        // SingleChildScrollView in production; wrap it here too so this
        // harness doesn't overflow at narrower (e.g. phone) viewports where
        // the desktop-sized viewport used elsewhere in this file happened
        // to have enough height to avoid needing to scroll.
        body: SingleChildScrollView(
          child: BackendSetupForm(
            localDeploymentAvailable: true,
            onDeploymentReady: onDeploymentReady,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('existing ready deployment leaves setup form open',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = _FakeDeploymentNotifier(
      const DeploymentState(isReady: true),
    );
    var completionCount = 0;

    await tester.pumpWidget(
      _buildHarness(
        notifier: notifier,
        onDeploymentReady: (_) async => completionCount++,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(BackendSetupForm), findsOneWidget);
    expect(completionCount, 0);
  });

  testWidgets('current form completes once after its deployment becomes ready',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = _FakeDeploymentNotifier(const DeploymentState());
    var completionCount = 0;

    await tester.pumpWidget(
      _buildHarness(
        notifier: notifier,
        onDeploymentReady: (_) async => completionCount++,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.ensureVisible(find.byKey(const Key('backend-setup-validate')));
    await tester.tap(find.byKey(const Key('backend-setup-validate')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('backend-setup-deploy')));
    await tester.tap(find.byKey(const Key('backend-setup-deploy')));
    await tester.pump();
    expect(completionCount, 0);

    notifier.completeDeployment();
    await tester.pump();
    await tester.pump();

    expect(completionCount, 1);
  });

  testWidgets(
      'current form completes once after its deployment becomes ready '
      '(mobile viewport)', (tester) async {
    // Phone-sized viewport -- this flow has no mobile-specific rendering,
    // but nothing previously exercised BackendSetupForm below the desktop
    // 840-width shell breakpoint. Same assertions as the desktop-sized
    // test above, confirming parity rather than a new behavior.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = _FakeDeploymentNotifier(const DeploymentState());
    var completionCount = 0;

    await tester.pumpWidget(
      _buildHarness(
        notifier: notifier,
        onDeploymentReady: (_) async => completionCount++,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // At a phone height the deploy button sits below the fold; scroll it
    // into view before tapping, matching how a real user would reach it.
    await tester.ensureVisible(find.byKey(const Key('backend-setup-validate')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('backend-setup-validate')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('backend-setup-deploy')));
    await tester.tap(find.byKey(const Key('backend-setup-deploy')));
    await tester.pump();
    expect(completionCount, 0);

    notifier.completeDeployment();
    await tester.pump();
    await tester.pump();

    expect(completionCount, 1);
  });

  testWidgets('degraded Jupyter deployment offers saved-target recovery',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const target = DeploymentTarget(
      id: 'saved-remote-target',
      displayName: 'Saved remote target',
      targetType: 'remote_host',
      mode: 'docker',
      authMode: 'ssh_key',
      host: '192.168.2.34',
      backendPort: 9000,
    );
    final notifier = _FakeDeploymentNotifier(
      const DeploymentState(
        targets: [target],
        activeJob: DeploymentJob(
          id: 'jupyter-degraded',
          targetId: 'saved-remote-target',
          mode: 'docker',
          stage: 'failed',
          percent: 96,
          stageLabel: 'Verifying Jupyter notebook readiness',
          error: 'degraded optional capability: Jupyter is not ready',
          logs: [],
        ),
      ),
    );

    await tester.pumpWidget(
      _buildHarness(
        notifier: notifier,
        onDeploymentReady: (_) async {},
      ),
    );
    await tester.pump();

    expect(find.text('Recover Jupyter'), findsOneWidget);
    await tester.tap(find.text('Recover Jupyter'));
    await tester.pump();

    // Recovering Jupyter now calls the lightweight per-container retry, not
    // the old full-redeploy recoverActiveJob() path -- confirm that's what
    // actually ran, and that a successful retry clears the degraded flag so
    // the button doesn't linger once Jupyter is genuinely fixed.
    expect(notifier.retryJupyterCalled, isTrue);
    expect(notifier.state.value?.activeJob?.targetId, 'saved-remote-target');
    expect(notifier.state.value?.activeJob?.error, isEmpty);
  });

  testWidgets('degraded Akida update keeps backend ready and offers retry',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const target = DeploymentTarget(
      id: 'saved-remote-target',
      displayName: 'Saved remote target',
      targetType: 'remote_host',
      mode: 'docker',
      authMode: 'ssh_key',
      host: '192.168.2.34',
      backendPort: 9000,
    );
    final notifier = _FakeDeploymentNotifier(
      const DeploymentState(
        targets: [target],
        isReady: true,
        activeJob: DeploymentJob(
          id: 'akida-degraded',
          targetId: 'saved-remote-target',
          mode: 'docker',
          stage: 'completed',
          percent: 100,
          stageLabel: 'Backend and launcher control are ready',
          error: 'degraded optional capability: the selected Akida host is '
              'offline; core services are available.',
          logs: [],
        ),
      ),
    );

    await tester.pumpWidget(
      _buildHarness(
        notifier: notifier,
        onDeploymentReady: (_) async {},
      ),
    );
    await tester.pump();

    expect(find.text('Akida runtime needs recovery'), findsOneWidget);
    expect(find.text('Retry Akida update'), findsOneWidget);
    expect(notifier.state.value?.isReady, isTrue);
  });

  testWidgets(
      'a degraded Akida host raises the update banner without a failed job',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A host that installed cleanly, is on the current version, and has no
    // failed job — but landed on the simulator. "Retry Akida update" used to be
    // gated on a pending version or a deploy job whose error text matched
    // 'degraded optional capability:' + 'akida', so in this state there was no
    // way to reach it from the app at all.
    const simulatorOnlyHost = AkidaPairedHost(
      id: 'akida-1',
      displayName: 'Bench Akida',
      host: '192.168.68.53',
      sshPort: 22,
      username: 'moosebun2',
      runtimeApiUrl: 'http://192.168.68.53:8002',
      controlApiUrl: 'http://192.168.68.53:8091',
      authMode: AkidaHostAuthMode.password,
      credentialRef: '',
      password: '',
      hasPassword: true,
      sshKeyPath: '',
      remoteInstallRoot: '/opt/neurochip-akida-host',
      serviceUser: 'neurochip',
      hostOs: 'Ubuntu 24.04',
      pythonVersion: '3.11.9',
      runtimeMode: AkidaRuntimeMode.remoteSdk,
      state: AkidaPairedHostState.simulatorOnly,
      lastReadinessMessage:
          'No physical Akida device was enumerated on the host.',
      lastVerifiedAt: '2026-08-05T09:00:00Z',
      installedRuntimeVersion: '0.4.2',
      availableRuntimeVersion: '0.4.2',
    );

    final notifier = _FakeDeploymentNotifier(
      const DeploymentState(isReady: true),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendDeploymentProvider.overrideWith(() => notifier),
          backendUpdateProvider.overrideWith((ref) async => null),
          selectedAkidaRuntimeStatusProvider.overrideWith(
            (ref) async => simulatorOnlyHost,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BackendSetupForm(
                localDeploymentAvailable: true,
                onDeploymentReady: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byKey(const Key('backend-update-available')), findsOneWidget);
    expect(
      find.text(
        'Selected Akida runtime needs attention — Simulator Only',
      ),
      findsOneWidget,
      reason: 'A degraded host does not need "an update"; the title must say '
          'what is actually wrong.',
    );
    expect(
      find.textContaining(
        'No physical Akida device was enumerated on the host.',
      ),
      findsOneWidget,
      reason: 'lastReadinessMessage is the reason and must be shown, not just '
          'a generic "will be updated" line.',
    );
    expect(
      find.byKey(const Key('backend-update-retry-akida')),
      findsOneWidget,
    );
  });
}
