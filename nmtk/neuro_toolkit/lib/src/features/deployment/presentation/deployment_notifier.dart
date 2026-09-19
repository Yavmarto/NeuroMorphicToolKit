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

  /// How long a deployment may report nothing new before the app stops
  /// pretending it is still working.
  ///
  /// Pulling backend images is legitimately slow and only reports every few
  /// seconds, so it keeps a long budget; every other stage is a sequence of
  /// short steps, and silence there means something is wrong.
  static const _maxJobStaleness = Duration(minutes: 3);
  static const _maxPullStaleness = Duration(minutes: 25);

  static Duration _stalenessBudgetFor(DeploymentJob job) =>
      job.stage == DeploymentPhase.pullingImages.wireName
      ? _maxPullStaleness
      : _maxJobStaleness;

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

  Future<DeploymentJob> setupRemoteServer(
    RemoteServerSetupRequest request,
  ) async {
    final job = await _service.setupRemoteServer(request);
    final snapshot = await _service.load();
    state = AsyncData(
      _stateFromSnapshot(
        snapshot,
      ).copyWith(activeJob: job, connectionLostReason: null),
    );
    _startPolling();
    return job;
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
    String releaseVersion = '',
    bool schemaMigration = false,
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
        releaseVersion: releaseVersion,
        schemaMigration: schemaMigration,
      ),
    );
    final current = state.value ?? const DeploymentState();
    state = AsyncData(
      current.copyWith(activeJob: job, connectionLostReason: null),
    );
    _startPolling();
    return job;
  }

  /// Retries a remote setup attempt that stalled or failed.
  ///
  /// A stalled attempt is still nominally running, so it is cancelled first —
  /// otherwise two administrator sessions would race on the same host.
  Future<DeploymentJob> retryRemoteSetup(
    RemoteServerSetupRequest request,
  ) async {
    final job = state.value?.activeJob;
    if (job != null && !job.isTerminal) {
      try {
        await _service.cancelJob(job.id);
      } catch (_) {
        // The stalled attempt may already be unreachable. Starting the retry
        // matters more than tidying it up.
      }
    }
    return setupRemoteServer(request);
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
            error:
                'degraded optional capability: Jupyter restart failed: '
                '$error',
          ),
        ),
      );
    }
  }

  DeploymentTarget? _mostRecentTarget(DeploymentState current) {
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

  DeploymentTarget? _targetForHost(
    DeploymentState current,
    String? preferredHost,
  ) {
    final normalizedHost = preferredHost?.trim();
    if (normalizedHost == null || normalizedHost.isEmpty) {
      return _mostRecentTarget(current);
    }
    for (final candidate in current.targets) {
      if (candidate.host.trim() == normalizedHost) return candidate;
    }
    return null;
  }

  Future<SystemHealthReport?> diagnoseLatestTarget({
    String? preferredHost,
  }) async {
    final current = state.value ?? await future;
    final target = _targetForHost(current, preferredHost);
    if (target == null) {
      final host = preferredHost?.trim();
      if (host == null || host.isEmpty) return null;
      return _service.diagnoseHost(host);
    }
    return _service.diagnoseTarget(target.id);
  }

  /// Attaches SSH credentials to an already-running server this app never
  /// deployed (or whose saved credential was lost), so repair/reinstall have
  /// something to authenticate with. Runs no install.
  Future<DeploymentTarget> linkCredentialsForHost(
    DeploymentRequest request,
  ) async {
    final target = await _service.linkExistingTarget(request);
    await refresh();
    return target;
  }

  Future<SystemHealthReport?> repairLatestTarget({
    String? preferredHost,
  }) async {
    final current = state.value ?? await future;
    final target = _targetForHost(current, preferredHost);
    if (target == null) {
      throw StateError(
        'This connected server has no saved deployment credential. '
        'Set it up from this screen before running repair.',
      );
    }
    final report = await _service.repairTarget(target.id);
    await refresh();
    return report;
  }

  Future<DeploymentJob?> reinstallLatestTarget({
    bool factoryReset = false,
    String? preferredHost,
  }) async {
    final current = state.value ?? await future;
    final target = _targetForHost(current, preferredHost);
    if (target == null) {
      throw StateError(
        'This connected server has no saved deployment credential. '
        'Set it up from this screen before reinstalling.',
      );
    }
    final job = await _service.reinstallTarget(
      target.id,
      factoryReset: factoryReset,
    );
    state = AsyncData(
      current.copyWith(activeJob: job, connectionLostReason: null),
    );
    _startPolling();
    return job;
  }

  Future<void> forgetHostKey({required String host, required int sshPort}) {
    return _service.forgetHostKey(host: host, sshPort: sshPort);
  }

  DeploymentTarget? _targetForRetry(DeploymentState current) {
    final job = current.activeJob;
    if (job != null) {
      for (final candidate in current.targets) {
        if (candidate.id == job.targetId) return candidate;
      }
    }
    return _mostRecentTarget(current);
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
    String releaseVersion = '',
    bool schemaMigration = false,
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
      releaseVersion: releaseVersion,
      schemaMigration: schemaMigration,
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
    final lastProgressAt = job.lastProgressAt ?? job.updatedAt;
    final budget = _stalenessBudgetFor(job);
    if (lastProgressAt != null &&
        DateTime.now().difference(lastProgressAt) > budget) {
      timer.cancel();
      state = AsyncData(
        current.copyWith(
          connectionLostReason:
              'This server has not reported progress for '
              '${budget.inMinutes} minutes. Retry setup, or open the raw SSH '
              'output to see the last thing it did.',
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
