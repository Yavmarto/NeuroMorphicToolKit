import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';

part 'module_notifier.g.dart';

@Riverpod(keepAlive: true)
class ModuleNotifier extends _$ModuleNotifier {
  late final UpdateService _updateService;
  Timer? _refreshTimer;

  @override
  Future<ModuleState> build() async {
    _updateService = UpdateService();
    final bootstrapState = ref.watch(launcherBootstrapStateProvider);

    if (!bootstrapState.canUseControlApi) {
      return const ModuleState();
    }

    try {
      final state = await _reloadFromControlApi(includeLauncherUpdate: true);
      await _startSwitchableNavModules(state.modules);

      // Setup polling timer
      _startRefreshTimer();

      // Setup listening to settings sync
      ref.listen(settingsProvider, (previous, next) {
        final prevLogLevel = previous?.value?.logLevel;
        final nextLogLevel = next.value?.logLevel;
        if (prevLogLevel != nextLogLevel && nextLogLevel != null) {
          unawaited(_syncServerSettings(nextLogLevel.name));
        }
      });

      return state;
    } catch (e) {
      // Re-throw to let AsyncValue catch it and expose `.error`
      throw Exception(nmtkUserFacingError(e));
    }
  }

  UpdateChannel get currentChannel => _updateService.channel;

  Future<ModuleState> _reloadFromControlApi({
    required bool includeLauncherUpdate,
  }) async {
    final controlApi = ref.read(controlApiServiceProvider);
    final settings = await controlApi.fetchSettings();
    final fetchedModules = await controlApi.fetchModules(
      refreshUpdates: includeLauncherUpdate,
    );

    LauncherUpdate? pendingUpdate;
    if (includeLauncherUpdate) {
      pendingUpdate = await _updateService.checkForLauncherUpdate();
    }

    return ModuleState(
      modules: fetchedModules,
      pythonAvailable: settings.pythonAvailable,
      mujocoAvailable: settings.mujocoAvailable,
      pendingLauncherUpdate: pendingUpdate,
      activeModuleIds: state.value?.activeModuleIds ?? [],
    );
  }

  Future<void> _startSwitchableNavModules(List<Module> currentModules) async {
    final toLaunch = currentModules
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

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (state.isLoading || state.hasError) return;
      unawaited(_pollUpdates());
    });
    ref.onDispose(() {
      _refreshTimer?.cancel();
    });
  }

  Future<void> _pollUpdates() async {
    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final settings = await controlApi.fetchSettings();
      final fetchedModules =
          await controlApi.fetchModules(refreshUpdates: false);

      final currentState = state.value;
      if (currentState == null) return;

      bool changed = false;
      var nextState = currentState;

      if (settings.pythonAvailable != nextState.pythonAvailable) {
        nextState =
            nextState.copyWith(pythonAvailable: settings.pythonAvailable);
        changed = true;
      }
      if (settings.mujocoAvailable != nextState.mujocoAvailable) {
        nextState =
            nextState.copyWith(mujocoAvailable: settings.mujocoAvailable);
        changed = true;
      }

      if (!listEquals(nextState.modules, fetchedModules)) {
        nextState = nextState.copyWith(modules: fetchedModules);
        changed = true;
      }

      final staleIds = nextState.activeModuleIds
          .where((id) => !fetchedModules.any((module) => module.id == id))
          .toList();
      if (staleIds.isNotEmpty) {
        final newActiveIds = List<String>.from(nextState.activeModuleIds)
          ..removeWhere((id) => staleIds.contains(id));
        nextState = nextState.copyWith(activeModuleIds: newActiveIds);
        changed = true;
      }

      if (changed) {
        state = AsyncData(nextState);
      }
    } catch (_) {
      // Ignore polling errors to prevent breaking the UI on transient network drops
    }
  }

  Future<void> _syncServerSettings(String logLevelName) async {
    final bootstrapState = ref.read(launcherBootstrapStateProvider);
    if (!bootstrapState.canUseControlApi) return;

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      await controlApi.updateSettings(logLevel: logLevelName);
    } catch (e) {
      debugPrint('Failed to sync launcher settings to control API: $e');
    }
  }

  Future<void> recheckPython() async {
    state = const AsyncLoading();
    final bootstrapState = ref.read(launcherBootstrapStateProvider);
    if (!bootstrapState.canUseControlApi) {
      state = AsyncError(
        bootstrapState.message ??
            'Preflight failed: launcher control API is unavailable.',
        StackTrace.current,
      );
      return;
    }
    try {
      final newState =
          await _reloadFromControlApi(includeLauncherUpdate: false);
      state = AsyncData(newState);
    } catch (e, st) {
      state = AsyncError(nmtkUserFacingError(e), st);
    }
  }

  Future<void> updateModuleSettings(
    String moduleId, {
    bool? isEnabled,
    int? customPort,
    bool? startOnLaunch,
  }) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index =
        currentState.modules.indexWhere((module) => module.id == moduleId);
    if (index == -1) return;

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      isEnabled: isEnabled,
      customPort: customPort,
      startOnLaunch: startOnLaunch,
    );
    state = AsyncData(currentState.copyWith(modules: updatedModules));

    final settingsToSave = <String, dynamic>{};
    if (isEnabled != null) settingsToSave['isEnabled'] = isEnabled;
    if (customPort != null) settingsToSave['customPort'] = customPort;
    if (startOnLaunch != null) settingsToSave['startOnLaunch'] = startOnLaunch;

    await ref
        .read(settingsProvider.notifier)
        .updateModuleSettings(moduleId, settingsToSave);

    if (isEnabled == false) {
      await stopModule(moduleId);
    }

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.updateModuleSettings(
        moduleId,
        isEnabled: isEnabled,
        customPort: customPort,
        startOnLaunch: startOnLaunch,
      );

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
    } catch (e) {
      debugPrint('Failed to update remote module settings: $e');
    }
  }

  Future<void> installModule(String moduleId) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      status: ModuleStatus.installing,
      installProgress: 0.0,
      healthStatus: null,
    );
    state = AsyncData(currentState.copyWith(modules: updatedModules));

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.installModule(moduleId);

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
      unawaited(_pollUpdates()); // Background reload
    } catch (e) {
      _setErrorState(moduleId, nmtkUserFacingError(e));
      debugPrint('Installation failed for $moduleId: $e');
    }
  }

  Future<void> repairModule(String moduleId) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      status: ModuleStatus.installing,
      installProgress: 0.0,
      healthStatus: null,
    );
    state = AsyncData(currentState.copyWith(modules: updatedModules));

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.repairModule(moduleId);

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
      unawaited(_pollUpdates());
    } catch (e) {
      _setErrorState(moduleId, nmtkUserFacingError(e));
      debugPrint('Repair failed for $moduleId: $e');
    }
  }

  Future<void> launchModule(String moduleId) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final updatedActiveIds = List<String>.from(currentState.activeModuleIds);
    if (!updatedActiveIds.contains(moduleId)) {
      updatedActiveIds.add(moduleId);
    }

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      status: ModuleStatus.starting,
      healthStatus: null,
    );

    state = AsyncData(currentState.copyWith(
      modules: updatedModules,
      activeModuleIds: updatedActiveIds,
    ));

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.startModule(moduleId);

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
      unawaited(_pollUpdates());
    } catch (e) {
      _setErrorState(moduleId, nmtkUserFacingError(e));
      debugPrint('Launch failed for $moduleId: $e');
    }
  }

  Future<void> stopModule(String moduleId) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] =
        updatedModules[index].copyWith(status: ModuleStatus.stopping);

    final updatedActiveIds = List<String>.from(currentState.activeModuleIds)
      ..remove(moduleId);

    state = AsyncData(currentState.copyWith(
      modules: updatedModules,
      activeModuleIds: updatedActiveIds,
    ));

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.stopModule(moduleId);

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
      unawaited(_pollUpdates());
    } catch (e) {
      _setErrorState(moduleId, nmtkUserFacingError(e));
      debugPrint('Stop failed for $moduleId: $e');
    }
  }

  Future<void> updateModule(String moduleId) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final module = currentState.modules[index];
    if (module.versionPinned ||
        !UpdateService.isNewerVersion(module.version, module.remoteVersion)) {
      return;
    }

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      status: ModuleStatus.updating,
      installProgress: 0.0,
      healthStatus: null,
    );
    state = AsyncData(currentState.copyWith(modules: updatedModules));

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.updateModule(moduleId);

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
      unawaited(_pollUpdates());
    } catch (e) {
      _setErrorState(moduleId, nmtkUserFacingError(e));
      debugPrint('Update failed for $moduleId: $e');
    }
  }

  Future<void> uninstallModule(String moduleId) async {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      status: ModuleStatus.notInstalled,
      installProgress: 0.0,
      healthStatus: null,
    );

    final updatedActiveIds = List<String>.from(currentState.activeModuleIds)
      ..remove(moduleId);

    state = AsyncData(currentState.copyWith(
      modules: updatedModules,
      activeModuleIds: updatedActiveIds,
    ));

    try {
      final controlApi = ref.read(controlApiServiceProvider);
      await controlApi.uninstallModule(moduleId);
      unawaited(_pollUpdates());
    } catch (e) {
      debugPrint('Uninstall failed for $moduleId: $e');
    }
  }

  void closeTab(String moduleId) {
    final currentState = state.value;
    if (currentState == null) return;

    final updatedActiveIds = List<String>.from(currentState.activeModuleIds)
      ..remove(moduleId);
    state = AsyncData(currentState.copyWith(activeModuleIds: updatedActiveIds));
  }

  void dismissLauncherUpdate() {
    final currentState = state.value;
    if (currentState == null) return;

    state = AsyncData(currentState.copyWith(pendingLauncherUpdate: null));
  }

  void setUpdateChannel(UpdateChannel channel) {
    _updateService.channel = channel;
    // We don't trigger state rebuild directly, let the poll fetch updates
  }

  Future<void> setVersionPinned(String moduleId, bool pinned) async {
    try {
      final controlApi = ref.read(controlApiServiceProvider);
      final updatedModule = await controlApi.updateModuleSettings(
        moduleId,
        versionPinned: pinned,
      );

      final latestState = state.value;
      if (latestState != null) {
        final newModules = List<Module>.from(latestState.modules);
        final newIndex = newModules.indexWhere((m) => m.id == moduleId);
        if (newIndex != -1) {
          newModules[newIndex] = updatedModule;
          state = AsyncData(latestState.copyWith(modules: newModules));
        }
      }
    } catch (e) {
      debugPrint('Failed to update version pinning for $moduleId: $e');
    }
  }

  Future<void> checkForUpdates() async {
    try {
      final newState = await _reloadFromControlApi(includeLauncherUpdate: true);
      state = AsyncData(newState);
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  void _setErrorState(String moduleId, String errorMsg) {
    final currentState = state.value;
    if (currentState == null) return;

    final index = currentState.modules.indexWhere((m) => m.id == moduleId);
    if (index == -1) return;

    final updatedModules = List<Module>.from(currentState.modules);
    updatedModules[index] = updatedModules[index].copyWith(
      status: ModuleStatus.error,
      healthStatus: errorMsg,
    );
    state = AsyncData(currentState.copyWith(modules: updatedModules));
  }
}
