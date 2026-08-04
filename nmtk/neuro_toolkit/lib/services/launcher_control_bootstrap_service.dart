import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:neuro_toolkit/services/bundle_manager.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

enum LauncherBootstrapStatus {
  noServerSelected,
  notStarted,
  starting,
  ready,
  preflightFailed,
}

class LauncherBootstrapState {
  const LauncherBootstrapState({
    required this.status,
    this.baseUri,
    this.message,
    this.controlApiReachable = false,
    this.hostReachableNoServer = false,
  });

  factory LauncherBootstrapState.ready(Uri baseUri, {String? message}) {
    return LauncherBootstrapState(
      status: LauncherBootstrapStatus.ready,
      baseUri: baseUri,
      message: message,
      controlApiReachable: true,
    );
  }

  factory LauncherBootstrapState.noServerSelected() {
    return const LauncherBootstrapState(
      status: LauncherBootstrapStatus.noServerSelected,
      message: 'Choose a launcher server before opening the workspace.',
    );
  }

  factory LauncherBootstrapState.preflightFailed(
    Uri baseUri,
    String message, {
    bool controlApiReachable = false,
    bool hostReachableNoServer = false,
  }) {
    return LauncherBootstrapState(
      status: LauncherBootstrapStatus.preflightFailed,
      baseUri: baseUri,
      message: message,
      controlApiReachable: controlApiReachable,
      hostReachableNoServer: hostReachableNoServer,
    );
  }

  final LauncherBootstrapStatus status;
  final Uri? baseUri;
  final String? message;

  /// True whenever the control API's `/health` endpoint answered at all —
  /// even if the target isn't fully ready (e.g. a local `suite_api` install
  /// problem). Distinct from [canUseControlApi]: the deploy/setup wizard only
  /// needs the control API reachable, not the whole target fully ready.
  final bool controlApiReachable;

  /// True when the target's TCP connection was actively refused rather than
  /// timing out — the host itself answered, it just has no launcher control
  /// API installed on that port yet. A timeout/unreachable host leaves this
  /// false, since that usually means a wrong address rather than a clean,
  /// installable target.
  final bool hostReachableNoServer;

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
  Process? _ownedProcess;

  Future<LauncherBootstrapState> ensureReady() async {
    final cached = _cachedState;
    if (cached != null) {
      return cached;
    }
    final resolved = await _ensureReadyInternal();
    _cachedState = resolved;
    return resolved;
  }

  /// Starts or reuses the local controller only after the user explicitly
  /// chooses the setup flow. Normal application startup must never call this.
  Future<LauncherBootstrapState> ensureLocalReady() async {
    final resolved = await _ensureLocalReady();
    _cachedState = resolved;
    return resolved;
  }

  Future<LauncherBootstrapState> _ensureReadyInternal() async {
    final explicitBaseUri = _explicitBaseUri();
    if (explicitBaseUri != null) {
      final deadline = DateTime.now().add(startupTimeout);
      var lastControlApiReachable = false;
      var lastHostReachableNoServer = false;
      while (DateTime.now().isBefore(deadline)) {
        final health = await _probeHealth(explicitBaseUri);
        lastControlApiReachable = health.controlApiReachable;
        lastHostReachableNoServer = health.hostReachableNoServer;
        if (health.ready) {
          return LauncherBootstrapState.ready(explicitBaseUri);
        }
        if (health.failureMessage != null) {
          return LauncherBootstrapState.preflightFailed(
            explicitBaseUri,
            health.failureMessage!,
            controlApiReachable: health.controlApiReachable,
          );
        }
        // A refused connection means nothing is installed on this host —
        // don't keep polling, there's nothing that will ever answer.
        if (health.hostReachableNoServer) {
          break;
        }
        await Future<void>.delayed(pollInterval);
      }
      return LauncherBootstrapState.preflightFailed(
        explicitBaseUri,
        lastHostReachableNoServer
            ? 'No launcher server found at $explicitBaseUri. The host is '
                'reachable, but nothing is installed there yet.'
            : 'Preflight failed: configured launcher control API did not become ready at '
                '$explicitBaseUri within ${startupTimeout.inSeconds}s.',
        controlApiReachable: lastControlApiReachable,
        hostReachableNoServer: lastHostReachableNoServer,
      );
    }

    return _ensureLocalReady();
  }

  Future<LauncherBootstrapState> _ensureLocalReady() async {
    final localBaseUri = _localBaseUri();
    if (_environment.isWeb || !_environment.isNativeDesktop) {
      return LauncherBootstrapState.ready(localBaseUri);
    }

    // Kill any stale orphan from a previous session before probing so that
    // code changes to the Python service always take effect on restart.
    // We only do this once per app lifetime: if _ownedProcess is already set,
    // the current process was started by this instance and is up-to-date.
    if (_ownedProcess == null) {
      await _killStaleLauncherProcess();
    }

    final existingHealth = await _probeHealth(localBaseUri);
    if (existingHealth.ready && _ownedProcess != null) {
      return LauncherBootstrapState.ready(localBaseUri);
    }
    if (existingHealth.failureMessage != null) {
      return LauncherBootstrapState.preflightFailed(
        localBaseUri,
        existingHealth.failureMessage!,
        controlApiReachable: existingHealth.controlApiReachable,
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
      final process = await _environment.startProcess(
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
      _ownedProcess = process;
    } catch (error) {
      return LauncherBootstrapState.preflightFailed(
        localBaseUri,
        'Preflight failed: could not start the launcher control API: $error',
      );
    }

    final deadline = DateTime.now().add(startupTimeout);
    var lastControlApiReachable = false;
    while (DateTime.now().isBefore(deadline)) {
      final health = await _probeHealth(localBaseUri);
      lastControlApiReachable = health.controlApiReachable;
      if (health.ready) {
        return LauncherBootstrapState.ready(localBaseUri);
      }
      if (health.failureMessage != null) {
        return LauncherBootstrapState.preflightFailed(
          localBaseUri,
          health.failureMessage!,
          controlApiReachable: health.controlApiReachable,
        );
      }
      await Future<void>.delayed(pollInterval);
    }

    return LauncherBootstrapState.preflightFailed(
      localBaseUri,
      'Preflight failed: local launcher control API did not become ready at '
      '$localBaseUri within ${startupTimeout.inSeconds}s.',
      controlApiReachable: lastControlApiReachable,
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

  /// Kill any orphaned launcher_control_service.py process left over from a
  /// previous app session. Uses `pkill -f` on macOS/Linux which matches the
  /// full command line, so it's precise enough to avoid killing unrelated
  /// Python processes.
  Future<void> _killStaleLauncherProcess() async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    try {
      await Process.run('pkill', ['-f', 'launcher_control_service.py']);
      // Give the OS a moment to reclaim the port before we probe/start.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (_) {
      // pkill not available or no matching process — safe to ignore.
    }
  }

  Future<_HealthProbeResult> _probeHealth(Uri baseUri) async {
    http.Response response;
    try {
      response = await _client
          .get(baseUri.replace(path: '/health'))
          .timeout(const Duration(seconds: 2));
    } on SocketException catch (error) {
      // The OS actively refused the connection — the host answered at the
      // network level, it just has nothing listening on this port. A
      // timeout/unreachable host (handled by the catch-all below) usually
      // means a wrong address instead, so keep that distinct.
      return _HealthProbeResult.notReady(
        hostReachableNoServer: _isConnectionRefused(error),
      );
    } catch (error) {
      // ponytail: temporary diagnostic for the Android quick-connect bug —
      // remove once the real failure mode is confirmed.
      debugPrint('_probeHealth($baseUri) failed: ${error.runtimeType}: $error');
      // Genuine transport-level failure — the control API never answered.
      return const _HealthProbeResult.notReady();
    }

    // From here on something answered at the transport level, so the control
    // API itself is reachable regardless of what its body says.
    if (response.statusCode != 200) {
      return const _HealthProbeResult.notReady(controlApiReachable: true);
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
    return const _HealthProbeResult.notReady(controlApiReachable: true);
  }

  /// `errno` values for ECONNREFUSED across the platforms this app targets —
  /// the only case that means "host reachable, nothing listening on this
  /// port" rather than "couldn't reach the host at all."
  static bool _isConnectionRefused(SocketException error) {
    const econnrefusedByPlatform = <int>{
      61, // macOS / BSD
      111, // Linux
      10061, // Windows (WSAECONNREFUSED)
    };
    final code = error.osError?.errorCode;
    return code != null && econnrefusedByPlatform.contains(code);
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
  const _HealthProbeResult._({
    required this.ready,
    this.failureMessage,
    this.controlApiReachable = false,
    this.hostReachableNoServer = false,
  });

  const _HealthProbeResult.ready()
      : this._(ready: true, controlApiReachable: true);

  const _HealthProbeResult.notReady({
    bool controlApiReachable = false,
    bool hostReachableNoServer = false,
  }) : this._(
          ready: false,
          controlApiReachable: controlApiReachable,
          hostReachableNoServer: hostReachableNoServer,
        );

  const _HealthProbeResult.failed(String message)
      : this._(
            ready: false, failureMessage: message, controlApiReachable: true);

  final bool ready;
  final String? failureMessage;
  final bool controlApiReachable;
  final bool hostReachableNoServer;
}
