import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/models/module.dart';

class ModuleProvider with ChangeNotifier {
  List<Module> _modules = [];
  bool _isLoading = false;
  String? _error;

  ModuleProvider() {
    loadModules();
  }

  List<Module> get modules => _modules;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Module> get installedModules =>
      _modules.where((m) => m.status == ModuleStatus.installed || m.status == ModuleStatus.running).toList();

  List<Module> get availableModules =>
      _modules.where((m) => m.status == ModuleStatus.notInstalled || m.status == ModuleStatus.installing).toList();

  Future<void> loadModules() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final String response = await rootBundle.loadString('assets/modules.json');
      final List<dynamic> data = json.decode(response);
      _modules = data.map((json) => Module.fromJson(json as Map<String, dynamic>)).toList();

      // For POC, simulate some modules being installed
      for (int i = 0; i < _modules.length; i++) {
        if (_modules[i].id == 'neurocnl' || _modules[i].id == 'neuro_dream_hand') {
           _modules[i].status = ModuleStatus.installed;
        }
      }

    } catch (e) {
      _error = 'Failed to load modules: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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

  // Mock method to check MuJoCo availability
  bool isMuJoCoAvailable() {
    return false; // Mocking as unavailable for now
  }
}
