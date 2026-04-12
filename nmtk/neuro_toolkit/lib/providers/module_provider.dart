import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:neuro_toolkit/services/update_service.dart';

class ModuleProvider with ChangeNotifier {
  ModuleProvider({
    ProcessManager? processManager,
    UpdateService? updateService,
    ControlApiService? controlApiService,
  }) {
    _updateService = updateService ?? UpdateService();
    _controlApiService = controlApiService ?? ControlApiService();
    _legacyProcessManager = processManager;
    _init();
  }

  late final UpdateService _updateService;
  late final ControlApiService _controlApiService;
  ProcessManager? _legacyProcessManager;
  LauncherUpdate? _pendingLauncherUpdate;
  Timer? _refreshTimer;

  @visibleForTesting
  List<Module> modulesForTesting = [];

  List<Module> get _modules =>
      modulesForTesting.isEmpty ? _internalModules : modulesForTesting;
  set _modules(List<Module> value) => _internalModules = value;

  List<Module> _internalModules = [];
  bool _isLoading = true;
  bool _pythonAvailable = true;
  bool _mujocoAvailable = true;
  String? _error;
  final List<String> _activeModuleIds = [];
  SettingsProvider? _settingsProvider;

  void updateSettingsProvider(SettingsProvider settingsProvider) {
    _settingsProvider = settingsProvider;
    unawaited(_syncServerSettings());
  }

  Future<void> _init() async {
    try {
      if (_legacyProcessManager != null) {
        _legacyProcessManager!.statusUpdates.listen((updatedModule) {
          final index =
              _modules.indexWhere((module) => module.id == updatedModule.id);
          if (index != -1) {
            _modules[index] = updatedModule;
            notifyListeners();
          }
        });
        return;
      }
      await _reloadFromControlApi(includeLauncherUpdate: true);
      _startRefreshTimer();
    } catch (e) {
      _error = 'Failed to load modules: $e';
      _pythonAvailable = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Module> get modules => _modules;

  @visibleForTesting
  set modules(List<Module> value) {
    _modules = value;
    notifyListeners();
  }

  bool get isLoading => _isLoading;
  bool get pythonAvailable => _pythonAvailable;
  String? get error => _error;
  LauncherUpdate? get pendingLauncherUpdate => _pendingLauncherUpdate;
  UpdateChannel get currentChannel => _updateService.channel;

  List<Module> get installedModules => _modules
      .where(
        (Module module) =>
            module.status == ModuleStatus.installed ||
            module.status == ModuleStatus.starting ||
            module.status == ModuleStatus.running ||
            module.status == ModuleStatus.stopping ||
            module.status == ModuleStatus.degraded ||
            module.status == ModuleStatus.error,
      )
      .toList();

  List<Module> get availableModules => _modules
      .where(
        (Module module) =>
            module.status == ModuleStatus.notInstalled ||
            module.status == ModuleStatus.installing,
      )
      .toList();

  List<String> get activeModuleIds => _activeModuleIds;

  List<Module> get activeModules => _activeModuleIds
      .map((String id) =>
          _modules.firstWhere((Module module) => module.id == id))
      .toList();

  bool isMuJoCoAvailable() => _mujocoAvailable;

  Future<void> recheckPython() async {
    _isLoading = true;
    notifyListeners();
    if (_legacyProcessManager != null) {
      await Future<void>.delayed(Duration.zero);
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _error = 'Failed to load modules: $e';
      _pythonAvailable = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
  }) async {
    final index = _modules.indexWhere((module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(
      isEnabled: isEnabled,
      customPort: customPort,
    );
    notifyListeners();

    if (_settingsProvider != null) {
      final settingsToSave = <String, dynamic>{};
      if (isEnabled != null) {
        settingsToSave['isEnabled'] = isEnabled;
      }
      if (customPort != null) {
        settingsToSave['customPort'] = customPort;
      }
      await _settingsProvider!.updateModuleSettings(moduleId, settingsToSave);
    }

    if (isEnabled == false) {
      await stopModule(moduleId);
    }

    try {
      _modules[index] = await _controlApiService.updateModuleSettings(
        moduleId,
        isEnabled: isEnabled,
        customPort: customPort,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update remote module settings: $e');
    }
  }

  Future<void> installModule(String moduleId) async {
    final index = _modules.indexWhere((Module module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.installing,
      installProgress: 0.0,
      healthStatus: null,
    );
    notifyListeners();

    try {
      if (_legacyProcessManager != null) {
        await _legacyProcessManager!.installModule(
          _modules[index],
          onProgress: (double progress) {
            _modules[index] = _modules[index].copyWith(
              installProgress: progress,
            );
            notifyListeners();
          },
        );
        return;
      }
      _modules[index] = await _controlApiService.installModule(moduleId);
      notifyListeners();
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      notifyListeners();
      debugPrint('Installation failed for $moduleId: $e');
    }
  }

  Future<void> launchModule(String moduleId) async {
    final index = _modules.indexWhere((Module module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    if (!_activeModuleIds.contains(moduleId)) {
      _activeModuleIds.add(moduleId);
    }
    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.starting,
      healthStatus: null,
    );
    notifyListeners();

    try {
      if (_legacyProcessManager != null) {
        await _legacyProcessManager!.startModule(_modules[index]);
        return;
      }
      _modules[index] = await _controlApiService.startModule(moduleId);
      notifyListeners();
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      notifyListeners();
      debugPrint('Launch failed for $moduleId: $e');
    }
  }

  Future<void> stopModule(String moduleId) async {
    final index = _modules.indexWhere((Module module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(status: ModuleStatus.stopping);
    _activeModuleIds.remove(moduleId);
    notifyListeners();

    try {
      if (_legacyProcessManager != null) {
        await _legacyProcessManager!.stopModule(moduleId);
        return;
      }
      _modules[index] = await _controlApiService.stopModule(moduleId);
      notifyListeners();
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      notifyListeners();
      debugPrint('Stop failed for $moduleId: $e');
    }
  }

  Future<void> updateModule(String moduleId) async {
    final index = _modules.indexWhere((Module module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.updating,
      installProgress: 0.0,
      healthStatus: null,
    );
    notifyListeners();

    try {
      if (_legacyProcessManager != null) {
        await _legacyProcessManager!.updateModule(
          _modules[index],
          onProgress: (double progress) {
            _modules[index] = _modules[index].copyWith(
              installProgress: progress,
            );
            notifyListeners();
          },
        );
        return;
      }
      _modules[index] = await _controlApiService.updateModule(moduleId);
      notifyListeners();
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.error,
        healthStatus: e.toString(),
      );
      notifyListeners();
      debugPrint('Update failed for $moduleId: $e');
    }
  }

  Future<void> uninstallModule(String moduleId) async {
    final index = _modules.indexWhere((Module module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(
      status: ModuleStatus.notInstalled,
      installProgress: 0.0,
      healthStatus: null,
    );
    _activeModuleIds.remove(moduleId);
    notifyListeners();

    try {
      if (_legacyProcessManager != null) {
        return;
      }
      await _controlApiService.uninstallModule(moduleId);
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      debugPrint('Uninstall failed for $moduleId: $e');
    }
  }

  void closeTab(String moduleId) {
    _activeModuleIds.remove(moduleId);
    notifyListeners();
  }

  void dismissLauncherUpdate() {
    _pendingLauncherUpdate = null;
    notifyListeners();
  }

  void setUpdateChannel(UpdateChannel channel) {
    _updateService.channel = channel;
    notifyListeners();
  }

  Future<void> setVersionPinned(String moduleId, bool pinned) async {
    final index = _modules.indexWhere((module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    try {
      _modules[index] = await _controlApiService.updateModuleSettings(
        moduleId,
        versionPinned: pinned,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update version pinning for $moduleId: $e');
    }
  }

  Future<void> checkForUpdates() async {
    try {
      await _reloadFromControlApi(includeLauncherUpdate: true);
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  Stream<String>? getModuleOutput(String moduleId) {
    return _legacyProcessManager?.getOutput(moduleId);
  }

  Future<void> _reloadFromControlApi({
    required bool includeLauncherUpdate,
  }) async {
    final settings = await _controlApiService.fetchSettings();
    final fetchedModules = await _controlApiService.fetchModules();

    _pythonAvailable = settings.pythonAvailable;
    _mujocoAvailable = settings.mujocoAvailable;
    _error = null;
    _modules = fetchedModules;
    _activeModuleIds.removeWhere(
      (id) => !_modules.any((module) => module.id == id),
    );

    if (includeLauncherUpdate) {
      _pendingLauncherUpdate = await _updateService.checkForLauncherUpdate();
    }
    notifyListeners();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isLoading) {
        return;
      }
      unawaited(_reloadFromControlApi(includeLauncherUpdate: false));
    });
  }

  Future<void> _syncServerSettings() async {
    if (_settingsProvider == null) {
      return;
    }
    try {
      await _controlApiService.updateSettings(
        logLevel: _settingsProvider!.logLevel.name,
      );
    } catch (e) {
      debugPrint('Failed to sync launcher settings to control API: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _legacyProcessManager = null;
    super.dispose();
  }
}
