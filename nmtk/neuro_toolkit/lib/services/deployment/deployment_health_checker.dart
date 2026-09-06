import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/bootstrap_transcript_parsing.dart';
import 'package:neuro_toolkit/services/deployment/deployment_asset_bundle.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/job_registry.dart';
import 'package:neuro_toolkit/services/deployment/local_deployment_service.dart';
import 'package:neuro_toolkit/services/deployment/remote_deployment_runner.dart';

/// Where this device can actually reach one target's services.
///
/// The remote overlay publishes every port on the server's own loopback, so a
/// remote backend answers only over an SSH tunnel; `host:port` reaches a local
/// deployment and older remote installs that still published on all
/// interfaces. Probing `host:port` against a loopback-bound server never even
/// connects, which reads back as "the backend is dead" however healthy it is —
/// that is what stranded a finished install at 90% with "this Mac cannot
/// reach it" and left reinstalling as the only offer.
class BackendEndpoints {
  const BackendEndpoints({
    required this.suiteApi,
    required this.launcherControl,
    required this.jupyter,
  });

  /// Straight at the host, for a local deployment or a legacy open-port one.
  BackendEndpoints.direct({required String host, required int backendPort})
    : suiteApi = Uri.parse('http://$host:$backendPort'),
      launcherControl = Uri.parse(
        'http://$host:${DeploymentHealthChecker.launcherControlPort}',
      ),
      jupyter = Uri.parse('http://$host:8008');

  final Uri suiteApi;
  final Uri launcherControl;
  final Uri jupyter;
}

/// Diagnoses and repairs an already-deployed backend: doctor-style HTTP
/// health checks, post-deploy readiness verification, and driving a repair
/// pass through [RemoteDeploymentRunner]/[LocalDeploymentService] when a
/// saved target needs one.
class DeploymentHealthChecker {
  DeploymentHealthChecker({http.Client? httpClient})
    : _httpClient = _AdminTokenClient(httpClient ?? http.Client());

  // Every doctor/health endpoint except /api/suite/health is behind the
  // administrator token, so a token-less probe reads back as "the backend is
  // not serving requests" and pushes the user into a needless reinstall.
  // ponytail: one shared token on the wrapper, set by each entry point below;
  // give _AdminTokenClient a per-request token if two targets are ever
  // diagnosed concurrently.
  final _AdminTokenClient _httpClient;

  static const int launcherControlPort = int.fromEnvironment(
    'NMTK_CONTROL_API_PORT',
    defaultValue: 8090,
  );

  Future<SystemHealthReport> diagnoseTarget(
    String targetId, {
    required JobRegistry registry,
    BackendEndpoints? endpoints,
  }) async {
    final targets = await (await registry.store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) throw StateError('Unknown deployment target.');
    final target = matches.first;
    final request = await (await registry.store).requestForTarget(target);
    return diagnoseHost(
      target.host,
      backendPort: target.backendPort,
      adminToken: request.adminToken,
      endpoints: endpoints,
    );
  }

  Future<SystemHealthReport> diagnoseHost(
    String host, {
    int backendPort = 9000,
    String adminToken = '',
    BackendEndpoints? endpoints,
  }) async {
    _httpClient.token = adminToken;
    final effectiveHost = host.trim().isEmpty ? '127.0.0.1' : host.trim();
    final api =
        endpoints ??
        BackendEndpoints.direct(host: effectiveHost, backendPort: backendPort);
    final checks = <SystemHealthCheck>[];

    try {
      final response = await _httpClient
          .post(
            api.suiteApi.resolve('/api/suite/doctor'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'capabilities': const <String>['snntorch'],
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        throw StateError('Suite doctor returned HTTP ${response.statusCode}.');
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Suite doctor returned invalid JSON.');
      }
      checks.addAll(SystemHealthReport.fromJson(payload).checks);
    } on Object {
      checks.add(
        const SystemHealthCheck(
          id: 'suite-api',
          label: 'NMTK backend',
          status: SystemHealthStatus.failed,
          detail: 'The NMTK backend is not serving requests.',
          recovery: 'Repair the saved server from System Health.',
          repairable: true,
        ),
      );
    }

    try {
      final response = await _httpClient
          .get(api.launcherControl.resolve('/api/launcher/doctor'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw StateError(
          'Launcher doctor returned HTTP ${response.statusCode}.',
        );
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Launcher doctor returned invalid JSON.');
      }
      final fatalCount = payload['fatalCount'] as int? ?? 0;
      final degradedCount = payload['degradedCount'] as int? ?? 0;
      checks.add(
        SystemHealthCheck(
          id: 'launcher-control',
          label: 'Launcher control',
          status: fatalCount > 0
              ? SystemHealthStatus.failed
              : degradedCount > 0
              ? SystemHealthStatus.degraded
              : SystemHealthStatus.ok,
          detail: fatalCount > 0
              ? '$fatalCount required launcher check(s) failed.'
              : degradedCount > 0
              ? '$degradedCount optional launcher capability check(s) are degraded.'
              : 'Launcher control and required modules are ready.',
          recovery: fatalCount > 0
              ? 'Repair the saved server from System Health.'
              : '',
          repairable: fatalCount > 0,
        ),
      );
      final hosts = payload['akidaHosts'];
      if (hosts is! List<dynamic> || hosts.isEmpty) {
        checks.add(
          const SystemHealthCheck(
            id: 'akida-runtime',
            label: 'Akida runtime',
            status: SystemHealthStatus.notConfigured,
            detail: 'No Akida runtime is configured for this backend.',
            required: false,
          ),
        );
      } else {
        final hostMaps = hosts.whereType<Map<String, dynamic>>().toList();
        final allReady =
            hostMaps.isNotEmpty &&
            hostMaps.every((item) => item['state'] == 'ready');
        checks.add(
          SystemHealthCheck(
            id: 'akida-runtime',
            label: 'Akida runtime',
            status: allReady
                ? SystemHealthStatus.ok
                : SystemHealthStatus.degraded,
            detail: allReady
                ? 'The configured Akida runtime is ready.'
                : 'A configured Akida runtime needs attention.',
            recovery: allReady
                ? ''
                : 'Open Akida target management and run its preflight repair.',
            repairable: !allReady,
            required: false,
          ),
        );
      }
    } on Object {
      checks.add(
        const SystemHealthCheck(
          id: 'launcher-control',
          label: 'Launcher control',
          status: SystemHealthStatus.failed,
          detail: 'Launcher control is not serving requests.',
          recovery: 'Repair the saved server from System Health.',
          repairable: true,
        ),
      );
    }

    final overall =
        checks.any(
          (check) =>
              check.required && check.status == SystemHealthStatus.failed,
        )
        ? SystemHealthStatus.failed
        : checks.any(
            (check) =>
                check.status == SystemHealthStatus.failed ||
                check.status == SystemHealthStatus.degraded,
          )
        ? SystemHealthStatus.degraded
        : SystemHealthStatus.ok;
    return SystemHealthReport(
      overall: overall,
      checkedAt: DateTime.now(),
      checks: checks,
    );
  }

  Future<SystemHealthReport> repairTarget(
    String targetId, {
    required JobRegistry registry,
    required AssetBundle assets,
    required RemoteDeploymentRunner runner,
    required LocalDeploymentService local,
    BackendEndpoints? endpoints,
  }) async {
    final targets = await (await registry.store).loadTargets();
    final matches = targets.where((target) => target.id == targetId);
    if (matches.isEmpty) throw StateError('Unknown deployment target.');
    final target = matches.first;
    final request = await (await registry.store).requestForTarget(target);
    _httpClient.token = request.adminToken;
    await DeploymentAssetBundle.load(assets);

    if (target.targetType == 'remote_host') {
      final client = await runner.connect(request, await registry.store);
      try {
        final deployDir = await runner.remoteDeployDir(client);
        await runner.uploadAssetsForRepair(client, deployDir, assets: assets);
        await runner.runChecked(
          client,
          'cd ${shellQuote(deployDir)} && '
              'bash ./nmtk-stack.sh install ${shellQuote(request.containerEngine)} && '
              'bash ./nmtk-stack.sh start ${shellQuote(request.containerEngine)}',
          'The server could not restart the NMTK backend.',
        );
      } finally {
        client.close();
      }
    } else {
      final directory = await local.materializeAssets(assets);
      await local.runChecked(
        request.containerEngine,
        [
          'compose',
          '--project-name',
          'nmtk',
          '-f',
          'docker-compose.yml',
          '-f',
          'docker-compose.prod.yml',
          'up',
          '-d',
          '--no-build',
          '--remove-orphans',
        ],
        directory,
        launcherControlPort: launcherControlPort,
      );
    }
    await waitForHealth(
      (endpoints ??
              BackendEndpoints.direct(
                host: target.host.isEmpty ? '127.0.0.1' : target.host,
                backendPort: target.backendPort,
              ))
          .suiteApi
          .resolve('/api/suite/health'),
      attempts: 30,
    );
    return diagnoseTarget(targetId, registry: registry, endpoints: endpoints);
  }

  Future<bool> isApiReady(
    DeploymentTarget target, {
    String adminToken = '',
    BackendEndpoints? endpoints,
  }) async {
    final api =
        endpoints ??
        BackendEndpoints.direct(
          host: target.host.isEmpty ? '127.0.0.1' : target.host,
          backendPort: target.backendPort,
        );
    return waitForHealth(
      api.launcherControl.resolve('/health'),
      attempts: 1,
      adminToken: adminToken,
    );
  }

  Future<bool> waitForHealth(
    Uri uri, {
    int attempts = 60,
    String adminToken = '',
  }) async {
    _httpClient.token = adminToken;
    return (await _waitForResponse(uri, attempts: attempts)) != null;
  }

  Future<http.Response?> _waitForResponse(
    Uri uri, {
    required int attempts,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _httpClient
            .get(uri)
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) return response;
      } catch (_) {
        // Startup connection failures are expected while containers warm.
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  Future<DeploymentJob> verifyRemoteApis(
    DeploymentJob job,
    DeploymentTarget target, {
    String? hostOverride,
    int attempts = 60,
    String adminToken = '',
    BackendEndpoints? endpoints,
    required JobRegistry registry,
  }) async {
    _httpClient.token = adminToken;
    final host = hostOverride ?? target.host;
    final api =
        endpoints ??
        BackendEndpoints.direct(host: host, backendPort: target.backendPort);
    final suiteReady = await waitForHealth(
      api.suiteApi.resolve('/api/suite/health'),
      attempts: attempts,
    );
    if (!suiteReady) {
      throw StateError(
        'Suite API did not become ready at $host:${target.backendPort}.',
      );
    }
    final launcherReady = await waitForHealth(
      api.launcherControl.resolve('/health'),
      attempts: attempts,
    );
    if (!launcherReady) {
      throw StateError(
        'Launcher control did not become ready at ${api.launcherControl}.',
      );
    }
    final neuroStudioReady = await waitForHealth(
      api.suiteApi.resolve('/api/neurocnl/health'),
      attempts: attempts,
    );
    if (!neuroStudioReady) {
      throw StateError(
        'NeuroStudio did not become ready on the deployed server.',
      );
    }
    final modulesResponse = await _waitForResponse(
      api.launcherControl.resolve('/api/launcher/modules'),
      attempts: attempts,
    );
    if (modulesResponse == null) {
      throw StateError('Launcher control did not return its module list.');
    }
    final modules = jsonDecode(modulesResponse.body);
    if (modules is! List ||
        !modules.any(
          (module) =>
              module is Map<String, dynamic> && module['id'] == 'neurocnl',
        )) {
      throw StateError('NeuroStudio is not available from launcher control.');
    }
    await _startAndVerifyNeuroStudio(api, attempts: attempts);

    // Jupyter is optional, but two attempts is ~2 seconds: a container that
    // builds its kernel environment on first boot is reported "not ready"
    // while it is still perfectly on track. A minute of grace turns that
    // false alarm back into the rare real one.
    final jupyterReady = await waitForHealth(
      api.jupyter.resolve('/api/status'),
      attempts: 30,
    );
    var currentJob = job;
    final logs = [...currentJob.logs];
    if (!jupyterReady) {
      logs.add(
        'degraded optional capability: Jupyter is not ready; core services '
        'are available.',
      );
    }
    final optionalFailures = <String>[
      if (!jupyterReady) 'Jupyter is not ready',
    ];
    final akidaResult = await _updateSelectedAkidaRuntime(
      currentJob,
      api.launcherControl,
      registry: registry,
    );
    currentJob = akidaResult.job;
    logs
      ..clear()
      ..addAll(currentJob.logs);
    if (akidaResult.failureMessage != null) {
      optionalFailures.add(akidaResult.failureMessage!);
      logs.add('degraded optional capability: ${akidaResult.failureMessage}');
    }
    final optionalCapabilityError = optionalFailures.isEmpty
        ? ''
        : 'degraded optional capability: ${optionalFailures.join('; ')}; '
              'core services are available.';
    return currentJob.copyWith(
      stage: DeploymentPhase.completed.wireName,
      percent: 100,
      stageLabel: 'Backend and launcher control are ready',
      logs: logs,
      error: optionalCapabilityError,
      updatedAt: DateTime.now(),
    );
  }

  Future<({DeploymentJob job, String? failureMessage})>
  _updateSelectedAkidaRuntime(
    DeploymentJob job,
    Uri launcherBase, {
    required JobRegistry registry,
  }) async {
    Map<String, dynamic> settings;
    try {
      final response = await _httpClient
          .get(launcherBase.resolve('/api/launcher/settings'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return (
          job: job,
          failureMessage:
              'Akida target selection could not be read; retry the Akida update',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (
          job: job,
          failureMessage:
              'Akida target selection could not be read; retry the Akida update',
        );
      }
      settings = decoded;
    } catch (_) {
      return (
        job: job,
        failureMessage:
            'Akida target selection could not be read; retry the Akida update',
      );
    }
    final selectedHostId = settings['selectedAkidaHostId'];
    if (selectedHostId is! String || selectedHostId.trim().isEmpty) {
      return (job: job, failureMessage: null);
    }

    final hostId = selectedHostId.trim();
    Map<String, dynamic> update;
    try {
      final response = await _httpClient
          .post(
            launcherBase.resolve(
              '/api/launcher/akida/hosts/$hostId/runtime-update-jobs',
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          job: job,
          failureMessage:
              'the selected Akida runtime update could not be started; retry it in Backend Setup',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return (
          job: job,
          failureMessage:
              'the selected Akida runtime returned an invalid update status; retry it in Backend Setup',
        );
      }
      update = decoded;
    } catch (_) {
      return (
        job: job,
        failureMessage:
            'the selected Akida host is offline or unreachable; retry the Akida update',
      );
    }

    for (var poll = 0; poll < 600; poll++) {
      final status = update['status']?.toString() ?? '';
      final message = update['message']?.toString().trim() ?? '';
      final progress = (update['progress'] as num?)?.toDouble() ?? 0;
      if (status == 'completed') {
        final version = update['installedVersion']?.toString().trim() ?? '';
        return (
          job: job.copyWith(
            logs: [
              ...job.logs,
              version.isEmpty
                  ? 'Selected Akida runtime is up to date.'
                  : 'Selected Akida runtime $version is up to date.',
            ],
          ),
          failureMessage: null,
        );
      }
      if (status == 'failed') {
        final recovery = update['recovery']?.toString().trim() ?? '';
        final safeMessage = message.isEmpty
            ? 'the selected Akida runtime update failed'
            : message;
        return (
          job: job,
          failureMessage: recovery.isEmpty
              ? safeMessage
              : '$safeMessage $recovery',
        );
      }

      final label = message.isEmpty
          ? 'Updating selected Akida runtime'
          : message;
      job = job.copyWith(
        stage: DeploymentPhase.updatingAkidaRuntime.wireName,
        percent: 94 + (progress.clamp(0, 100) * 0.05),
        stageLabel: label,
        logs: job.logs.isNotEmpty && job.logs.last == label
            ? job.logs
            : [...job.logs, label],
        updatedAt: DateTime.now(),
        lastProgressAt: DateTime.now(),
      );
      await registry.updateJob(job);
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        final response = await _httpClient
            .get(
              launcherBase.resolve(
                '/api/launcher/akida/hosts/$hostId/runtime-update-jobs/${update['jobId']}',
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) update = decoded;
      } catch (_) {
        // A service restart can briefly close the launcher connection. Keep
        // polling the persisted job instead of turning that into a core
        // backend deployment failure.
      }
    }
    return (
      job: job,
      failureMessage:
          'the selected Akida runtime update timed out; retry it in Backend Setup',
    );
  }

  Future<void> _startAndVerifyNeuroStudio(
    BackendEndpoints api, {
    required int attempts,
  }) async {
    final launcherBase = api.launcherControl;
    final startResponse = await _httpClient
        .post(launcherBase.resolve('/api/launcher/modules/neurocnl/start'))
        .timeout(const Duration(seconds: 4));
    if (startResponse.statusCode < 200 || startResponse.statusCode >= 300) {
      throw StateError('Launcher control could not start NeuroStudio.');
    }
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _httpClient
            .get(launcherBase.resolve('/api/launcher/modules/neurocnl'))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final module = jsonDecode(response.body);
          if (module is Map<String, dynamic>) {
            final status = module['status'];
            if (status == 4 || status == 7) return;
            if (status == 6) {
              throw StateError(
                'NeuroStudio could not start on the deployed server.',
              );
            }
          }
        }
      } catch (error) {
        if (error is StateError) rethrow;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError(
      'NeuroStudio did not become ready on the deployed server.',
    );
  }

  DeploymentJob clientReachabilityFailure(
    DeploymentJob job,
    DeploymentTarget target, {
    Object? cause,
  }) {
    // "This Mac cannot reach it" was reported for every post-install check
    // that failed, including ones the network had nothing to do with, so the
    // one message that mattered — which check failed and why — was thrown
    // away. Say what actually happened.
    final detail = cause == null
        ? ''
        : ' ${cause.toString().replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), '')}';
    final message =
        'The backend started on the server, but this Mac could not finish '
        'checking it.$detail';
    return job.copyWith(
      stage: DeploymentPhase.failed.wireName,
      percent: 100,
      stageLabel: 'Backend could not be verified from this device',
      logs: [
        ...job.logs,
        'Client readiness check failed for ${target.host}.$detail',
      ],
      error: message,
      failureDetails: DeploymentFailureDetails(
        code: 'client_readiness_failed',
        phase: 'verifying_suite_api',
        summary: 'Backend could not be verified from this device',
        recovery: message,
        technicalDetails: cause == null
            ? 'Required client-facing health checks did not all return HTTP 200.'
            : boundedDiagnosticOutput(cause.toString()),
        existingConnectionReachable: false,
      ),
      updatedAt: DateTime.now(),
    );
  }
}

/// Adds the administrator token to every deployment health probe. Without it
/// the suite and launcher doctors answer 401 and a healthy backend looks dead.
class _AdminTokenClient extends http.BaseClient {
  _AdminTokenClient(this._inner);

  final http.Client _inner;
  String token = '';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (token.isNotEmpty) {
      request.headers['X-NMTK-Admin-Token'] = token;
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
