// TODO(riverpod-migration): Migrate ModuleProvider to AsyncNotifier<List<Module>>.
//
// ModuleProvider is the most complex provider (498 lines) because it owns:
//   • the 3-second polling timer (_startRefreshTimer)
//   • module lifecycle (install, launch, stop, update, uninstall)
//   • active-module tracking (_activeModuleIds)
//   • cross-provider dependency on SettingsProvider
//   • legacy ProcessManager compatibility layer
//
// Steps:
//   1. Replace the polling Timer with `ref.keepAlive()` + a Timer inside build()
//      that calls `ref.invalidateSelf()` or updates state directly.
//   2. Expose `List<Module>` as the state value; isLoading and error move into
//      AsyncValue's native loading/error states.
//   3. Active module IDs can be a separate `StateProvider<List<String>>`.
//   4. Remove `updateSettingsProvider()` — use `ref.watch(settingsStateProvider)`
//      inside the notifier instead.
//   5. Update riverpod_providers.dart to remove moduleStateProvider's
//      ChangeNotifierProvider and use AsyncNotifierProvider.
//   6. Update all call sites in tool_view.dart, settings.dart, etc.
//
// The polling + test coverage prerequisites make this at least a 2-day effort.
// Tackle only after WorkspaceProvider and SettingsProvider are migrated first.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/process_manager.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';

class ModuleProvider with ChangeNotifier {
  ModuleProvider({
    ProcessManager? processManager,
    UpdateService? updateService,
    ControlApiService? controlApiService,
    LauncherBootstrapState? bootstrapState,
  }) {
    _updateService = updateService ?? UpdateService();
    _controlApiService = controlApiService ?? ControlApiService();
    _bootstrapState = bootstrapState ??
        LauncherBootstrapState.ready(ControlApiService.resolveBaseUri());
    _legacyProcessManager = processManager;
    _init();
  }

  late final UpdateService _updateService;
  late final ControlApiService _controlApiService;
  late final LauncherBootstrapState _bootstrapState;
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
          final index = _modules.indexWhere(
            (module) => module.id == updatedModule.id,
          );
          if (index != -1) {
            _modules[index] = updatedModule;
            notifyListeners();
          }
        });
        return;
      }
      if (!_bootstrapState.canUseControlApi) {
        _error = _bootstrapState.message ??
            'Preflight failed: launcher control API is unavailable.';
        return;
      }
      await _reloadFromControlApi(includeLauncherUpdate: true);
      await _startSwitchableNavModules();
    } catch (e) {
      // A connection failure (e.g. control API not yet running) does not mean
      // Python is absent — do not set _pythonAvailable = false here.
      _error = nmtkUserFacingError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Start the refresh timer whether or not the first load succeeded so the
    // app picks up the control API automatically once it becomes reachable
    // (e.g. after `make dev` finishes starting the backend).
    if (_bootstrapState.canUseControlApi) {
      _startRefreshTimer();
    }
  }

  /// Eagerly starts every installed module that the workspace can switch
  /// to as a tab, so the user never waits for a cold start when first
  /// switching between modules. The start set mirrors `_shouldOpenModule`
  /// in `tool_view.dart`: enabled, nav-visible, and backed by either a web
  /// frontend or a registered native surface. Modules are started
  /// concurrently to minimise wall-clock startup time.
  Future<void> _startSwitchableNavModules() async {
    final toLaunch = _modules
        .where(
          (module) =>
              module.isEnabled &&
              module.showInLauncherNav &&
              (module.hasFrontend ||
                  NativeSurfaceRegistry.supportsModule(module.id)) &&
              module.status == ModuleStatus.installed,
        )
        .map((module) => module.id)
        .toList(growable: false);
    if (toLaunch.isEmpty) {
      return;
    }
    await Future.wait(toLaunch.map(launchModule));
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
      .map(
        (String id) => _modules.firstWhere((Module module) => module.id == id),
      )
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
    if (!_bootstrapState.canUseControlApi) {
      _error = _bootstrapState.message ??
          'Preflight failed: launcher control API is unavailable.';
      _isLoading = false;
      notifyListeners();
      return;
    }
    try {
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      // Connection failure ≠ Python missing; don't set _pythonAvailable = false.
      _error = nmtkUserFacingError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
    bool? startOnLaunch,
  }) async {
    final index = _modules.indexWhere((module) => module.id == moduleId);
    if (index == -1) {
      return;
    }

    _modules[index] = _modules[index].copyWith(
      isEnabled: isEnabled,
      customPort: customPort,
      startOnLaunch: startOnLaunch,
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
      if (startOnLaunch != null) {
        settingsToSave['startOnLaunch'] = startOnLaunch;
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
        startOnLaunch: startOnLaunch,
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
        healthStatus: nmtkUserFacingError(e),
      );
      notifyListeners();
      debugPrint('Installation failed for $moduleId: $e');
    }
  }

  Future<void> repairModule(String moduleId) async {
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
      _modules[index] = await _controlApiService.repairModule(moduleId);
      notifyListeners();
      await _reloadFromControlApi(includeLauncherUpdate: false);
    } catch (e) {
      _modules[index] = _modules[index].copyWith(
        status: ModuleStatus.error,
        healthStatus: nmtkUserFacingError(e),
      );
      notifyListeners();
      debugPrint('Repair failed for $moduleId: $e');
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
        healthStatus: nmtkUserFacingError(e),
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
        healthStatus: nmtkUserFacingError(e),
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
    if (_modules[index].versionPinned ||
        !UpdateService.isNewerVersion(
          _modules[index].version,
          _modules[index].remoteVersion,
        )) {
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
        healthStatus: nmtkUserFacingError(e),
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
    if (!_bootstrapState.canUseControlApi) {
      return;
    }
    final settings = await _controlApiService.fetchSettings();
    final fetchedModules = await _controlApiService.fetchModules(
      refreshUpdates: includeLauncherUpdate,
    );

    // Only notify listeners when something actually changed to avoid
    // rebuilding the entire widget tree on every 3-second polling tick.
    bool changed = false;

    if (settings.pythonAvailable != _pythonAvailable) {
      _pythonAvailable = settings.pythonAvailable;
      changed = true;
    }
    if (settings.mujocoAvailable != _mujocoAvailable) {
      _mujocoAvailable = settings.mujocoAvailable;
      changed = true;
    }
    if (_error != null) {
      _error = null;
      changed = true;
    }

    // listEquals uses Module.== so this only triggers a rebuild when
    // id/status/healthStatus/installProgress/version actually changes.
    if (!listEquals(_modules, fetchedModules)) {
      _modules = fetchedModules;
      changed = true;
    }

    final staleIds = _activeModuleIds
        .where((id) => !_modules.any((module) => module.id == id))
        .toList();
    if (staleIds.isNotEmpty) {
      _activeModuleIds.removeWhere((id) => staleIds.contains(id));
      changed = true;
    }

    if (includeLauncherUpdate) {
      final update = await _updateService.checkForLauncherUpdate();
      if (update != _pendingLauncherUpdate) {
        _pendingLauncherUpdate = update;
        changed = true;
      }
    }

    if (changed) notifyListeners();
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
    if (_settingsProvider == null || !_bootstrapState.canUseControlApi) {
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
