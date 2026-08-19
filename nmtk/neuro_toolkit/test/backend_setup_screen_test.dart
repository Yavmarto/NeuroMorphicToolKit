import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/update_service.dart';

class _FakeDeploymentService implements DeploymentService {
  _FakeDeploymentService({
    this.preflightResult = const DeploymentPreflightResult(
      status: 'ok',
      message: 'ready',
      blockingFindings: [],
      degradedFindings: [],
      suggestedRecovery: '',
    ),
    this.snapshot = const DeploymentSnapshot(),
    this.doctorReport,
    this.reinstallThrows = false,
  });

  final DeploymentPreflightResult preflightResult;
  final DeploymentSnapshot snapshot;
  final SystemHealthReport? doctorReport;
  final bool reinstallThrows;
  int deployCalls = 0;
  DeploymentRequest? lastDeployRequest;
  int setupCalls = 0;
  RemoteServerSetupRequest? lastSetupRequest;
  final List<String> cancelledJobIds = <String>[];
  int diagnoseCalls = 0;
  int repairCalls = 0;
  int reinstallCalls = 0;
  bool? lastFactoryReset;

  @override
  Future<DeploymentSnapshot> load() async => snapshot;

  @override
  Future<DeploymentPreflightResult> preflight(
    DeploymentRequest request,
  ) async {
    return preflightResult;
  }

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) async {
    deployCalls++;
    lastDeployRequest = request;
    return const DeploymentJob(
      id: 'deploy-job',
      targetId: 'target',
      mode: 'docker',
      stage: 'queued',
      percent: 0,
      stageLabel: 'Queued',
      logs: [],
    );
  }

  @override
  Future<DeploymentJob> setupRemoteServer(
    RemoteServerSetupRequest request,
  ) async {
    setupCalls++;
    lastSetupRequest = request;
    return const DeploymentJob(
      id: 'remote-setup-job',
      targetId: 'remote-192-168-2-34',
      mode: 'docker',
      stage: 'queued',
      percent: 0,
      stageLabel: 'Queued',
      logs: [],
    );
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
  Future<DeploymentJob> cancelJob(String jobId) async {
    cancelledJobIds.add(jobId);
    final activeJob = snapshot.activeJob;
    if (activeJob == null || activeJob.id != jobId) {
      throw StateError('Job $jobId was not found.');
    }
    return activeJob.copyWith(stage: 'cancelled');
  }

  @override
  Future<DeploymentJob> fetchJob(String jobId) async {
    final activeJob = snapshot.activeJob;
    if (activeJob != null && activeJob.id == jobId) return activeJob;
    throw StateError('Job $jobId was not found.');
  }

  @override
  Future<DeploymentJob?> retryJob(String jobId) {
    throw UnimplementedError();
  }

  @override
  Future<void> retryJupyter(String targetId) {
    throw UnimplementedError();
  }

  @override
  Future<SystemHealthReport> diagnoseTarget(String targetId) async {
    diagnoseCalls++;
    return doctorReport ??
        SystemHealthReport(
          overall: SystemHealthStatus.ok,
          checkedAt: DateTime(2026, 8, 13, 12),
          checks: const [
            SystemHealthCheck(
              id: 'suite-api',
              label: 'Suite API',
              status: SystemHealthStatus.ok,
              detail: 'Ready',
            ),
          ],
        );
  }

  @override
  Future<SystemHealthReport> repairTarget(String targetId) async {
    repairCalls++;
    return diagnoseTarget(targetId);
  }

  @override
  Future<DeploymentJob> reinstallTarget(
    String targetId, {
    bool factoryReset = false,
  }) async {
    reinstallCalls++;
    lastFactoryReset = factoryReset;
    if (reinstallThrows && !factoryReset) {
      throw StateError('Data-preserving reinstall failed.');
    }
    return DeploymentJob(
      id: 'reinstall-job-$reinstallCalls',
      targetId: targetId,
      mode: 'docker',
      stage: 'queued',
      percent: 0,
      stageLabel: 'Queued',
      logs: const [],
    );
  }

  final List<String> forgottenHostKeys = <String>[];

  @override
  Future<void> forgetHostKey({
    required String host,
    required int sshPort,
  }) async {
    forgottenHostKeys.add('$host:$sshPort');
  }
}

const _savedTarget = DeploymentTarget(
  id: 'target',
  displayName: 'Lab server',
  targetType: 'remote_host',
  mode: 'docker',
  authMode: 'ssh_key',
  backendPort: 9000,
  host: '192.168.2.90',
);

Widget _harness({
  bool? localDeploymentAvailable,
  _FakeDeploymentService? deploymentService,
  String? backendVersion,
  LauncherUpdate? backendUpdate,
  AkidaPairedHost? selectedAkidaHost,
}) {
  return ProviderScope(
    overrides: [
      deploymentServiceProvider.overrideWithValue(
        deploymentService ?? _FakeDeploymentService(),
      ),
      backendVersionProvider.overrideWith((_) async => backendVersion),
      backendUpdateProvider.overrideWith((_) async => backendUpdate),
      selectedAkidaRuntimeStatusProvider.overrideWith(
        (_) async => selectedAkidaHost,
      ),
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
  testWidgets('System Health checks all configured services automatically',
      (tester) async {
    final service = _FakeDeploymentService(
      snapshot: const DeploymentSnapshot(targets: [_savedTarget]),
      doctorReport: SystemHealthReport(
        overall: SystemHealthStatus.ok,
        checkedAt: DateTime(2026, 8, 13, 12),
        checks: const [
          SystemHealthCheck(
            id: 'framework-snntorch',
            label: 'snnTorch',
            status: SystemHealthStatus.ok,
            detail: 'Kernel starts and imports snnTorch.',
          ),
          SystemHealthCheck(
            id: 'akida-runtime',
            label: 'Akida runtime',
            status: SystemHealthStatus.notConfigured,
            detail: 'No Akida runtime is configured.',
            required: false,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_harness(deploymentService: service));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend-system-health-card')), findsOneWidget);
    expect(find.text('Everything configured is working'), findsOneWidget);
    expect(find.text('snnTorch'), findsOneWidget);
    expect(find.text('Akida runtime'), findsOneWidget);
    expect(service.diagnoseCalls, 1);
  });

  testWidgets('failed health offers repair before reinstall', (tester) async {
    final service = _FakeDeploymentService(
      snapshot: const DeploymentSnapshot(targets: [_savedTarget]),
      doctorReport: SystemHealthReport(
        overall: SystemHealthStatus.failed,
        checkedAt: DateTime(2026, 8, 13, 12),
        checks: const [
          SystemHealthCheck(
            id: 'suite-api',
            label: 'NMTK backend',
            status: SystemHealthStatus.failed,
            detail: 'Offline',
            repairable: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(_harness(deploymentService: service));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('backend-system-health-repair')), findsOneWidget);
    expect(
      find.byKey(const Key('backend-system-health-reinstall')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('backend-system-health-repair')));
    await tester.pumpAndSettle();

    expect(service.repairCalls, 1);
    expect(
      find.byKey(const Key('backend-system-health-reinstall')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('backend-system-health-factory-reset')),
      findsNothing,
    );
  });
  testWidgets('setup opens the deployment form without launcher connection UI',
      (tester) async {
    await tester.pumpWidget(_harness(localDeploymentAvailable: true));
    await tester.pump();

    expect(find.text('Set up your backend'), findsOneWidget);
    expect(find.byType(BackendSetupForm), findsOneWidget);
    expect(find.text('Connect to server'), findsOneWidget);
    expect(find.text('Set up new server'), findsOneWidget);
    expect(find.text('Server address'), findsNothing);
    expect(find.text('Save & Retry'), findsNothing);
    expect(find.text('Step 1 — Python'), findsNothing);
  });

  testWidgets('no update banner when the backend has nothing to update to',
      (tester) async {
    await tester.pumpWidget(_harness(localDeploymentAvailable: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend-update-available')), findsNothing);
  });

  testWidgets('stale selected Akida runtime keeps retry banner visible',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        localDeploymentAvailable: true,
        selectedAkidaHost: const AkidaPairedHost(
          id: 'host-1',
          displayName: 'Lab Akida',
          host: '192.168.2.90',
          sshPort: 22,
          username: 'moosebun2',
          runtimeApiUrl: 'http://192.168.2.90:8002',
          controlApiUrl: 'http://192.168.2.90:8091',
          authMode: AkidaHostAuthMode.sshKey,
          credentialRef: '',
          password: '',
          hasPassword: false,
          sshKeyPath: '',
          remoteInstallRoot: '/opt/neurochip-akida-host',
          serviceUser: 'neurochip',
          hostOs: 'linux',
          pythonVersion: '3.11',
          runtimeMode: AkidaRuntimeMode.remoteSdk,
          state: AkidaPairedHostState.ready,
          lastReadinessMessage: 'Ready',
          lastVerifiedAt: '',
          installedRuntimeVersion: '0.5.0',
          availableRuntimeVersion: '0.6.0',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend-update-available')), findsOneWidget);
    expect(find.text('Selected Akida runtime needs an update'), findsOneWidget);
    expect(find.byKey(const Key('backend-update-retry-akida')), findsOneWidget);
  });

  testWidgets('keeps backend version out of the setup form', (tester) async {
    await tester.pumpWidget(_harness(
      localDeploymentAvailable: true,
      backendVersion: '1.2.0',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend-version')), findsNothing);
    expect(find.text('Backend version: 1.2.0'), findsNothing);
  });

  testWidgets('an available backend release offers a one-tap update',
      (tester) async {
    final service = _FakeDeploymentService();
    await tester.pumpWidget(_harness(
      localDeploymentAvailable: true,
      deploymentService: service,
      backendUpdate: LauncherUpdate(
        version: '1.2.0',
        url: 'https://example.invalid/v1.2.0',
        releaseNotes: 'notes',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backend-update-available')), findsOneWidget);
    expect(
      find.text('Backend update available — 1.2.0'),
      findsOneWidget,
    );

    final action = find.byKey(const Key('backend-update-action'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    // Validates and deploys in one tap — no separate "Validate server" press.
    expect(service.deployCalls, 1);
  });

  testWidgets('updating never wipes volumes', (tester) async {
    // The whole difference between an update and a clean install: `down -v`
    // would take the user's workspaces and notebooks with it.
    final service = _FakeDeploymentService();
    await tester.pumpWidget(_harness(
      localDeploymentAvailable: true,
      deploymentService: service,
      backendUpdate: LauncherUpdate(
        version: '1.2.0',
        url: 'https://example.invalid/v1.2.0',
        releaseNotes: 'notes',
      ),
    ));
    await tester.pumpAndSettle();

    final cleanInstallToggle = find.byType(SwitchListTile);
    if (cleanInstallToggle.evaluate().isNotEmpty) {
      await tester.ensureVisible(cleanInstallToggle.first);
      await tester.tap(cleanInstallToggle.first);
      await tester.pumpAndSettle();
    }

    final action = find.byKey(const Key('backend-update-action'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(service.lastDeployRequest, isNotNull);
    expect(service.lastDeployRequest!.cleanInstall, isFalse);
  });

  testWidgets('deployment stays locked until the current setup validates',
      (tester) async {
    final service = _FakeDeploymentService();
    await tester.pumpWidget(
      _harness(localDeploymentAvailable: true, deploymentService: service),
    );
    await tester.pump();

    final deploy = find.byKey(const Key('backend-setup-deploy'));
    expect(tester.widget<ZetaButton>(deploy).onPressed, isNull);
    expect(
      find.textContaining('Validate the current configuration'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('backend-setup-validate')),
    );
    await tester.tap(find.byKey(const Key('backend-setup-validate')));
    await tester.pumpAndSettle();

    expect(find.text('Ready to deploy'), findsOneWidget);
    expect(tester.widget<ZetaButton>(deploy).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).at(1), 'Renamed backend');
    await tester.pump();
    await tester.pump();

    expect(tester.widget<ZetaButton>(deploy).onPressed, isNull);
    expect(
      find.textContaining('Validate the current configuration'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('backend-setup-validate')),
    );
    await tester.tap(find.byKey(const Key('backend-setup-validate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(deploy);
    await tester.tap(deploy);
    await tester.pumpAndSettle();

    expect(service.deployCalls, 1);
  });

  testWidgets('failed validation keeps deployment locked with recovery copy',
      (tester) async {
    final service = _FakeDeploymentService(
      preflightResult: const DeploymentPreflightResult(
        status: 'failed',
        message: 'SSH authentication failed.',
        blockingFindings: ['Check the SSH username and credentials.'],
        degradedFindings: [],
        suggestedRecovery: 'Update the credentials and validate again.',
      ),
    );
    await tester.pumpWidget(
      _harness(localDeploymentAvailable: true, deploymentService: service),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('backend-setup-validate')),
    );
    await tester.tap(find.byKey(const Key('backend-setup-validate')));
    await tester.pumpAndSettle();

    expect(find.text('Validation failed'), findsOneWidget);
    expect(
      find.text('Deployment remains locked until validation passes.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ZetaButton>(
            find.byKey(const Key('backend-setup-deploy')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('optional validation warnings still allow deployment',
      (tester) async {
    final service = _FakeDeploymentService(
      preflightResult: const DeploymentPreflightResult(
        status: 'ok',
        message: 'The server can run the backend.',
        blockingFindings: [],
        degradedFindings: ['Docker will be installed automatically.'],
        suggestedRecovery: 'Review the optional warning, then continue.',
      ),
    );
    await tester.pumpWidget(
      _harness(localDeploymentAvailable: true, deploymentService: service),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('backend-setup-validate')),
    );
    await tester.tap(find.byKey(const Key('backend-setup-validate')));
    await tester.pumpAndSettle();

    expect(
      find.text('Ready to deploy with optional capability warnings'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ZetaButton>(
            find.byKey(const Key('backend-setup-deploy')),
          )
          .onPressed,
      isNotNull,
    );
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
    expect(find.text('Standalone'), findsNothing);
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Podman'), findsOneWidget);
  });

  testWidgets('remote setup uses one action with ephemeral administrator input',
      (tester) async {
    final service = _FakeDeploymentService();
    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '192.168.2.34');
    await tester.enterText(fields.at(3), 'temporary-admin-secret');
    final setupButton =
        find.byKey(const Key('backend-setup-set-up-and-connect'));
    await tester.ensureVisible(setupButton);
    await tester.tap(setupButton);
    await tester.pumpAndSettle();

    expect(service.setupCalls, 1);
    expect(service.lastSetupRequest?.host, '192.168.2.34');
    expect(service.lastSetupRequest?.adminUsername, 'root');
    expect(service.lastSetupRequest?.adminPassword, 'temporary-admin-secret');
    expect(service.lastSetupRequest?.containerEngine, 'docker');
    expect(
      service.lastSetupRequest?.reinstallMode,
      RemoteReinstallMode.preserveData,
    );
  });

  testWidgets('factory reset appears only after safe recovery paths fail',
      (tester) async {
    final service = _FakeDeploymentService(
      snapshot: const DeploymentSnapshot(targets: [_savedTarget]),
      reinstallThrows: true,
      doctorReport: SystemHealthReport(
        overall: SystemHealthStatus.failed,
        checkedAt: DateTime(2026, 8, 13, 12),
        checks: const [
          SystemHealthCheck(
            id: 'suite-api',
            label: 'NMTK backend',
            status: SystemHealthStatus.failed,
            detail: 'Offline',
            repairable: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('backend-system-health-factory-reset')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('backend-system-health-repair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backend-system-health-reinstall')));
    await tester.pumpAndSettle();

    final resetButton =
        find.byKey(const Key('backend-system-health-factory-reset'));
    expect(resetButton, findsOneWidget);
    expect(tester.widget<ZetaButton>(resetButton).onPressed, isNull);
    await tester.enterText(
      find.descendant(
        of: find.byKey(
          const Key('backend-system-health-reset-confirmation'),
        ),
        matching: find.byType(TextField),
      ),
      'RESET',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ZetaButton>(resetButton).onPressed, isNotNull);
    await tester.tap(resetButton);
    await tester.pump();

    expect(service.lastFactoryReset, isTrue);
  });

  testWidgets(
      'failed setup explains the cause and keeps prior connection contextual',
      (tester) async {
    MethodCall? clipboardCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const job = DeploymentJob(
      id: 'failed-setup',
      targetId: 'remote-192-168-2-34',
      mode: 'docker',
      stage: 'failed',
      percent: 100,
      stageLabel: 'Podman installations could not be inspected',
      logs: <String>[
        'Checking administrator access',
        'Removing existing NMTK containers',
      ],
      terminalOutput: <String>[
        r'$ podman info (user: deploy)',
        '✗ podman info failed (exit 125)',
        '  cannot connect to Podman socket',
      ],
      failureDetails: DeploymentFailureDetails(
        code: 'podman_inspection_failed',
        phase: 'reconciling_existing_install',
        summary: 'Podman installations could not be inspected',
        recovery: 'Ensure Podman is available for each server user and retry.',
        technicalDetails: 'podman info returned exit status 125',
        exitCode: 29,
        existingConnectionReachable: true,
      ),
    );
    final service = _FakeDeploymentService(
      snapshot: const DeploymentSnapshot(
        activeJob: job,
        isReady: true,
      ),
    );

    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pump();

    expect(
      find.text('Podman installations could not be inspected'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The reinstall failed, but the existing server is still connected.',
      ),
      findsOneWidget,
    );
    expect(find.text('Deployed'), findsNothing);

    final details =
        find.byKey(const Key('deployment-view-details-failed-setup'));
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();

    expect(find.text('Raw SSH output — 192.168.2.34'), findsOneWidget);
    expect(
      find.textContaining('cannot connect to Podman socket'),
      findsOneWidget,
    );
    expect(find.text('Copy output'), findsOneWidget);
    await tester.tap(find.text('Copy output'));
    await tester.pumpAndSettle();
    expect(
      clipboardCall?.arguments.toString(),
      contains(r'$ podman info (user: deploy)'),
    );
  });

  testWidgets(
      'active setup shows simple progress while raw commands stay hidden',
      (tester) async {
    final job = DeploymentJob(
      id: 'active-setup',
      targetId: 'remote-192-168-2-34',
      mode: 'podman',
      stage: 'bootstrapping_access',
      percent: 17,
      stageLabel: 'Preparing the NMTK deployment account',
      logs: const ['Preparing the NMTK deployment account'],
      terminalOutput: const [
        r'$ systemctl --user enable podman.socket',
        'Created symlink podman.socket',
      ],
      updatedAt: DateTime.now().subtract(const Duration(seconds: 4)),
      activeOperation: DeploymentActiveOperation(
        label: 'Verifying rootless Podman API',
        startedAt: DateTime.now().subtract(const Duration(seconds: 7)),
        timeoutSeconds: 20,
        automaticRecovery: true,
      ),
    );
    final service = _FakeDeploymentService(
      snapshot: DeploymentSnapshot(activeJob: job),
    );

    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pump();

    final progress = find.textContaining(
      'Automatic recovery · Verifying rootless Podman API',
    );
    expect(progress, findsOneWidget);
    final firstText = tester.widget<Text>(progress).data!;
    final firstElapsed =
        int.parse(RegExp(r'(\d+)s elapsed').firstMatch(firstText)!.group(1)!);
    final laterText = BackendSetupForm.operationProgressLabelForTesting(
      job.activeOperation!,
      job.activeOperation!.startedAt.add(const Duration(seconds: 9)),
    );
    final laterElapsed =
        int.parse(RegExp(r'(\d+)s elapsed').firstMatch(laterText)!.group(1)!);
    expect(laterElapsed, greaterThan(firstElapsed));
    expect(laterText, endsWith('up to 20s'));
    expect(
      BackendSetupForm.operationProgressLabelForTesting(
        job.activeOperation!,
        job.activeOperation!.startedAt.add(const Duration(seconds: 20)),
      ),
      'Automatic recovery · Verifying rootless Podman API · '
      'timeout reached · stopping safely',
    );
    expect(
      find.text(r'$ systemctl --user enable podman.socket'),
      findsNothing,
    );
    expect(find.text('View raw SSH output'), findsOneWidget);
  });

  testWidgets('a setup that stopped reporting says so instead of showing 17%',
      (tester) async {
    // The reported bug: the job sat at 17% with a live progress bar forever.
    // A job whose last real progress is older than the staleness budget must
    // read as stopped, and must offer a way out.
    final job = DeploymentJob(
      id: 'stalled-setup',
      targetId: 'remote-192-168-2-34',
      mode: 'podman',
      stage: 'bootstrapping_access',
      percent: 17,
      stageLabel: 'Preparing the NMTK deployment account',
      logs: const ['Preparing the NMTK deployment account'],
      updatedAt: DateTime.now(),
      lastProgressAt: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    final service = _FakeDeploymentService(
      snapshot: DeploymentSnapshot(activeJob: job),
    );

    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Server setup stopped responding at 17%'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('deployment-stalled-reason-stalled-setup')),
      findsOneWidget,
    );
    expect(
      find.text('17% — Preparing the NMTK deployment account'),
      findsNothing,
    );
    expect(find.text('Last step: Preparing the NMTK deployment account'),
        findsOneWidget);
    expect(find.text('View raw SSH output'), findsOneWidget);
    expect(find.byKey(const Key('backend-setup-retry')), findsOneWidget);
  });

  testWidgets(
      'retrying a stalled setup re-asks only for the administrator '
      'credential', (tester) async {
    final job = DeploymentJob(
      id: 'stalled-setup',
      targetId: 'remote-192-168-2-34',
      mode: 'podman',
      stage: 'bootstrapping_access',
      percent: 17,
      stageLabel: 'Preparing the NMTK deployment account',
      logs: const [],
      updatedAt: DateTime.now(),
      lastProgressAt: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    final service = _FakeDeploymentService(
      snapshot: DeploymentSnapshot(activeJob: job),
    );

    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pump();
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '192.168.2.34');
    await tester.pump();

    final retry = find.byKey(const Key('backend-setup-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    // The administrator credential is never persisted, so retrying has to ask
    // for it — but it must say that instead of failing silently.
    expect(service.setupCalls, 0);
    expect(
      find.textContaining('Enter the administrator password again to retry'),
      findsOneWidget,
    );

    await tester.enterText(fields.at(3), 'temporary-admin-secret');
    await tester.pump();
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(service.setupCalls, 1);
    expect(service.cancelledJobIds, const <String>['stalled-setup']);
    expect(service.lastSetupRequest?.host, '192.168.2.34');
    expect(service.lastSetupRequest?.adminPassword, 'temporary-admin-secret');
    expect(
      service.lastSetupRequest?.reinstallMode,
      RemoteReinstallMode.preserveData,
    );
  });

  testWidgets(
      'new remote setup offers factory reset but never triggers it unasked',
      (tester) async {
    final service = _FakeDeploymentService();
    await tester.pumpWidget(
      _harness(localDeploymentAvailable: false, deploymentService: service),
    );
    await tester.pump();

    expect(find.text('Factory reset server data'), findsOneWidget);
    expect(find.text('Erase and reinstall'), findsNothing);
    expect(service.setupCalls, 0);
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

    expect(find.text('Connect to server'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      '192.168.2.90',
    );
    await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
    await tester.pumpAndSettle();

    expect(connected, isNotNull);
    expect(connected!.host, '192.168.2.90');
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
    await tester.enterText(input, '192.168.2.90');
    await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('backend-setup-quick-connect-error')),
      findsOneWidget,
    );
    expect(find.textContaining('could not be reached'), findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller!.text,
      '192.168.2.90',
    );
  });

  testWidgets('quick connect rejects URLs and hostnames before connecting',
      (tester) async {
    var callbackCalled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deploymentServiceProvider.overrideWithValue(_FakeDeploymentService()),
        ],
        child: MaterialApp(
          home: BackendSetupScreen(
            localDeploymentAvailable: true,
            onQuickConnect: (_) async {
              callbackCalled = true;
              return null;
            },
            onDeploymentReady: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(TextField).first,
      'http://192.168.2.90:8090',
    );
    await tester.tap(find.byKey(const Key('backend-setup-quick-connect')));
    await tester.pumpAndSettle();

    expect(callbackCalled, isFalse);
    expect(find.textContaining('Enter an IPv4 address'), findsOneWidget);
  });
}
