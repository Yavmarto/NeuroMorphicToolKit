import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';

const _readySettings = LauncherControlSettings(
  logLevel: 'info',
  mujocoAvailable: false,
  pythonAvailable: true,
  pynqBoards: [],
  akidaHosts: [],
  selectedAkidaHostId: null,
  backendDeploymentReady: true,
);

LauncherBootstrapData _readyAt(String url) {
  final baseUri = Uri.parse(url);
  return LauncherBootstrapData.ready(
    bootstrapState: LauncherBootstrapState.ready(baseUri),
    controlApiService: ControlApiService(baseUri: baseUri),
    launcherSettings: _readySettings,
  );
}

class _SwitchableBootstrapNotifier extends LauncherBootstrapNotifier {
  _SwitchableBootstrapNotifier(this.initial);

  final LauncherBootstrapData initial;

  @override
  Future<LauncherBootstrapData> build() async => initial;

  void select(LauncherBootstrapData selection) {
    state = AsyncData(selection);
  }
}

class _RepairService implements DeploymentService {
  _RepairService({this.repairThrows = false});

  int repairCalls = 0;
  final bool repairThrows;

  @override
  Future<DeploymentSnapshot> load() async => const DeploymentSnapshot(
        targets: [
          DeploymentTarget(
            id: 'target-1',
            displayName: 'Server',
            targetType: 'remote_host',
            mode: 'docker',
            authMode: 'ssh_key',
            backendPort: 9000,
            host: '192.168.2.90',
          ),
        ],
      );

  @override
  Future<SystemHealthReport> repairTarget(String targetId) async {
    repairCalls++;
    if (repairThrows) throw StateError('saved credential missing');
    return SystemHealthReport(
      overall: SystemHealthStatus.failed,
      checkedAt: DateTime.now(),
      checks: const [],
    );
  }

  @override
  Future<SystemHealthReport> diagnoseTarget(String targetId) =>
      repairTarget(targetId);

  @override
  Future<DeploymentJob> reinstallTarget(
    String targetId, {
    bool factoryReset = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<DeploymentJob> setupRemoteServer(RemoteServerSetupRequest request) =>
      throw UnimplementedError();

  @override
  Future<DeploymentJob> cancelJob(String jobId) => throw UnimplementedError();

  @override
  Future<DeploymentJob> deploy(DeploymentRequest request) =>
      throw UnimplementedError();

  @override
  Future<DeploymentJob> fetchJob(String jobId) => throw UnimplementedError();

  @override
  Future<DeploymentPreflightResult> preflight(DeploymentRequest request) =>
      throw UnimplementedError();

  @override
  Future<DeploymentJob?> retryJob(String jobId) => throw UnimplementedError();

  @override
  Future<void> retryJupyter(String targetId) => throw UnimplementedError();

  @override
  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> forgetHostKey({required String host, required int sshPort}) =>
      throw UnimplementedError();
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('health state becomes unstable, disconnected, then recovers', () async {
    final responses = Queue<bool>.from([true, false, false, false, true]);
    final repairService = _RepairService();
    final container = ProviderContainer(
      overrides: [
        launcherBootstrapProvider.overrideWith(
          () => _SwitchableBootstrapNotifier(
            _readyAt('http://192.168.2.90:8090'),
          ),
        ),
        serverHealthProbeProvider.overrideWithValue(
          (_) async => responses.removeFirst(),
        ),
        deploymentServiceProvider.overrideWithValue(repairService),
      ],
    );
    addTearDown(container.dispose);

    container.listen(serverConnectionProvider, (_, __) {});
    await _flushMicrotasks();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.connected,
    );

    final notifier = container.read(serverConnectionProvider.notifier);
    await notifier.checkNow();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.unstable,
    );
    await notifier.checkNow();
    expect(
      container.read(serverConnectionProvider).consecutiveFailures,
      2,
    );
    await notifier.checkNow();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.disconnected,
    );
    await _flushMicrotasks();
    expect(repairService.repairCalls, 1);
    final recovered = container.read(serverConnectionProvider);
    expect(recovered.phase, ServerConnectionPhase.connected);
    expect(recovered.consecutiveFailures, 0);
  });

  test('automatic repair runs only once during one outage', () async {
    final repairService = _RepairService();
    final container = ProviderContainer(
      overrides: [
        launcherBootstrapProvider.overrideWith(
          () => _SwitchableBootstrapNotifier(
            _readyAt('http://192.168.2.90:8090'),
          ),
        ),
        serverHealthProbeProvider.overrideWithValue((_) async => false),
        deploymentServiceProvider.overrideWithValue(repairService),
      ],
    );
    addTearDown(container.dispose);

    container.listen(serverConnectionProvider, (_, __) {});
    await _flushMicrotasks();
    final notifier = container.read(serverConnectionProvider.notifier);
    for (var attempt = 0; attempt < 6; attempt++) {
      await notifier.checkNow();
    }
    await _flushMicrotasks();

    expect(repairService.repairCalls, 1);
  });

  test('missing repair credential does not create a repair loop', () async {
    final repairService = _RepairService(repairThrows: true);
    final container = ProviderContainer(
      overrides: [
        launcherBootstrapProvider.overrideWith(
          () => _SwitchableBootstrapNotifier(
            _readyAt('http://192.168.2.90:8090'),
          ),
        ),
        serverHealthProbeProvider.overrideWithValue((_) async => false),
        deploymentServiceProvider.overrideWithValue(repairService),
      ],
    );
    addTearDown(container.dispose);

    container.listen(serverConnectionProvider, (_, __) {});
    await _flushMicrotasks();
    final notifier = container.read(serverConnectionProvider.notifier);
    for (var attempt = 0; attempt < 6; attempt++) {
      await notifier.checkNow();
    }
    await _flushMicrotasks();

    expect(repairService.repairCalls, 1);
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.disconnected,
    );
  });

  test('late health response from the previous server is ignored', () async {
    final oldServerProbe = Completer<bool>();
    final bootstrap = _SwitchableBootstrapNotifier(
      _readyAt('http://192.168.2.90:8090'),
    );
    final container = ProviderContainer(
      overrides: [
        launcherBootstrapProvider.overrideWith(() => bootstrap),
        serverHealthProbeProvider.overrideWithValue((controlApi) {
          if (controlApi.baseUri.host == '192.168.2.90') {
            return oldServerProbe.future;
          }
          return Future<bool>.value(true);
        }),
      ],
    );
    addTearDown(container.dispose);

    container.listen(serverConnectionProvider, (_, __) {});
    await _flushMicrotasks();

    bootstrap.select(_readyAt('http://192.168.2.34:8090'));
    await _flushMicrotasks();
    var state = container.read(serverConnectionProvider);
    expect(state.baseUri?.host, '192.168.2.34');
    expect(state.phase, ServerConnectionPhase.connected);

    oldServerProbe.complete(false);
    await _flushMicrotasks();
    state = container.read(serverConnectionProvider);
    expect(state.baseUri?.host, '192.168.2.34');
    expect(state.phase, ServerConnectionPhase.connected);
  });
}
