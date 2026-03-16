import 'package:flutter/foundation.dart';
import '../models/module.dart';

class ModuleProvider with ChangeNotifier {
  final List<Module> _modules = [
    Module(
      id: 'neuro_dream_hand',
      name: 'Neuro-Dream-Hand',
      description: 'Neuromorphic simulation framework for prosthetic hand control.',
    ),
    Module(
      id: 'neurocnl',
      name: 'neurocnl',
      description: 'Controlled Natural Language specifications compiler.',
    ),
    Module(
      id: 'nmtk',
      name: 'nmtk',
      description: 'Neuromorphic Toolkit hub for utilities.',
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
      await Future.delayed(const Duration(milliseconds: 300));
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
