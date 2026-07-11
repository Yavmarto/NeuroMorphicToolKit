import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/deployment/domain/deployment_state.dart';

part 'deployment_notifier.g.dart';

@riverpod
class BackendDeploymentNotifier extends _$BackendDeploymentNotifier {
  Timer? _pollTimer;
  bool _pollInFlight = false;

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
      backendPort: backendPort,
      namespace: namespace,
      context: context,
      apiServer: apiServer,
    );
    return ref.read(controlApiServiceProvider).preflightDeploymentTarget(
      <String, dynamic>{'target': payload},
    );
  }

  Future<void> deploy({
    required String targetType,
    required String mode,
    required String displayName,
    String host = '',
    String username = '',
    int sshPort = 22,
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
      state = AsyncData(currentState.copyWith(activeJob: activeJob));
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
              : 'ssh_key',
      'host': host,
      'username': username,
      'sshPort': sshPort,
      'backendPort': backendPort,
      'namespace': namespace,
      'context': context,
      'apiServer': apiServer,
    };
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final currentState = state.value;
      final job = currentState?.activeJob;
      if (job == null) {
        timer.cancel();
        return;
      }
      if (_pollInFlight) return;

      _pollInFlight = true;
      final controlApi = ref.read(controlApiServiceProvider);
      try {
        final updatedJob = await controlApi.fetchDeploymentJob(job.id);
        if (updatedJob.isTerminal) {
          timer.cancel();
          await refresh();
        } else {
          state = AsyncData(currentState!.copyWith(activeJob: updatedJob));
        }
      } catch (e) {
        // Ignore polling errors
      } finally {
        _pollInFlight = false;
      }
    });
  }
}
