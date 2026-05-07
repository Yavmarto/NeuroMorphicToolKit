import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

class BackendDeploymentProvider with ChangeNotifier {
  BackendDeploymentProvider({ControlApiService? controlApiService})
      : _controlApiService = controlApiService ?? ControlApiService() {
    unawaited(refresh());
  }

  final ControlApiService _controlApiService;
  List<DeploymentTarget> _targets = <DeploymentTarget>[];
  DeploymentJob? _activeJob;
  bool _isLoading = true;
  bool _isReady = false;
  String? _error;
  Timer? _pollTimer;

  List<DeploymentTarget> get targets => _targets;
  DeploymentJob? get activeJob => _activeJob;
  bool get isLoading => _isLoading;
  bool get isReady => _isReady;
  String? get error => _error;

  Future<void> refresh() async {
    try {
      final settings = await _controlApiService.fetchSettings();
      _targets = await _controlApiService.fetchDeploymentTargets();
      _isReady = settings.backendDeploymentReady;
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
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
    return _controlApiService.preflightDeploymentTarget(
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
    final target = await _controlApiService.createDeploymentTarget(
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
    _activeJob = await _controlApiService.createDeploymentJob(
      <String, dynamic>{'targetId': target.id, 'mode': mode},
    );
    notifyListeners();
    _startPolling();
  }

  Future<void> cancelActiveJob() async {
    final job = _activeJob;
    if (job == null) return;
    _activeJob = await _controlApiService.cancelDeploymentJob(job.id);
    notifyListeners();
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
      final job = _activeJob;
      if (job == null) {
        timer.cancel();
        return;
      }
      _activeJob = await _controlApiService.fetchDeploymentJob(job.id);
      if (_activeJob!.isTerminal) {
        timer.cancel();
        await refresh();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
