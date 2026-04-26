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
      if (await _isHealthy(explicitBaseUri)) {
        return LauncherBootstrapState.ready(explicitBaseUri);
      }
      return LauncherBootstrapState.preflightFailed(
        explicitBaseUri,
        'Preflight failed: configured launcher control API is unreachable at '
        '$explicitBaseUri.',
      );
    }

    final localBaseUri = _localBaseUri();
    if (_environment.isWeb || !_environment.isNativeDesktop) {
      return LauncherBootstrapState.ready(localBaseUri);
    }

    if (await _isHealthy(localBaseUri)) {
      return LauncherBootstrapState.ready(localBaseUri);
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
          '127.0.0.1',
          '--port',
          '${ControlApiService.configuredPort}',
        ],
        workingDirectory: launchSpec.workingDirectory,
        environment: <String, String>{
          ..._environment.environment,
          'PYTHONPATH': _mergedPythonPath(launchSpec.pythonPathRoot),
          'NMTK_UVICORN_HOST': '127.0.0.1',
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
      if (await _isHealthy(localBaseUri)) {
        return LauncherBootstrapState.ready(localBaseUri);
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

  Future<bool> _isHealthy(Uri baseUri) async {
    try {
      final response = await _client
          .get(baseUri.replace(path: '/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
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
