import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/bundle_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ProcessManager {
  static final ProcessManager _instance = ProcessManager._internal();
  factory ProcessManager() => _instance;
  ProcessManager._internal();

  final Map<String, Process> _runningProcesses = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  Timer? _healthTimer;
  bool _initialized = false;
  List<Module> _modules = [];

  // Stream for status updates
  final _statusController = StreamController<Module>.broadcast();
  Stream<Module> get statusUpdates => _statusController.stream;

  Future<void> init(List<Module> modules) async {
    if (_initialized) return;
    _modules = modules;
    await _loadState(_modules);
    _startHealthPolling();
    _initialized = true;
  }

  void dispose() {
    _healthTimer?.cancel();
    _statusController.close();
    for (var controller in _outputControllers.values) {
      controller.close();
    }
  }

  /// The directory containing pyproject.toml for a given module.
  String _installDir(Module module) {
    return p.normalize(p.join(module.directory, module.sourcePath));
  }

  Future<void> installModule(Module module, {Function(double)? onProgress}) async {
    final installDir = _installDir(module);
    final moduleDir = Directory(installDir);
    if (!await moduleDir.exists()) {
      throw Exception('Module directory not found: $installDir');
    }

    final venvPath = p.join(installDir, 'venv');
    final venvDir = Directory(venvPath);

    try {
      if (!await venvDir.exists()) {
        onProgress?.call(0.1);

        final pythonBin = await BundleManager().pythonPath;

        // Try normal venv creation first
        var venvResult = await Process.run(
          pythonBin,
          ['-m', 'venv', 'venv'],
          workingDirectory: installDir,
        );

        if (venvResult.exitCode != 0) {
          // Fallback: create venv without pip, then bootstrap pip separately.
          // This handles cases where ensurepip is broken (e.g. missing wheels).
          debugPrint('Normal venv failed, trying --without-pip fallback...');
          // Clean up partial venv if any
          if (await venvDir.exists()) {
            await venvDir.delete(recursive: true);
          }

          venvResult = await Process.run(
            pythonBin,
            ['-m', 'venv', '--without-pip', 'venv'],
            workingDirectory: installDir,
          );

          if (venvResult.exitCode != 0) {
            throw Exception('Failed to create venv: ${venvResult.stderr}');
          }

          // Bootstrap pip into the venv
          final venvPython = Platform.isWindows
              ? p.join(venvPath, 'Scripts', 'python.exe')
              : p.join(venvPath, 'bin', 'python');

          // Try ensurepip first (it may work inside the venv even if it failed during venv creation)
          var pipBootstrap = await Process.run(
            venvPython,
            ['-m', 'ensurepip', '--default-pip'],
            workingDirectory: installDir,
          );

          if (pipBootstrap.exitCode != 0) {
            // Last resort: download get-pip.py
            debugPrint('ensurepip failed, downloading get-pip.py...');
            final getPipPath = p.join(installDir, 'get-pip.py');
            final curlResult = await Process.run(
              'curl',
              ['-sS', 'https://bootstrap.pypa.io/get-pip.py', '-o', getPipPath],
            );
            if (curlResult.exitCode == 0) {
              pipBootstrap = await Process.run(
                venvPython,
                [getPipPath],
                workingDirectory: installDir,
              );
              // Clean up get-pip.py
              try { await File(getPipPath).delete(); } catch (_) {}
            }
            if (pipBootstrap.exitCode != 0) {
              throw Exception('Failed to bootstrap pip in venv');
            }
          }
        }
      }

      onProgress?.call(0.3);

      final pipPath = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'pip.exe')
          : p.join(venvPath, 'bin', 'pip');

      // Use non-editable install. Editable (-e) fails with poetry-core
      // projects where the package dir name matches the project dir name.
      final pipResult = await Process.run(
        pipPath,
        ['install', '.'],
        workingDirectory: installDir,
      );

      if (pipResult.exitCode != 0) {
        throw Exception('Failed to install dependencies: ${pipResult.stderr}');
      }

      onProgress?.call(1.0);

      final updatedModule = module.copyWith(
        status: ModuleStatus.installed,
        installProgress: 1.0,
      );
      _statusController.add(updatedModule);
      await saveModuleState(updatedModule);
    } catch (e) {
      final updatedModule = module.copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      _statusController.add(updatedModule);
      rethrow;
    }
  }

  Future<void> startModule(Module module) async {
    if (_runningProcesses.containsKey(module.id)) return;
    if (module.port == null) {
      throw Exception('Cannot start module ${module.id}: no port configured');
    }

    final installDir = _installDir(module);
    final venvPath = p.join(installDir, 'venv');
    final pythonPath = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');

    final updatedModuleStarting = module.copyWith(status: ModuleStatus.starting);
    _statusController.add(updatedModuleStarting);

    try {
      final process = await Process.start(
        pythonPath,
        ['-m', 'uvicorn', module.uvicornTarget, '--port', (module.port ?? 8000).toString()],
        workingDirectory: installDir,
      );

      _runningProcesses[module.id] = process;
      final controller = StreamController<String>.broadcast();
      _outputControllers[module.id] = controller;

      process.stdout.transform(utf8.decoder).listen((data) {
        controller.add(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        controller.add(data);
      });

      process.exitCode.then((code) {
        _runningProcesses.remove(module.id);
        _outputControllers[module.id]?.close();
        _outputControllers.remove(module.id);

        final updatedModuleStopped = module.copyWith(
          status: code == 0 ? ModuleStatus.installed : ModuleStatus.error,
          healthStatus: code == 0 ? null : 'Process exited with code $code',
        );
        _statusController.add(updatedModuleStopped);
      });

      // Give it some time to start up
      await Future.delayed(const Duration(seconds: 2));
      await _checkHealth(module);
    } catch (e) {
      final updatedModuleError = module.copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      _statusController.add(updatedModuleError);
      rethrow;
    }
  }

  Future<void> stopModule(String moduleId) async {
    final process = _runningProcesses[moduleId];
    if (process == null) return;

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

  Future<void> _checkHealth(Module module) async {
    if (module.port == null) return;
    try {
      final response = await http
          .get(Uri.parse('http://localhost:${module.port}/health'))
          .timeout(const Duration(seconds: 2));

      ModuleStatus newStatus;
      String? healthInfo;

      if (response.statusCode == 200) {
        newStatus = ModuleStatus.running;
        healthInfo = response.body;
      } else if (response.statusCode == 503) {
        newStatus = ModuleStatus.degraded;
        healthInfo = response.body;
      } else {
        newStatus = ModuleStatus.error;
        healthInfo = 'Health check failed: ${response.statusCode}';
      }

      if (module.status != newStatus || module.healthStatus != healthInfo) {
        final updatedModule = module.copyWith(
          status: newStatus,
          healthStatus: healthInfo,
        );
        _statusController.add(updatedModule);
      }
    } catch (e) {
      if (module.status == ModuleStatus.running ||
          module.status == ModuleStatus.starting) {
        final updatedModule = module.copyWith(
          status: ModuleStatus.error,
          healthStatus: 'Health check error: $e',
        );
        _statusController.add(updatedModule);
      }
    }
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      for (var module in _modules) {
        if (_runningProcesses.containsKey(module.id)) {
          _checkHealth(module);
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
        states = jsonDecode(await file.readAsString());
      }

      states[module.id] = module.toJson();
      await file.writeAsString(jsonEncode(states));
    } catch (e) {
      debugPrint('Error saving module state: $e');
    }
  }

  Future<void> _loadState(List<Module> modules) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'module_states.json'));

      if (await file.exists()) {
        final states = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (var i = 0; i < modules.length; i++) {
          if (states.containsKey(modules[i].id)) {
            final saved = states[modules[i].id] as Map<String, dynamic>;
            final savedStatus = saved['status'] as int?;
            // Only restore installation status, not runtime status or paths.
            // Paths are always freshly resolved from BundleManager + modules.json.
            if (savedStatus != null) {
              final status = ModuleStatus.values[savedStatus];
              if (status == ModuleStatus.installed ||
                  status == ModuleStatus.running ||
                  status == ModuleStatus.degraded ||
                  status == ModuleStatus.error) {
                modules[i].status = ModuleStatus.installed;
                modules[i].installProgress = 1.0;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading module state: $e');
    }
  }

  Stream<String>? getOutput(String moduleId) {
    return _outputControllers[moduleId]?.stream;
  }
}
