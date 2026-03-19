import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/module.dart';

class ModuleProvider with ChangeNotifier {
  final List<Module> _modules = [
    Module(
      id: 'neurocnl',
      name: 'NeuroCNL',
      description:
          'Translates plain-English specifications into verified Spiking Neural Networks (SNNs).',
    ),
    Module(
      id: 'neurosim',
      name: 'Neurosim',
      description:
          'A robust simulation environment to test neuromorphic models before physical deployment.',
    ),
    Module(
      id: 'neurosense',
      name: 'Neurosense',
      description:
          'Sensory processing and encoding. Converts traditional data modalities into spike trains.',
    ),
    Module(
      id: 'neurochip',
      name: 'Neurochip',
      description: 'Interfacing directly with neuromorphic hardware backends.',
    ),
    Module(
      id: 'neurobench',
      name: 'Neurobench',
      description:
          'Standardized benchmarking and testing of neuromorphic models and hardware configurations.',
    ),
    Module(
      id: 'neurohub',
      name: 'Neurohub',
      description:
          'A central repository for sharing pre-trained neuromorphic models, datasets, and configurations.',
    ),
    Module(
      id: 'neuro_dream_hand',
      name: 'Neuro-Dream-Hand',
      description:
          'Applied hardware robotics and edge integration (e.g., controlling a robotic hand via SNNs).',
    ),
  ];

  List<Module> get modules => _modules;

  List<Module> get installedModules =>
      _modules.where((m) => m.status == ModuleStatus.installed).toList();

  List<Module> get availableModules =>
      _modules.where((m) => m.status != ModuleStatus.installed).toList();

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
      );
      notifyListeners();
    }
  }
}
