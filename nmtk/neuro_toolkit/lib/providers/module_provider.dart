import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

class ModuleProvider with ChangeNotifier {
  final ProcessManager _processManager = ProcessManager();

  final List<Module> _modules = [
    Module(
      id: 'neurocnl',
      name: 'neurocnl',
      description: 'Controlled Natural Language specifications compiler.',
      directory: 'neurocnl',
      port: 8000,
    ),
    Module(
      id: 'Neurosim',
      name: 'Neurosim',
      description: 'Neuromorphic simulator for hardware-accurate modeling.',
      directory: 'Neurosim',
      port: 8001,
    ),
    Module(
      id: 'Neurochip',
      name: 'Neurochip',
      description: 'Hardware abstraction layer for neuromorphic chips.',
      directory: 'Neurochip',
      port: 8002,
    ),
    Module(
      id: 'Neurobench',
      name: 'Neurobench',
      description: 'Benchmarking suite for neuromorphic algorithms.',
      directory: 'Neurobench',
      port: 8003,
    ),
    Module(
      id: 'Neurosense',
      name: 'Neurosense',
      description: 'Sensing and perception modules for neuromorphic systems.',
      directory: 'Neurosense',
      port: 8004,
    ),
    Module(
      id: 'Neurohub',
      name: 'Neurohub',
      description: 'Data management and collaboration hub.',
      directory: 'Neurohub',
      port: 8005,
    ),
  ];

  ModuleProvider() {
    _init();
  }

  Future<void> _init() async {
    // Correct directories to be absolute paths relative to repo root
    // In this environment, we are at the repo root.
    // The flutter app is in nmtk/neuro_toolkit.
    // So the modules are at ../../<module_name>

    for (var i = 0; i < _modules.length; i++) {
       _modules[i] = _modules[i].copyWith(
         directory: p.normalize(p.absolute('../../', _modules[i].directory))
       );
    }

    await _processManager.init(_modules);

    _processManager.statusUpdates.listen((updatedModule) {
      final index = _modules.indexWhere((m) => m.id == updatedModule.id);
      if (index != -1) {
        _modules[index] = updatedModule;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  List<Module> get modules => _modules;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Module> get installedModules =>
      _modules.where((m) =>
        m.status == ModuleStatus.installed ||
        m.status == ModuleStatus.starting ||
        m.status == ModuleStatus.running ||
        m.status == ModuleStatus.stopping ||
        m.status == ModuleStatus.degraded ||
        m.status == ModuleStatus.error
      ).toList();

  List<Module> get availableModules =>
      _modules.where((m) => m.status == ModuleStatus.notInstalled || m.status == ModuleStatus.installing).toList();

  Future<void> installModule(String moduleId) async {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.installing,
      installProgress: 0.0,
    );
    notifyListeners();

    try {
      await _processManager.installModule(
        _modules[index],
        onProgress: (progress) {
          _modules[index] = _modules[index].copyWith(installProgress: progress);
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Installation failed for $moduleId: $e');
      // Status is updated via stream in _init
    }
  }

  Future<void> launchModule(String moduleId) async {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    try {
      await _processManager.startModule(_modules[index]);
    } catch (e) {
      debugPrint('Launch failed for $moduleId: $e');
    }
  }

  Future<void> stopModule(String moduleId) async {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    _modules[index] = _modules[index].copyWith(status: ModuleStatus.stopping);
    notifyListeners();

    try {
      await _processManager.stopModule(moduleId);
    } catch (e) {
      debugPrint('Stop failed for $moduleId: $e');
    }
  }

  Future<void> uninstallModule(String moduleId) async {
    // For now, just reset the state. In a real app, we might delete the venv.
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.notInstalled,
        installProgress: 0.0,
        healthStatus: null,
      );
      notifyListeners();
      await _processManager.saveModuleState(_modules[index]);
    }
  }

  Stream<String>? getModuleOutput(String moduleId) {
    return _processManager.getOutput(moduleId);
  }
}
