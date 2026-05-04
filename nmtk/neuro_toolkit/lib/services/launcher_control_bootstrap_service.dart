import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:neuro_toolkit/services/bundle_manager.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

enum LauncherBootstrapStatus {
  notStarted,
  starting,
  ready,
  preflightFailed,
}

class LauncherBootstrapState {
  const LauncherBootstrapState({
    required this.status,
    required this.baseUri,
    this.message,
  });

  factory LauncherBootstrapState.ready(Uri baseUri, {String? message}) {
    return LauncherBootstrapState(
      status: LauncherBootstrapStatus.ready,
      baseUri: baseUri,
      message: message,
    );
  }

  factory LauncherBootstrapState.preflightFailed(
    Uri baseUri,
    String message,
  ) {
    return LauncherBootstrapState(
      status: LauncherBootstrapStatus.preflightFailed,
      baseUri: baseUri,
      message: message,
    );
  }

  final LauncherBootstrapStatus status;
  final Uri baseUri;
  final String? message;

  bool get canUseControlApi => status == LauncherBootstrapStatus.ready;
}

abstract class LauncherControlBootstrapEnvironment {
  bool get isWeb;
  bool get isNativeDesktop;
  bool get isBundled;
  String get currentDirectory;
  String get resourcesRootPath;
  Map<String, String> get environment;

  Future<String?> findPython();

  Future<bool> fileExists(String path);

  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

class DefaultLauncherControlBootstrapEnvironment
    implements LauncherControlBootstrapEnvironment {
  DefaultLauncherControlBootstrapEnvironment({BundleManager? bundleManager})
      : _bundleManager = bundleManager ?? BundleManager();

  final BundleManager _bundleManager;

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get isNativeDesktop {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  @override
  bool get isBundled => _bundleManager.isBundled;

  @override
  String get currentDirectory => Directory.current.path;

  @override
  String get resourcesRootPath {
    if (!_bundleManager.isBundled) {
      return currentDirectory;
    }
    if (_bundleManager.env.isMacOS) {
      return p.join(_bundleManager.bundleRootPath, 'Contents', 'Resources');
    }
    return _bundleManager.bundleRootPath;
  }

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  Future<String?> findPython() => _bundleManager.findPython();

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
}

class LauncherControlBootstrapService {
  LauncherControlBootstrapService({
    LauncherControlBootstrapEnvironment? environment,
    http.Client? client,
    this.startupTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 300),
    Uri? explicitBaseUriOverride,
  })  : _environment =
            environment ?? DefaultLauncherControlBootstrapEnvironment(),
        _client = client ?? http.Client(),
        _explicitBaseUriOverride = explicitBaseUriOverride;

  final LauncherControlBootstrapEnvironment _environment;
  final http.Client _client;
  final Duration startupTimeout;
  final Duration pollInterval;
  final Uri? _explicitBaseUriOverride;

  LauncherBootstrapState? _cachedState;

  Future<LauncherBootstrapState> ensureReady() async {
    final cached = _cachedState;
    if (cached != null) {
      return cached;
    }
    final resolved = await _ensureReadyInternal();
    _cachedState = resolved;
    return resolved;
  }

  Future<LauncherBootstrapState> _ensureReadyInternal() async {
    final explicitBaseUri = _explicitBaseUri();
    if (explicitBaseUri != null) {
      final deadline = DateTime.now().add(startupTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final health = await _probeHealth(explicitBaseUri);
        if (health.ready) {
          return LauncherBootstrapState.ready(explicitBaseUri);
        }
        if (health.failureMessage != null) {
          return LauncherBootstrapState.preflightFailed(
            explicitBaseUri,
            health.failureMessage!,
          );
        }
        await Future<void>.delayed(pollInterval);
      }
      return LauncherBootstrapState.preflightFailed(
        explicitBaseUri,
        'Preflight failed: configured launcher control API did not become ready at '
        '$explicitBaseUri within ${startupTimeout.inSeconds}s.',
      );
    }

    final localBaseUri = _localBaseUri();
    if (_environment.isWeb || !_environment.isNativeDesktop) {
      return LauncherBootstrapState.ready(localBaseUri);
    }

    final existingHealth = await _probeHealth(localBaseUri);
    if (existingHealth.ready) {
      return LauncherBootstrapState.ready(localBaseUri);
    }
    if (existingHealth.failureMessage != null) {
      return LauncherBootstrapState.preflightFailed(
        localBaseUri,
        existingHealth.failureMessage!,
      );
    }

    final python = await _environment.findPython();
    if (python == null || python.isEmpty) {
      return LauncherBootstrapState.preflightFailed(
        localBaseUri,
        'Preflight failed: Python 3 was not found for the launcher control API.',
      );
    }

    final launchSpec = _resolveLaunchSpec();
    if (!await _environment.fileExists(launchSpec.scriptPath)) {
      return LauncherBootstrapState.preflightFailed(
        localBaseUri,
        'Preflight failed: launcher control API entrypoint not found at '
        '${launchSpec.scriptPath}.',
      );
    }

    try {
      await _environment.startProcess(
        python,
        <String>[
          launchSpec.scriptPath,
          '--host',
          '0.0.0.0',
          '--port',
          '${ControlApiService.configuredPort}',
        ],
        workingDirectory: launchSpec.workingDirectory,
        environment: <String, String>{
          ..._environment.environment,
          'PYTHONPATH': _mergedPythonPath(launchSpec.pythonPathRoot),
          'NMTK_UVICORN_HOST': '0.0.0.0',
          if (_environment.isBundled) 'NMTK_BUNDLED_MODE': '1',
        },
      );
    } catch (error) {
      return LauncherBootstrapState.preflightFailed(
        localBaseUri,
        'Preflight failed: could not start the launcher control API: $error',
      );
    }

    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final health = await _probeHealth(localBaseUri);
      if (health.ready) {
        return LauncherBootstrapState.ready(localBaseUri);
      }
      if (health.failureMessage != null) {
        return LauncherBootstrapState.preflightFailed(
          localBaseUri,
          health.failureMessage!,
        );
      }
      await Future<void>.delayed(pollInterval);
    }

    return LauncherBootstrapState.preflightFailed(
      localBaseUri,
      'Preflight failed: local launcher control API did not become ready at '
      '$localBaseUri within ${startupTimeout.inSeconds}s.',
    );
  }

  Uri? _explicitBaseUri() {
    if (_explicitBaseUriOverride != null) {
      return _explicitBaseUriOverride;
    }
    final configured = ControlApiService.configuredBaseUrl.trim();
    if (configured.isEmpty) {
      return null;
    }
    return Uri.parse(configured);
  }

  Uri _localBaseUri() {
    return Uri.parse('http://127.0.0.1:${ControlApiService.configuredPort}');
  }

  Future<_HealthProbeResult> _probeHealth(Uri baseUri) async {
    try {
      final response = await _client
          .get(baseUri.replace(path: '/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        return const _HealthProbeResult.notReady();
      }
      if (response.body.isEmpty) {
        return const _HealthProbeResult.ready();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const _HealthProbeResult.ready();
      }
      final suiteApiStatus = (decoded['suiteApiStatus'] as String?)?.trim();
      final suiteApiMessage = (decoded['suiteApiMessage'] as String?)?.trim();
      if (suiteApiStatus == null ||
          suiteApiStatus.isEmpty ||
          suiteApiStatus == 'ready' ||
          suiteApiStatus == 'disabled') {
        return const _HealthProbeResult.ready();
      }
      if (suiteApiStatus == 'preflight_failed' || suiteApiStatus == 'failed') {
        return _HealthProbeResult.failed(
          suiteApiMessage == null || suiteApiMessage.isEmpty
              ? 'Preflight failed: suite_api could not start.'
              : 'Preflight failed: $suiteApiMessage',
        );
      }
      return const _HealthProbeResult.notReady();
    } catch (_) {
      return const _HealthProbeResult.notReady();
    }
  }

  _LaunchSpec _resolveLaunchSpec() {
    if (_environment.isBundled) {
      final resourcesRoot = _environment.resourcesRootPath;
      return _LaunchSpec(
        scriptPath: p.join(
          resourcesRoot,
          'scripts',
          'launcher_control_service.py',
        ),
        pythonPathRoot: resourcesRoot,
        workingDirectory: resourcesRoot,
      );
    }

    final repoRoot = p.normalize(
      p.join(_environment.currentDirectory, '..', '..'),
    );
    return _LaunchSpec(
      scriptPath: p.join(repoRoot, 'scripts', 'launcher_control_service.py'),
      pythonPathRoot: repoRoot,
      workingDirectory: repoRoot,
    );
  }

  String _mergedPythonPath(String rootPath) {
    final existing = _environment.environment['PYTHONPATH'];
    if (existing == null || existing.isEmpty) {
      return rootPath;
    }
    return '$rootPath${Platform.pathSeparator}$existing';
  }
}

class _LaunchSpec {
  const _LaunchSpec({
    required this.scriptPath,
    required this.pythonPathRoot,
    required this.workingDirectory,
  });

  final String scriptPath;
  final String pythonPathRoot;
  final String workingDirectory;
}

class _HealthProbeResult {
  const _HealthProbeResult._({required this.ready, this.failureMessage});

  const _HealthProbeResult.ready() : this._(ready: true);

  const _HealthProbeResult.notReady() : this._(ready: false);

  const _HealthProbeResult.failed(String message)
      : this._(ready: false, failureMessage: message);

  final bool ready;
  final String? failureMessage;
}
