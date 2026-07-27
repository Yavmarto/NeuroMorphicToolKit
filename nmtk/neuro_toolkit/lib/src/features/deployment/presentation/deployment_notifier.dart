import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/src/features/deployment/domain/deployment_state.dart';

part 'deployment_notifier.g.dart';

@riverpod
class BackendDeploymentNotifier extends _$BackendDeploymentNotifier {
  static const _maxConsecutivePollFailures = 3;
  static const _maxJobStaleness = Duration(minutes: 30);

  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _consecutivePollFailures = 0;

  DeploymentService get _service => ref.read(deploymentServiceProvider);

  @override
  Future<DeploymentState> build() async {
    final snapshot = await ref.watch(deploymentServiceProvider).load();
    ref.onDispose(() => _pollTimer?.cancel());
    if (snapshot.activeJob != null && !snapshot.activeJob!.isTerminal) {
      unawaited(Future<void>.microtask(_startPolling));
    }
    return _stateFromSnapshot(snapshot);
  }

  Future<void> refresh() async {
    try {
      final snapshot = await _service.load();
      state = AsyncData(_stateFromSnapshot(snapshot));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

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
  }) {
    return _service.preflight(
      _request(
        targetType: targetType,
        mode: mode,
        displayName: displayName,
        host: host,
        username: username,
        sshPort: sshPort,
        authMethod: authMethod,
        sshPassword: sshPassword,
        sshPrivateKey: sshPrivateKey,
        backendPort: backendPort,
        namespace: namespace,
        context: context,
        apiServer: apiServer,
        containerEngine: containerEngine,
        kubeconfig: kubeconfig,
      ),
    );
  }

  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    String rootPassword = '',
    String rootPrivateKey = '',
    String containerEngine = 'docker',
  }) {
    return _service.bootstrapRemoteUser(
      host: host,
      sshPort: sshPort,
      rootUsername: rootUsername,
      rootPassword: rootPassword,
      rootPrivateKey: rootPrivateKey,
      containerEngine: containerEngine,
    );
  }

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
    final job = await _service.deploy(
      _request(
        targetType: targetType,
        mode: mode,
        displayName: displayName,
        host: host,
        username: username,
        sshPort: sshPort,
        authMethod: authMethod,
        sshPassword: sshPassword,
        sshPrivateKey: sshPrivateKey,
        backendPort: backendPort,
        namespace: namespace,
        context: context,
        apiServer: apiServer,
        containerEngine: containerEngine,
        kubeconfig: kubeconfig,
        cleanInstall: cleanInstall,
      ),
    );
    final current = state.value ?? const DeploymentState();
    state = AsyncData(
      current.copyWith(activeJob: job, connectionLostReason: null),
    );
    _startPolling();
    return job;
  }

  Future<void> cancelActiveJob() async {
    final current = state.value;
    final job = current?.activeJob;
    if (current == null || job == null) return;
    final updated = await _service.cancelJob(job.id);
    state = AsyncData(current.copyWith(activeJob: updated));
  }

  Future<DeploymentJob?> recoverActiveJob() async {
    final current = state.value;
    final job = current?.activeJob;
    if (current == null || job == null || !job.isTerminal) return null;
    final retried = await _service.retryJob(job.id);
    if (retried == null) return null;
    state = AsyncData(
      current.copyWith(activeJob: retried, connectionLostReason: null),
    );
    _startPolling();
    return retried;
  }

  /// Restarts just the Jupyter container for the current target, without
  /// redeploying the rest of the backend. Unlike [recoverActiveJob], this
  /// works from anywhere in the app, not only while the setup screen's job
  /// is still in view.
  Future<void> retryJupyter() async {
    final current = state.value;
    if (current == null) return;
    final target = _targetForRetry(current);
    if (target == null) return;
    try {
      await _service.retryJupyter(target.id);
      await refresh();
    } catch (error) {
      final job = current.activeJob;
      if (job == null) return;
      // Keep the "degraded optional capability: Jupyter" prefix so the
      // existing Recover-Jupyter affordance (gated on that exact prefix)
      // stays visible for another attempt instead of disappearing on
      // failure.
      state = AsyncData(
        current.copyWith(
          activeJob: job.copyWith(
            error: 'degraded optional capability: Jupyter restart failed: '
                '$error',
          ),
        ),
      );
    }
  }

  DeploymentTarget? _targetForRetry(DeploymentState current) {
    final job = current.activeJob;
    if (job != null) {
      for (final candidate in current.targets) {
        if (candidate.id == job.targetId) return candidate;
      }
    }
    if (current.targets.isEmpty) return null;
    var mostRecent = current.targets.first;
    for (final candidate in current.targets.skip(1)) {
      final currentUpdatedAt = mostRecent.updatedAt;
      final candidateUpdatedAt = candidate.updatedAt;
      if (candidateUpdatedAt != null &&
          (currentUpdatedAt == null ||
              candidateUpdatedAt.isAfter(currentUpdatedAt))) {
        mostRecent = candidate;
      }
    }
    return mostRecent;
  }

  DeploymentRequest _request({
    required String targetType,
    required String mode,
    required String displayName,
    required String host,
    required String username,
    required int sshPort,
    required String authMethod,
    required String sshPassword,
    required String sshPrivateKey,
    required int backendPort,
    required String namespace,
    required String context,
    required String apiServer,
    required String containerEngine,
    required String kubeconfig,
    bool cleanInstall = false,
  }) {
    return DeploymentRequest(
      targetType: targetType,
      mode: mode,
      displayName: displayName,
      host: host,
      username: username,
      sshPort: sshPort,
      authMethod: authMethod,
      sshPassword: sshPassword,
      sshPrivateKey: sshPrivateKey,
      backendPort: backendPort,
      namespace: namespace,
      context: context,
      apiServer: apiServer,
      containerEngine: containerEngine,
      kubeconfig: kubeconfig,
      cleanInstall: cleanInstall,
    );
  }

  DeploymentState _stateFromSnapshot(DeploymentSnapshot snapshot) {
    return DeploymentState(
      targets: snapshot.targets,
      activeJob: snapshot.activeJob,
      isReady: snapshot.isReady,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _consecutivePollFailures = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), _pollTick);
    unawaited(_pollTick(_pollTimer!));
  }

  Future<void> _pollTick(Timer timer) async {
    final current = state.value;
    final job = current?.activeJob;
    if (current == null || job == null) {
      timer.cancel();
      return;
    }
    final updatedAt = job.updatedAt;
    if (updatedAt != null &&
        DateTime.now().difference(updatedAt) > _maxJobStaleness) {
      timer.cancel();
      state = AsyncData(
        current.copyWith(
          connectionLostReason:
              'This deployment has not reported progress for 30 minutes. '
              'Reopen setup to inspect and recover it.',
        ),
      );
      return;
    }
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final updated = await _service.fetchJob(job.id);
      _consecutivePollFailures = 0;
      final snapshot = await _service.load();
      state = AsyncData(
        DeploymentState(
          targets: snapshot.targets,
          activeJob: updated,
          isReady: updated.stage == DeploymentPhase.completed.wireName,
        ),
      );
      if (updated.isTerminal) timer.cancel();
    } catch (_) {
      _consecutivePollFailures++;
      if (_consecutivePollFailures >= _maxConsecutivePollFailures) {
        timer.cancel();
        state = AsyncData(
          current.copyWith(
            connectionLostReason:
                'The client could not inspect the deployment after three '
                'attempts. The detached server job may still be running.',
          ),
        );
      }
    } finally {
      _pollInFlight = false;
    }
  }
}
