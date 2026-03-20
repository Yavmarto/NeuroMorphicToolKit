import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';
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

  Future<void> installModule(Module module, {Function(double)? onProgress}) async {
    final moduleDir = Directory(module.directory);
    if (!await moduleDir.exists()) {
      throw Exception('Module directory not found: ${module.directory}');
    }

    final venvPath = p.join(module.directory, 'venv');
    final venvDir = Directory(venvPath);

    try {
      if (!await venvDir.exists()) {
        onProgress?.call(0.1);

        ProcessResult venvResult;
        try {
          venvResult = await Process.run(
            'python3',
            ['-m', 'venv', 'venv'],
            workingDirectory: module.directory,
          );
        } catch (_) {
          // Fallback to 'python' for Windows or environments without 'python3' alias
           venvResult = await Process.run(
            'python',
            ['-m', 'venv', 'venv'],
            workingDirectory: module.directory,
          );
        }

        if (venvResult.exitCode != 0) {
          throw Exception('Failed to create venv: ${venvResult.stderr}');
        }
      }

      onProgress?.call(0.3);

      final pipPath = Platform.isWindows
          ? p.join(venvPath, 'Scripts', 'pip.exe')
          : p.join(venvPath, 'bin', 'pip');

      final pipResult = await Process.run(
        pipPath,
        ['install', '-e', '.'],
        workingDirectory: module.directory,
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

    final venvPath = p.join(module.directory, 'venv');
    final pythonPath = Platform.isWindows
        ? p.join(venvPath, 'Scripts', 'python.exe')
        : p.join(venvPath, 'bin', 'python');

    final updatedModuleStarting = module.copyWith(status: ModuleStatus.starting);
    _statusController.add(updatedModuleStarting);

    try {
      final process = await Process.start(
        pythonPath,
        ['-m', 'uvicorn', 'app.main:app', '--port', module.port.toString()],
        workingDirectory: module.directory,
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
            final savedModule = Module.fromJson(states[modules[i].id]);
            // Only keep installation status, not runtime status
            if (savedModule.status == ModuleStatus.installed ||
                savedModule.status == ModuleStatus.running ||
                savedModule.status == ModuleStatus.degraded ||
                savedModule.status == ModuleStatus.error) {
              modules[i].status = ModuleStatus.installed;
              modules[i].installProgress = 1.0;
            } else {
               modules[i].status = savedModule.status;
               modules[i].installProgress = savedModule.installProgress;
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
