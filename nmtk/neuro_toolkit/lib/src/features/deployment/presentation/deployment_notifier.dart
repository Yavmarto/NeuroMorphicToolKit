import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/deployment/domain/deployment_state.dart';

part 'deployment_notifier.g.dart';

@riverpod
class BackendDeploymentNotifier extends _$BackendDeploymentNotifier {
  static const _maxConsecutivePollFailures = 3;

  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _consecutivePollFailures = 0;

  @override
  Future<DeploymentState> build() async {
    final controlApi = ref.watch(controlApiServiceProvider);
    final settings = await controlApi.fetchSettings();
    final targets = await controlApi.fetchDeploymentTargets();

    ref.onDispose(() {
      _pollTimer?.cancel();
    });

    return DeploymentState(
      targets: targets,
      isReady: settings.backendDeploymentReady,
    );
  }

  Future<void> refresh() async {
    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final settings = await controlApi.fetchSettings();
      final targets = await controlApi.fetchDeploymentTargets();

      final currentState = state.value;
      if (currentState != null) {
        state = AsyncData(currentState.copyWith(
          targets: targets,
          isReady: settings.backendDeploymentReady,
        ));
      } else {
        state = AsyncData(DeploymentState(
          targets: targets,
          isReady: settings.backendDeploymentReady,
        ));
      }
    } catch (e, st) {
      state = AsyncError(e, st);
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
  }) async {
    final payload = _targetPayload(
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
    );
    return ref.read(controlApiServiceProvider).preflightDeploymentTarget(
      <String, dynamic>{'target': payload},
    );
  }

  /// One-time root SSH bootstrap: creates a dedicated non-root deploy user
  /// on the remote host. `rootPassword`/`rootPrivateKey` are sent to the
  /// local control API for a single SSH session and are never persisted by
  /// it — the returned credentials are the only thing meant to be kept,
  /// exactly as if the user had pasted a private key in manually.
  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    String rootPassword = '',
    String rootPrivateKey = '',
  }) {
    return ref.read(controlApiServiceProvider).bootstrapRemoteDeployUser(
      <String, dynamic>{
        'host': host,
        'sshPort': sshPort,
        'rootUsername': rootUsername,
        if (rootPassword.isNotEmpty) 'rootPassword': rootPassword,
        if (rootPrivateKey.isNotEmpty) 'rootPrivateKey': rootPrivateKey,
      },
    );
  }

  Future<void> deploy({
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
  }) async {
    final controlApi = ref.read(controlApiServiceProvider);
    final target = await controlApi.createDeploymentTarget(
      _targetPayload(
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
      ),
    );
    final activeJob = await controlApi.createDeploymentJob(
      <String, dynamic>{'targetId': target.id, 'mode': mode},
    );

    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(
        activeJob: activeJob,
        connectionLostReason: null,
      ));
    }

    _startPolling();
  }

  Future<void> cancelActiveJob() async {
    final currentState = state.value;
    final job = currentState?.activeJob;
    if (job == null) return;

    final controlApi = ref.read(controlApiServiceProvider);
    final updatedJob = await controlApi.cancelDeploymentJob(job.id);

    state = AsyncData(currentState!.copyWith(activeJob: updatedJob));
  }

  Map<String, dynamic> _targetPayload({
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
  }) {
    return <String, dynamic>{
      'displayName': displayName,
      'targetType': targetType,
      'mode': mode,
      'authMode': targetType == 'local'
          ? 'none'
          : targetType == 'kubernetes_cluster'
              ? 'kubeconfig'
              : authMethod,
      'host': host,
      'username': username,
      'sshPort': sshPort,
      if (targetType == 'remote_host' && authMethod == 'ssh_password')
        'sshPassword': sshPassword,
      if (targetType == 'remote_host' && authMethod == 'ssh_key')
        'sshPrivateKey': sshPrivateKey,
      'backendPort': backendPort,
      'namespace': namespace,
      'context': context,
      'apiServer': apiServer,
    };
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _consecutivePollFailures = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), _pollTick);
    // Jobs here can fail in well under a second (e.g. an instant SSH auth
    // rejection) — waiting for the first periodic tick would leave the UI
    // showing nothing but the initial state for a whole second, reading as
    // frozen. Check right away instead of waiting.
    unawaited(_pollTick(_pollTimer!));
  }

  static const _maxJobStaleness = Duration(seconds: 45);

  Future<void> _pollTick(Timer timer) async {
    final currentState = state.value;
    final job = currentState?.activeJob;
    if (job == null) {
      timer.cancel();
      return;
    }

    // Staleness watchdog, checked before the in-flight guard below: if a
    // poll request never resolves (e.g. a hung connection while the backend
    // restarts), _pollInFlight can latch true forever, silently freezing
    // this job's displayed state indefinitely with nothing to break out of
    // it. Using the job's own updatedAt — the same number shown to the user
    // as "updated Xs ago" — as a hard ceiling means the display is never
    // allowed to go stale without also self-healing.
    final updatedAt = job.updatedAt;
    if (updatedAt != null &&
        DateTime.now().difference(updatedAt) > _maxJobStaleness) {
      timer.cancel();
      _pollInFlight = false;
      final latestState = state.value;
      if (latestState != null) {
        state = AsyncData(latestState.copyWith(
          activeJob: null,
          connectionLostReason:
              'Lost contact with the deploy job after ${_maxJobStaleness.inSeconds}s '
              'without an update — it may still be running on the server.',
        ));
      }
      await refresh();
      return;
    }

    if (_pollInFlight) return;

    _pollInFlight = true;
    final controlApi = ref.read(controlApiServiceProvider);
    try {
      final updatedJob = await controlApi.fetchDeploymentJob(job.id);
      _consecutivePollFailures = 0;
      // Apply the polled job before branching on terminal/non-terminal —
      // otherwise a terminal (failed/completed) payload gets discarded below
      // and the UI keeps showing the last in-progress snapshot forever.
      state = AsyncData(currentState!.copyWith(activeJob: updatedJob));
      if (updatedJob.isTerminal) {
        timer.cancel();
        await refresh();
      }
    } catch (e) {
      // A single stalled poll shouldn't clear an in-progress job — but
      // repeated failures mean we can no longer trust this activeJob is
      // still accurate, so fall back to the persisted target state
      // (lastReadiness/lastFailureReason) instead of polling forever in
      // silence.
      _consecutivePollFailures++;
      if (_consecutivePollFailures >= _maxConsecutivePollFailures) {
        timer.cancel();
        final latestState = state.value;
        if (latestState != null) {
          state = AsyncData(latestState.copyWith(
            activeJob: null,
            connectionLostReason:
                'Lost contact with the deploy job after '
                '$_maxConsecutivePollFailures failed status checks — it may '
                'still be running on the server.',
          ));
        }
        await refresh();
      }
    } finally {
      _pollInFlight = false;
    }
  }
}
