import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/module.dart';

class ModuleProvider with ChangeNotifier {
  final List<Module> _modules = [
    Module(
      id: 'neurocnl',
      name: 'neurocnl',
      description: 'Controlled Natural Language specifications compiler.',
      port: 8000,
      hasFrontend: true,
    ),
    Module(
      id: 'neurosim',
      name: 'Neurosim',
      description: 'Spiking Neural Network simulator and visualizer.',
      port: 8001,
      hasFrontend: true,
    ),
    Module(
      id: 'neurochip',
      name: 'Neurochip',
      description: 'Neuromorphic hardware deployment and quantization tool.',
      port: 8002,
    ),
    Module(
      id: 'neurobench',
      name: 'Neurobench',
      description: 'Benchmarking framework for neuromorphic systems.',
      port: 8003,
    ),
    Module(
      id: 'neurosense',
      name: 'Neurosense',
      description: 'Sensor data encoding and processing suite.',
      port: 8004,
      hasFrontend: true,
    ),
    Module(
      id: 'neurohub',
      name: 'Neurohub',
      description: 'Central asset management and workflow orchestration.',
      port: 8005,
    ),
    Module(
      id: 'neuro_dream_hand',
      name: 'Neuro-Dream-Hand',
      description: 'Neuromorphic simulation framework for prosthetic hand control.',
      port: 8006,
    ),
  ];

  final List<String> _activeModuleIds = [];

  List<Module> get modules => _modules;

  List<Module> get installedModules =>
      _modules.where((m) => m.status == ModuleStatus.installed).toList();

  List<Module> get availableModules =>
      _modules.where((m) => m.status != ModuleStatus.installed).toList();

  List<String> get activeModuleIds => _activeModuleIds;

  List<Module> get activeModules => _activeModuleIds
      .map((id) => _modules.firstWhere((m) => m.id == id))
      .toList();

  Future<void> installModule(String moduleId) async {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    // Start installation
    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.installing,
      installProgress: 0.0,
    );
    notifyListeners();

    // Mock installation process
    for (int i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _modules[index] = _modules[index].copyWith(installProgress: i / 10.0);
      notifyListeners();
    }

    // Complete installation
    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.installed,
      installProgress: 1.0,
    );
    notifyListeners();
  }

  void uninstallModule(String moduleId) {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.notInstalled,
        installProgress: 0.0,
        isLaunched: false,
      );
      _activeModuleIds.remove(moduleId);
      notifyListeners();
    }
  }

  void launchModule(String moduleId) {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    if (!_modules[index].isLaunched) {
      _modules[index] = _modules[index].copyWith(isLaunched: true);
    }

    if (!_activeModuleIds.contains(moduleId)) {
      _activeModuleIds.add(moduleId);
    }
    notifyListeners();
  }

  void closeTab(String moduleId) {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

  void stopModule(String moduleId) {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _modules[index] = _modules[index].copyWith(isLaunched: false);
      _activeModuleIds.remove(moduleId);
      notifyListeners();
    }
  }
}
