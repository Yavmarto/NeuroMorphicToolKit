import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:path/path.dart' as p;

class ModuleProvider with ChangeNotifier {
  final ProcessManager _processManager = ProcessManager();

  List<Module> _modules = [];
  bool _isLoading = true;
  String? _error;
  final List<String> _activeModuleIds = [];

  ModuleProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      // Load modules from JSON manifest
      final jsonString = await rootBundle.loadString('assets/modules.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _modules = jsonList.map((json) => Module.fromJson(json)).toList();

      // Resolve directories to absolute paths relative to repo root.
      // The flutter app is in nmtk/neuro_toolkit, so modules are at ../../<dir>.
      for (var i = 0; i < _modules.length; i++) {
        _modules[i] = _modules[i].copyWith(
          directory: p.normalize(p.join(p.current, '..', '..', _modules[i].directory)),
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

      _isLoading = false;
    } catch (e) {
      _error = 'Failed to load modules: $e';
      _isLoading = false;
    }
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
      _modules.where((m) =>
        m.status == ModuleStatus.notInstalled ||
        m.status == ModuleStatus.installing
      ).toList();

  List<String> get activeModuleIds => _activeModuleIds;

  List<Module> get activeModules => _activeModuleIds
      .map((id) => _modules.firstWhere((m) => m.id == id))
      .toList();

  bool isMuJoCoAvailable() {
    try {
      final result = Process.runSync('which', ['mujoco']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

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
    }
  }

  Future<void> launchModule(String moduleId) async {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    // Add to active tabs for workspace view
    if (!_activeModuleIds.contains(moduleId)) {
      _activeModuleIds.add(moduleId);
    }
    notifyListeners();

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
    _activeModuleIds.remove(moduleId);
    notifyListeners();

    try {
      await _processManager.stopModule(moduleId);
    } catch (e) {
      debugPrint('Stop failed for $moduleId: $e');
    }
  }

  Future<void> uninstallModule(String moduleId) async {
    final index = _modules.indexWhere((m) => m.id == moduleId);
    if (index != -1) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.notInstalled,
        installProgress: 0.0,
        healthStatus: null,
      );
      _activeModuleIds.remove(moduleId);
      notifyListeners();
    }
  }

  void closeTab(String moduleId) {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

  Stream<String>? getModuleOutput(String moduleId) {
    return _processManager.getOutput(moduleId);
  }
}
