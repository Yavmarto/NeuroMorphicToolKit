import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/bundle_manager.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class ProcessRunner {
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  });

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  });
}

class DefaultProcessRunner implements ProcessRunner {
  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }
}

class _HealthProbeResponse {
  const _HealthProbeResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class ProcessManager {
  static const int _maxConsecutiveHealthFailures = 2;
  static const Duration _defaultStartupHealthGracePeriod = Duration(
    seconds: 12,
  );
  static const Duration _defaultStartupHealthProbeInterval = Duration(
    milliseconds: 500,
  );

  static final ProcessManager _instance = ProcessManager._internal();
  factory ProcessManager(
      {ProcessRunner? processRunner, http.Client? httpClient}) {
    if (processRunner != null) {
      _instance._processRunner = processRunner;
    }
    if (httpClient != null) {
      _instance._httpClient = httpClient;
    }
    return _instance;
  }

  @visibleForTesting
  set processRunner(ProcessRunner runner) => _processRunner = runner;

  @visibleForTesting
  set httpClient(http.Client client) => _httpClient = client;

  @visibleForTesting
  set startupHealthGracePeriod(Duration duration) =>
      _startupHealthGracePeriod = duration;

  @visibleForTesting
  set startupHealthProbeInterval(Duration duration) =>
      _startupHealthProbeInterval = duration;

  ProcessManager._internal();

  ProcessRunner _processRunner = DefaultProcessRunner();
  http.Client _httpClient = http.Client();

  final Map<String, Process> _runningProcesses = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final Map<String, int> _retryCounts = {};
  final Map<String, int> _consecutiveHealthFailures = {};
  final Map<String, DateTime> _nextRetryTimes = {};
  final Map<String, DateTime> _startupGraceDeadlines = {};
  final Set<String> _intentionallyStopping = {};
  final Set<String> _failureStopping = {};
  Timer? _healthTimer;
  bool _initialized = false;
  List<Module> _modules = [];
  LogLevel _currentLogLevel = LogLevel.info;
  Duration _startupHealthGracePeriod = _defaultStartupHealthGracePeriod;
  Duration _startupHealthProbeInterval = _defaultStartupHealthProbeInterval;

  // Stream for status updates
  final _statusController = StreamController<Module>.broadcast();
  Stream<Module> get statusUpdates => _statusController.stream;

  void _updateModuleStatus(Module module) {
    final index = _modules.indexWhere((m) => m.id == module.id);
    if (index != -1) {
      _modules[index] = module;
    }
    _statusController.add(module);
  }

  Module _currentModuleState(String moduleId, Module fallback) {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) {
      return fallback;
    }
    return _modules[index];
  }

  void _resetHealthFailureCount(String moduleId) {
    _consecutiveHealthFailures.remove(moduleId);
  }

  bool _isInStartupGracePeriod(String moduleId) {
    final deadline = _startupGraceDeadlines[moduleId];
    return deadline != null && DateTime.now().isBefore(deadline);
  }

  bool _isRetryableProbeError(Object error) {
    return error is http.ClientException ||
        error is SocketException ||
        error is HttpException ||
        error is TimeoutException;
  }

  Future<_HealthProbeResponse> _sendHealthProbe(Uri uri) async {
    final request = http.Request('GET', uri)..persistentConnection = false;
    final response = await _httpClient.send(request).timeout(
          const Duration(seconds: 2),
        );
    final body = await response.stream.bytesToString();
    return _HealthProbeResponse(statusCode: response.statusCode, body: body);
  }

  Future<_HealthProbeResponse> _probeHealth(Uri uri, String moduleId) async {
    Object? lastError;

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await _sendHealthProbe(uri);
      } catch (error) {
        lastError = error;
        if (!_isRetryableProbeError(error) || attempt == 2) {
          break;
        }
        debugPrint(
          '[$moduleId] Health probe transport error on attempt '
          '$attempt/2, retrying with a fresh request: $error',
        );
      }
    }

    throw lastError!;
  }

  Future<void> _recordHealthFailure(Module module, String error) async {
    final currentModule = _currentModuleState(module.id, module);
    if (currentModule.status == ModuleStatus.starting &&
        _isInStartupGracePeriod(module.id)) {
      final startupDeadline = _startupGraceDeadlines[module.id]!;
      final updatedModule = currentModule.copyWith(
        status: ModuleStatus.starting,
        healthStatus:
            'Waiting for startup until ${startupDeadline.toIso8601String()}: '
            '$error',
      );
      _updateModuleStatus(updatedModule);
      return;
    }

    final failureCount = (_consecutiveHealthFailures[module.id] ?? 0) + 1;
    _consecutiveHealthFailures[module.id] = failureCount;

    if (failureCount < _maxConsecutiveHealthFailures) {
      final nextStatus = currentModule.status == ModuleStatus.starting
          ? ModuleStatus.starting
          : ModuleStatus.degraded;
      final updatedModule = currentModule.copyWith(
        status: nextStatus,
        healthStatus: 'Transient health probe issue ($failureCount/'
            '$_maxConsecutiveHealthFailures): $error',
      );
      _updateModuleStatus(updatedModule);
      return;
    }

    await _handleFailure(
      currentModule,
      'Health check failed after $failureCount consecutive probes: $error',
    );
  }

  @visibleForTesting
  Future<bool> checkHealthForTesting(Module module) => _checkHealth(module);

  @visibleForTesting
  int consecutiveHealthFailuresFor(String moduleId) =>
      _consecutiveHealthFailures[moduleId] ?? 0;

  @visibleForTesting
  bool hasScheduledRetryFor(String moduleId) =>
      _nextRetryTimes.containsKey(moduleId);

  @visibleForTesting
  Module? moduleStateForTesting(String moduleId) {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) {
      return null;
    }
    return _modules[index];
  }

  void _scheduleRetry(Module module) {
    final count = (_retryCounts[module.id] ?? 0) + 1;
    _retryCounts[module.id] = count;

    // Backoff: 5, 10, 20, 40, 60, 60...
    int seconds = (5 * (1 << (count - 1)));
    if (seconds > 60) seconds = 60;

    final nextRetry = DateTime.now().add(Duration(seconds: seconds));
    _nextRetryTimes[module.id] = nextRetry;

    debugPrint(
        '[${module.id}] Scheduled retry #$count in ${seconds}s at $nextRetry');

    final updatedModule = module.copyWith(
      status: ModuleStatus.error,
      healthStatus:
          '${module.healthStatus ?? "Unhealthy"}. Retrying in ${seconds}s...',
    );
    _updateModuleStatus(updatedModule);
  }

  Future<void> _handleFailure(Module module, String? error) async {
    if (module.status == ModuleStatus.stopping ||
        _intentionallyStopping.contains(module.id)) {
      return;
    }

    _resetHealthFailureCount(module.id);
    _startupGraceDeadlines.remove(module.id);
    debugPrint('[${module.id}] Handling failure: $error');

    final updatedModule = module.copyWith(
      status: ModuleStatus.error,
      healthStatus: error,
    );
    _updateModuleStatus(updatedModule);

    if (_runningProcesses.containsKey(module.id)) {
      _failureStopping.add(module.id);
      await stopModule(module.id, isFailure: true);
    }

    _failureStopping.remove(module.id);
    _scheduleRetry(updatedModule);
  }

  Future<void> init(List<Module> modules,
      [LogLevel logLevel = LogLevel.info]) async {
    _currentLogLevel = logLevel;
    if (_initialized) {
      // Update modules list if it changed
      _modules = modules;
      return;
    }
    _modules = modules;
    await _loadState(_modules);
    _startHealthPolling();
    _initialized = true;
  }

  @visibleForTesting
  void resetForTesting() {
    dispose();
    _retryCounts.clear();
    _consecutiveHealthFailures.clear();
    _nextRetryTimes.clear();
    _intentionallyStopping.clear();
    _failureStopping.clear();
    _modules.clear();
  }

  void dispose() {
    _healthTimer?.cancel();
    _initialized = false;
    for (var controller in _outputControllers.values) {
      controller.close();
    }
    _outputControllers.clear();
    _runningProcesses.clear();
    _consecutiveHealthFailures.clear();
    _failureStopping.clear();
    _startupGraceDeadlines.clear();
  }

  /// The directory containing pyproject.toml (for pip install).
  String _installDir(Module module) {
    return p.normalize(p.join(module.directory, module.sourcePath));
  }

  /// The working directory for uvicorn (may differ from install dir).
  String _runDir(Module module) {
    return p.normalize(p.join(module.directory, module.runPath));
  }

  Future<void> installModule(
    Module module, {
    void Function(double)? onProgress,
  }) async {
    final installDir = _installDir(module);
    final moduleDir = Directory(installDir);
    debugPrint('[${module.id}] installModule: installDir=$installDir');

    if (!await moduleDir.exists()) {
      debugPrint('[${module.id}] ERROR: directory not found: $installDir');
      final isBundled = BundleManager().isBundled;
      final mode = isBundled ? 'bundled' : 'development';
      throw Exception(
        'Module directory not found in $mode mode: $installDir. '
        '${isBundled ? "The application bundle might be corrupted." : "Please ensure the repository submodules are initialized."}',
      );
    }

    final venvPath = p.join(installDir, 'venv');
    final venvDir = Directory(venvPath);

    try {
      // If the venv directory exists but python is missing/broken (e.g. the
      // base interpreter was removed), delete it so it gets recreated below.
      if (await venvDir.exists()) {
        final venvPythonCheck = Platform.isWindows
            ? p.join(venvPath, 'Scripts', 'python.exe')
            : p.join(venvPath, 'bin', 'python');
        if (!await File(venvPythonCheck).exists()) {
          debugPrint(
            '[${module.id}] venv python missing/broken, deleting for recreation...',
          );
          await venvDir.delete(recursive: true);
        }
      }

      if (!await venvDir.exists()) {
        onProgress?.call(0.1);
        final pythonBin = await BundleManager().pythonPath;
        debugPrint(
          '[${module.id}] Creating venv with: $pythonBin -m venv venv (in $installDir)',
        );

        var venvResult = await _processRunner.run(
          pythonBin,
          ['-m', 'venv', 'venv'],
          workingDirectory: installDir,
        );

        if (venvResult.exitCode != 0) {
          debugPrint(
            '[${module.id}] Normal venv failed (exit ${venvResult.exitCode}): ${venvResult.stderr}',
          );
          debugPrint('[${module.id}] Trying --without-pip fallback...');
          if (await venvDir.exists()) {
            await venvDir.delete(recursive: true);
          }

          venvResult = await _processRunner.run(
            pythonBin,
            ['-m', 'venv', '--without-pip', 'venv'],
            workingDirectory: installDir,
          );

          if (venvResult.exitCode != 0) {
            throw Exception('Failed to create venv: ${venvResult.stderr}');
          }

          final venvPython = Platform.isWindows
              ? p.join(venvPath, 'Scripts', 'python.exe')
              : p.join(venvPath, 'bin', 'python');

          var pipBootstrap = await _processRunner.run(
            venvPython,
            ['-m', 'ensurepip', '--default-pip'],
            workingDirectory: installDir,
          );

          if (pipBootstrap.exitCode != 0) {
            debugPrint(
              '[${module.id}] ensurepip failed, downloading get-pip.py...',
            );
            final getPipPath = p.join(installDir, 'get-pip.py');
            final curlResult = await _processRunner.run(
              'curl',
              ['-sS', 'https://bootstrap.pypa.io/get-pip.py', '-o', getPipPath],
            );
            if (curlResult.exitCode == 0) {
              pipBootstrap = await _processRunner.run(
                venvPython,
                [getPipPath],
                workingDirectory: installDir,
              );
              try {
                await File(getPipPath).delete();
              } catch (_) {}
            }
            if (pipBootstrap.exitCode != 0) {
              throw Exception('Failed to bootstrap pip in venv');
            }
          }
        }
        debugPrint('[${module.id}] venv created successfully');
      } else {
        debugPrint('[${module.id}] venv already exists at $venvPath');
      }

      onProgress?.call(0.3);

      final pipPath = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'pip.exe')
          : p.join(venvPath, 'bin', 'pip');

      // Install local sibling dependencies first (e.g. Neuro-Dream-Hand for neurocnl)
      if (module.localDeps.isNotEmpty) {
        final repoRoot = p.normalize(p.join(module.directory, '..'));
        for (final dep in module.localDeps) {
          final depDir = p.join(repoRoot, dep);
          debugPrint(
            '[${module.id}] Installing local dep: $pipPath install $depDir',
          );
          final depResult = await _processRunner
              .run(pipPath, ['install', depDir], workingDirectory: installDir);
          if (depResult.exitCode != 0) {
            debugPrint(
              '[${module.id}] Local dep $dep FAILED: ${depResult.stderr}',
            );
            // Non-fatal — continue, the main install might still work
          } else {
            debugPrint('[${module.id}] Local dep $dep installed');
          }
        }
      }

      debugPrint('[${module.id}] Running: $pipPath install . (in $installDir)');
      final pipResult = await _processRunner.run(
        pipPath,
        ['install', '.'],
        workingDirectory: installDir,
      );

      if (pipResult.exitCode != 0) {
        debugPrint(
          '[${module.id}] pip install FAILED (exit ${pipResult.exitCode})',
        );
        debugPrint('[${module.id}] stderr: ${pipResult.stderr}');
        throw Exception('Failed to install dependencies: ${pipResult.stderr}');
      }

      debugPrint('[${module.id}] pip install SUCCESS');
      onProgress?.call(1.0);

      final updatedModule = module.copyWith(
        status: ModuleStatus.installed,
        installProgress: 1.0,
      );
      _updateModuleStatus(updatedModule);
      await saveModuleState(updatedModule);
    } catch (e) {
      debugPrint('[${module.id}] installModule EXCEPTION: $e');
      final updatedModule = module.copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      _updateModuleStatus(updatedModule);
      rethrow;
    }
  }

  /// Kill any leftover process listening on a port (from a previous crash/session).
  Future<void> _killProcessOnPort(int port) async {
    try {
      if (Platform.isWindows) {
        // Windows: netstat -ano | findstr :<port>
        final result = await _processRunner.run('netstat', ['-ano']);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          for (final line in lines) {
            if (line.contains(':$port') && line.contains('LISTENING')) {
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 5) {
                final pid = parts.last;
                debugPrint('Killing leftover process $pid on port $port');
                await _processRunner.run('taskkill', ['/F', '/PID', pid]);
              }
            }
          }
        }
      } else {
        // macOS/Linux: lsof -ti :<port>
        final result = await _processRunner.run('lsof', ['-ti', ':$port']);
        if (result.exitCode == 0) {
          final pids = result.stdout.toString().trim().split('\n');
          for (final pid in pids) {
            if (pid.isNotEmpty) {
              debugPrint('Killing leftover process $pid on port $port');
              Process.killPid(int.parse(pid), ProcessSignal.sigkill);
            }
          }
        }
      }
      // Brief wait for port to be released
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('Error killing process on port $port: $e');
    }
  }

  Future<void> startModule(Module module, {bool isRetry = false}) async {
    if (!module.isEnabled) return;
    if (_runningProcesses.containsKey(module.id)) return;
    final int? effectivePort = module.customPort ?? module.port;
    if (effectivePort == null) {
      throw Exception('Cannot start module ${module.id}: no port configured');
    }

    if (!isRetry) {
      _retryCounts.remove(module.id);
      _nextRetryTimes.remove(module.id);
    }
    _intentionallyStopping.remove(module.id);
    _failureStopping.remove(module.id);
    _resetHealthFailureCount(module.id);

    // Kill any zombie process from a previous session occupying our port
    await _killProcessOnPort(effectivePort);

    final installDir = _installDir(module);
    final runDir = _runDir(module);
    final venvPath = p.join(installDir, 'venv');
    final uvicornHost =
        Platform.environment['NMTK_UVICORN_HOST']?.trim().isNotEmpty == true
            ? Platform.environment['NMTK_UVICORN_HOST']!.trim()
            : '127.0.0.1';
    final pythonPath = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');

    debugPrint(
      '[${module.id}] startModule: installDir=$installDir runDir=$runDir',
    );
    debugPrint(
      '[${module.id}] startModule: pythonPath=$pythonPath target=${module.uvicornTarget} host=$uvicornHost port=$effectivePort',
    );

    // Guard: if venv doesn't exist, the module needs to be (re-)installed first
    if (!await File(pythonPath).exists()) {
      debugPrint('[${module.id}] venv python not found — installing first...');
      try {
        await installModule(module);
      } catch (e) {
        debugPrint('[${module.id}] Auto-install failed: $e');
        rethrow;
      }
      // Verify the install actually created the venv
      if (!await File(pythonPath).exists()) {
        throw Exception(
          'Install completed but venv python still not found at $pythonPath',
        );
      }
    }

    final updatedModuleStarting =
        module.copyWith(status: ModuleStatus.starting);
    _updateModuleStatus(updatedModuleStarting);
    _startupGraceDeadlines[module.id] = DateTime.now().add(
      _startupHealthGracePeriod,
    );

    final startTime = DateTime.now();

    try {
      debugPrint(
        '[${module.id}] Starting: $pythonPath -m uvicorn ${module.uvicornTarget} --host $uvicornHost --port $effectivePort --log-level ${_currentLogLevel.name}',
      );
      debugPrint('[${module.id}] Working directory: $runDir');

      final process = await _processRunner.start(
        pythonPath,
        [
          '-m',
          'uvicorn',
          module.uvicornTarget,
          '--host',
          uvicornHost,
          '--port',
          effectivePort.toString(),
          '--log-level',
          _currentLogLevel.name,
        ],
        workingDirectory: runDir,
      );

      _runningProcesses[module.id] = process;
      final controller = StreamController<String>.broadcast();
      _outputControllers[module.id] = controller;

      process.stdout.transform(utf8.decoder).listen((data) {
        controller.add(data);
        debugPrint('[${module.id}] stdout: ${data.trim()}');
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        controller.add(data);
        debugPrint('[${module.id}] stderr: ${data.trim()}');
      });

      unawaited(
        process.exitCode.then((code) {
          _runningProcesses.remove(module.id);
          unawaited(
              AnalyticsService().trackEvent('module_process_exit', properties: {
            'moduleId': module.id,
            'exitCode': code,
          }));
          _outputControllers[module.id]?.close();
          _outputControllers.remove(module.id);

          final wasIntentionalStop = _intentionallyStopping.remove(module.id);
          final wasFailureStop = _failureStopping.remove(module.id);
          final currentModule = _currentModuleState(module.id, module);
          _startupGraceDeadlines.remove(module.id);

          if (wasIntentionalStop) {
            final updatedModuleStopped = currentModule.copyWith(
              status: ModuleStatus.installed,
              healthStatus: null,
            );
            _updateModuleStatus(updatedModuleStopped);
            return;
          }

          if (wasFailureStop) {
            return;
          }

          _resetHealthFailureCount(module.id);
          final exitMessage = code == 0
              ? 'Process exited unexpectedly'
              : 'Process exited with code $code';
          final updatedModuleStopped = currentModule.copyWith(
            status: ModuleStatus.error,
            healthStatus: exitMessage,
          );
          _updateModuleStatus(updatedModuleStopped);
          _scheduleRetry(updatedModuleStopped);
        }),
      );

      final success = await _waitForHealthyStartup(module);

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      unawaited(
          AnalyticsService().trackEvent('module_startup_metric', properties: {
        'moduleId': module.id,
        'durationMs': duration,
        'success': success,
      }));
    } catch (e) {
      final updatedModuleError = module.copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      _updateModuleStatus(updatedModuleError);
      rethrow;
    }
  }

  Future<bool> _waitForHealthyStartup(Module module) async {
    final deadline = _startupGraceDeadlines[module.id] ??
        DateTime.now().add(_startupHealthGracePeriod);

    while (true) {
      final success = await _checkHealth(module);
      if (success) {
        _startupGraceDeadlines.remove(module.id);
        return true;
      }

      final currentModule = _currentModuleState(module.id, module);
      if (currentModule.status == ModuleStatus.error ||
          !_runningProcesses.containsKey(module.id)) {
        return false;
      }

      if (DateTime.now().isAfter(deadline)) {
        return false;
      }

      await Future<void>.delayed(_startupHealthProbeInterval);
    }
  }

  Future<void> stopModule(String moduleId, {bool isFailure = false}) async {
    if (!isFailure) {
      _intentionallyStopping.add(moduleId);
      _retryCounts.remove(moduleId);
      _nextRetryTimes.remove(moduleId);
      _consecutiveHealthFailures.remove(moduleId);
    }
    _startupGraceDeadlines.remove(moduleId);

    final process = _runningProcesses[moduleId];
    if (process == null) {
      if (!isFailure) {
        _intentionallyStopping.remove(moduleId);
      }
      return;
    }

    process.kill(ProcessSignal.sigterm);

    // Wait for process to exit
    final exitFuture = process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await exitFuture;
  }

  Future<bool> _checkHealth(Module module) async {
    final effectivePort = module.customPort ?? module.port;
    if (effectivePort == null) return false;
    final currentModule = _currentModuleState(module.id, module);
    try {
      final uri = Uri.parse('http://127.0.0.1:$effectivePort/health');
      final response = await _probeHealth(uri, currentModule.id);
      final body = response.body;
      final statusCode = response.statusCode;

      ModuleStatus newStatus;
      String? healthInfo;

      if (statusCode == 200) {
        newStatus = ModuleStatus.running;
        healthInfo = body;
        _resetHealthFailureCount(currentModule.id);
      } else if (statusCode == 503) {
        newStatus = ModuleStatus.degraded;
        healthInfo = body;
        _resetHealthFailureCount(currentModule.id);
      } else if (statusCode == 404) {
        // Server is running but has no /health endpoint — treat as running
        newStatus = ModuleStatus.running;
        healthInfo = 'No /health endpoint (server is up)';
        _resetHealthFailureCount(currentModule.id);
      } else {
        await _recordHealthFailure(
          currentModule,
          'Health check returned HTTP $statusCode',
        );
        return false;
      }

      if (currentModule.status != newStatus ||
          currentModule.healthStatus != healthInfo) {
        debugPrint(
          '[${currentModule.id}] Health status changed: '
          '${currentModule.status} -> $newStatus',
        );
        final updatedModule = currentModule.copyWith(
          status: newStatus,
          healthStatus: healthInfo,
        );
        _updateModuleStatus(updatedModule);
      }
      return statusCode == 200 || statusCode == 404;
    } catch (e) {
      debugPrint('[${currentModule.id}] Health check error: $e');
      await _recordHealthFailure(currentModule, 'Health probe error: $e');
      return false;
    }
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    debugPrint(
      'Starting health polling every 5 seconds for ${_modules.length} modules',
    );
    _healthTimer =
        Timer.periodic(const Duration(seconds: 5), (Timer timer) async {
      for (var module in _modules) {
        if (!module.isEnabled) continue;
        if (_runningProcesses.containsKey(module.id)) {
          debugPrint('Polling health for ${module.id}');
          unawaited(_checkHealth(module));
        } else if (module.status == ModuleStatus.error) {
          final nextRetry = _nextRetryTimes[module.id];
          if (nextRetry != null && DateTime.now().isAfter(nextRetry)) {
            debugPrint('Retrying module ${module.id}');
            unawaited(startModule(module, isRetry: true));
          }
        }
      }
    });
  }

  Future<void> saveModuleState(Module module) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'module_states.json'));

      Map<String, dynamic> states = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic decoded = jsonDecode(content);
        states = decoded as Map<String, dynamic>;
      }

      states[module.id] = module.toJson();
      await file.writeAsString(
        jsonEncode(states),
      );
    } catch (e) {
      debugPrint('Error saving module state: $e');
    }
  }

  Future<void> _loadState(List<Module> modules) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'module_states.json'));

      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic decoded = jsonDecode(content);
        final states = decoded as Map<String, dynamic>;
        for (var i = 0; i < modules.length; i++) {
          if (states.containsKey(modules[i].id)) {
            final saved = states[modules[i].id] as Map<String, dynamic>;
            final savedStatus = saved['status'] as int?;
            // Restore version and pinning info
            final savedVersion = saved['version'] as String?;
            final savedPinned = saved['versionPinned'] as bool?;

            // Only restore installation status, not runtime status or paths.
            // Paths are always freshly resolved from BundleManager + modules.json.
            if (savedStatus != null) {
              final status = ModuleStatus.values[savedStatus];
              if (status == ModuleStatus.installed ||
                  status == ModuleStatus.running ||
                  status == ModuleStatus.degraded ||
                  status == ModuleStatus.error ||
                  status == ModuleStatus.updating) {
                modules[i] = modules[i].copyWith(
                  status: ModuleStatus.installed,
                  installProgress: 1.0,
                  version: savedVersion,
                  versionPinned: savedPinned,
                );
              } else {
                modules[i] = modules[i].copyWith(
                  version: savedVersion,
                  versionPinned: savedPinned,
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading module state: $e');
    }
  }

  Future<void> updateModule(
    Module module, {
    void Function(double)? onProgress,
  }) async {
    final moduleId = module.id;
    debugPrint('[$moduleId] Updating module...');

    // 1. Stop if running
    if (_runningProcesses.containsKey(moduleId)) {
      await stopModule(moduleId);
    }

    final moduleDir = _installDir(module);
    final backupDir = '$moduleDir.bak';
    final env = BundleManager().env;

    try {
      // 2. Backup current directory
      onProgress?.call(0.1);
      if (env.directoryExists(moduleDir)) {
        if (env.directoryExists(backupDir)) {
          await env.deleteDirectory(backupDir, recursive: true);
        }
        // Simple rename for backup
        await env.renameDirectory(moduleDir, backupDir);
      }

      // 3. Re-create directory and "download" (simulate by copying back or just re-installing)
      // In a real app, this would be a git pull or download.
      // Here we'll recreate the dir and run install.
      await env.createDirectory(moduleDir, recursive: true);

      // Restore some files from backup for simulation if needed, but here we just re-install
      // To simulate "remote" update, we can just copy backup back but pretend it's new
      // (Actually, installModule expects the source to be there).
      // Let's copy the backup back to moduleDir to simulate "downloaded" source.
      await _copyDirectoryEnv(backupDir, moduleDir, env);

      onProgress?.call(0.3);

      // 4. Install new version
      // We pass a modified module with the new version
      final updatedModule = module.copyWith(
        version: module.remoteVersion,
        status: ModuleStatus.updating,
      );
      _updateModuleStatus(updatedModule);

      await installModule(updatedModule,
          onProgress: (p) => onProgress?.call(0.3 + p * 0.5));

      // 5. Verify with health check
      onProgress?.call(0.9);
      await startModule(updatedModule);

      // Wait for health check to stabilize
      await Future<void>.delayed(const Duration(seconds: 5));

      final index = _modules.indexWhere((m) => m.id == moduleId);
      if (index != -1 && _modules[index].status == ModuleStatus.running) {
        // Success! Clean up backup
        if (env.directoryExists(backupDir)) {
          await env.deleteDirectory(backupDir, recursive: true);
        }
        onProgress?.call(1.0);
        debugPrint('[$moduleId] Update successful and verified.');
      } else {
        throw Exception('Health check failed after update');
      }
    } catch (e) {
      debugPrint('[$moduleId] Update failed: $e. Rolling back...');
      // 6. Rollback
      if (_runningProcesses.containsKey(moduleId)) {
        await stopModule(moduleId);
      }

      if (env.directoryExists(moduleDir)) {
        await env.deleteDirectory(moduleDir, recursive: true);
      }

      if (env.directoryExists(backupDir)) {
        await env.renameDirectory(backupDir, moduleDir);
      }

      final rolledBackModule = module.copyWith(
        status: ModuleStatus.installed,
        healthStatus: 'Update failed: $e. Rolled back to ${module.version}',
      );
      _updateModuleStatus(rolledBackModule);
      await saveModuleState(rolledBackModule);
      rethrow;
    }
  }

  Future<void> _copyDirectoryEnv(
      String source, String destination, BundleEnvironment env) async {
    await env.createDirectory(destination, recursive: true);
    await for (final entity in env.listDirectory(source, recursive: false)) {
      final newPath = p.join(destination, p.basename(entity.path));
      if (entity is File) {
        await env.copyFile(entity.path, newPath);
      } else if (entity is Directory) {
        await _copyDirectoryEnv(entity.path, newPath, env);
      }
    }
  }

  Stream<String>? getOutput(String moduleId) {
    return _outputControllers[moduleId]?.stream;
  }
}
