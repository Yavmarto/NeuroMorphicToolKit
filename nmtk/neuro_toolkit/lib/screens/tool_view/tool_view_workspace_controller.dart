import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/widgets/module_error_view.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';

import 'package:neuro_toolkit/screens/tool_view/module_uri_resolver.dart'
    as uri_resolver;
import 'package:neuro_toolkit/screens/tool_view/tool_view_workspace_host.dart';

/// The single module surface the launcher mounts. Everything else in the
/// module manifest is a backend capability descriptor, not an openable UI.
const String kPrimaryModuleId = 'neurocnl';

/// Owns module-workspace session lifecycle: which module is active, the
/// live WebView controllers, per-module load failures, and the
/// generation/guard state that prevents overlapping `initializeWorkspace`
/// runs from racing each other during boot or a server switch.
class ToolViewWorkspaceController {
  ToolViewWorkspaceController(this._host);

  final ToolViewWorkspaceHost _host;

  final Map<String, InAppWebViewController> controllers =
      <String, InAppWebViewController>{};
  final Map<String, Uri> pendingModuleRequests = <String, Uri>{};
  final Map<String, ModuleLoadFailure> moduleLoadFailures =
      <String, ModuleLoadFailure>{};

  // Tracks each module's status from the previous build so we can detect
  // non-running → running transitions and auto-clear only *stale* failures
  // (those recorded while the module was down). Failures that occurred while
  // the module was already running are kept until the user clicks Retry.
  final Map<String, ModuleStatus> prevModuleStatuses = <String, ModuleStatus>{};

  String activeModuleId = '';
  // Guards the entire async initializeWorkspace() operation (not just its
  // aftermath) so overlapping rebuilds during boot — e.g. a module flipping
  // starting -> running while ensureDefaultSessionsOnce is still in flight —
  // can never queue a second concurrent run. A second concurrent run can
  // transiently churn workspaceState.focusedModuleId, which remounts the
  // active module's KeyedSubtree and re-triggers its startup dialogs.
  bool workspaceInitializing = false;
  int workspaceServerGeneration = 0;

  WidgetRef get _ref => _host.ref;
  bool get mounted => _host.mounted;
  void rebuild(VoidCallback fn) => _host.rebuild(fn);

  void handleModuleStateChanged(
    AsyncValue<ModuleState>? previous,
    AsyncValue<ModuleState> next,
  ) {
    final modules = next.value?.modules;
    if (modules == null) return;
    final eligibleModules = modules
        .where(shouldOpenModule)
        .toList(growable: false);
    var clearedFailure = false;
    for (final module in eligibleModules) {
      final previousStatus = prevModuleStatuses[module.id];
      final isReady =
          module.status == ModuleStatus.running ||
          module.status == ModuleStatus.degraded;
      final wasReady =
          previousStatus == ModuleStatus.running ||
          previousStatus == ModuleStatus.degraded;
      if (previousStatus != null &&
          isReady &&
          !wasReady &&
          moduleLoadFailures.remove(module.id) != null) {
        controllers.remove(module.id);
        clearedFailure = true;
      }
      prevModuleStatuses[module.id] = module.status;
    }
    _reconcileActiveModule(eligibleModules, _ref.read(workspaceProvider).value);
    if (clearedFailure && _host.mounted) _host.rebuild(() {});
    unawaited(initializeWorkspace());
  }

  void handleWorkspaceStateChanged(
    AsyncValue<WorkspaceState>? previous,
    AsyncValue<WorkspaceState> next,
  ) {
    final moduleState = _ref.read(moduleProvider).value;
    final workspaceState = next.value;
    if (moduleState == null || workspaceState == null) return;
    final eligibleModules = moduleState.modules
        .where(shouldOpenModule)
        .toList(growable: false);
    _reconcileActiveModule(eligibleModules, workspaceState);
    unawaited(initializeWorkspace());
  }

  void handleControlApiChanged(
    ControlApiService? previous,
    ControlApiService? next,
  ) {
    if (previous?.baseUri == next?.baseUri) return;
    workspaceServerGeneration++;
    workspaceInitializing = false;
    if (!_host.mounted) return;
    _host.rebuild(() {
      controllers.clear();
      pendingModuleRequests.clear();
      moduleLoadFailures.clear();
      prevModuleStatuses.clear();
    });
    unawaited(initializeWorkspace());
  }

  void _reconcileActiveModule(
    List<Module> eligibleModules,
    WorkspaceState? workspaceState,
  ) {
    if (!_host.mounted || eligibleModules.isEmpty || workspaceState == null) {
      return;
    }
    final preferred =
        _preferredModuleId(eligibleModules, workspaceState.focusedModuleId) ??
        eligibleModules.first.id;
    if (preferred == activeModuleId) return;
    _host.rebuild(() => activeModuleId = preferred);
  }

  void handleLauncherNavigation(
    LauncherNavigationRequest? previous,
    LauncherNavigationRequest? next,
  ) {
    if (next == null || previous?.sequence == next.sequence) return;

    switch (next.action) {
      case LauncherNavigationAction.openWorkspace:
        unawaited(initializeWorkspace());
        return;
      case LauncherNavigationAction.openModule:
        final moduleId = next.moduleId;
        final modules = _ref.read(moduleProvider).value?.modules;
        if (moduleId == null || modules == null) return;
        final module = findModule(modules, moduleId);
        if (module == null || !shouldOpenModule(module)) return;
        unawaited(activateModule(moduleId, requestFocus: true));
        return;
      case LauncherNavigationAction.reloadWorkspace:
        unawaited(reloadWorkspace());
        return;
      case LauncherNavigationAction.toggleSidebar:
        Actions.maybeInvoke(_host.context, const ToggleSidebarIntent());
        return;
    }
  }

  Future<void> reloadWorkspace() async {
    workspaceServerGeneration++;
    workspaceInitializing = false;
    _host.rebuild(() {
      controllers.clear();
      pendingModuleRequests.clear();
      moduleLoadFailures.clear();
      prevModuleStatuses.clear();
    });
    await Future.wait([
      _ref.refresh(moduleProvider.future),
      _ref.refresh(workspaceProvider.future),
    ]);
    if (_host.mounted) {
      await initializeWorkspace();
    }
  }

  Future<void> initializeWorkspace() async {
    if (!_host.mounted) return;
    if (workspaceInitializing) {
      return;
    }
    workspaceInitializing = true;
    final serverGeneration = workspaceServerGeneration;
    final baseUri = uri_resolver.launcherBaseUri(_ref);
    if (baseUri == null) {
      workspaceInitializing = false;
      return;
    }
    final serverKey = baseUri.toString();
    try {
      final moduleStateAsync = _ref.read(moduleProvider);
      final moduleState = moduleStateAsync.value;
      final workspaceStateAsync = _ref.read(workspaceProvider);
      final workspaceState = workspaceStateAsync.value;
      if (moduleStateAsync.isLoading ||
          workspaceStateAsync.isLoading ||
          moduleState == null ||
          workspaceState == null) {
        return;
      }
      if (serverGeneration != workspaceServerGeneration ||
          serverKey != uri_resolver.launcherBaseUri(_ref)?.toString()) {
        return;
      }

      final eligibleModules = moduleState.modules
          .where(shouldOpenModule)
          .toList(growable: false);
      if (eligibleModules.isEmpty) {
        return;
      }

      final existingSessions = <String, WorkspaceSession>{
        for (final session in workspaceState.sessions)
          session.moduleId: session,
      };
      final desiredSessions = eligibleModules
          .map(
            (Module module) =>
                (existingSessions[module.id] ?? _defaultSessionFor(module))
                    .copyWith(
                      surfaceMode: uri_resolver.surfaceModeForModule(module.id),
                      readinessState: readinessStateForModule(module),
                    ),
          )
          .toList(growable: false);
      final targetModuleId =
          _preferredModuleId(eligibleModules, workspaceState.focusedModuleId) ??
          eligibleModules.first.id;

      if (serverGeneration != workspaceServerGeneration ||
          serverKey != uri_resolver.launcherBaseUri(_ref)?.toString()) {
        return;
      }
      await _ref
          .read(workspaceProvider.notifier)
          .ensureDefaultSessionsOnce(
            sessions: desiredSessions,
            focusedModuleId: targetModuleId,
          );
      if (!_host.mounted ||
          serverGeneration != workspaceServerGeneration ||
          serverKey != uri_resolver.launcherBaseUri(_ref)?.toString()) {
        return;
      }

      await activateModule(targetModuleId, requestFocus: true);
    } finally {
      workspaceInitializing = false;
    }
  }

  WorkspaceSession _defaultSessionFor(Module module) {
    return WorkspaceSession(
      moduleId: module.id,
      surfaceMode: uri_resolver.surfaceModeForModule(module.id),
      restoreState: const <String, dynamic>{},
      readinessState: readinessStateForModule(module),
    );
  }

  String? _preferredModuleId(
    List<Module> eligibleModules,
    String? focusedModuleId,
  ) {
    final eligibleIds = eligibleModules.map((module) => module.id).toSet();
    if (focusedModuleId != null && eligibleIds.contains(focusedModuleId)) {
      return focusedModuleId;
    }
    if (eligibleIds.contains(activeModuleId)) {
      return activeModuleId;
    }
    return null;
  }

  bool shouldOpenModule(Module module) {
    // The launcher mounts exactly one frontend surface: NeuroStudio. Every
    // other entry in the module manifest is a backend capability descriptor
    // (Jupyter kernels, native services, etc.), not a separate tabbable UI.
    if (module.id != kPrimaryModuleId) {
      return false;
    }
    if (!module.isEnabled || !module.showInLauncherNav) {
      return false;
    }
    return module.hasFrontend ||
        NativeSurfaceRegistry.supportsModule(module.id);
  }

  String readinessStateForModule(Module module) {
    if (module.isPreflightFailed || module.status == ModuleStatus.error) {
      return 'error';
    }
    if (module.status == ModuleStatus.degraded) {
      return 'degraded';
    }
    if (module.status == ModuleStatus.running) {
      return 'ready';
    }
    if (module.status == ModuleStatus.starting ||
        module.status == ModuleStatus.stopping) {
      return 'warming_up';
    }
    return 'opening';
  }

  Future<void> activateModule(
    String moduleId, {
    required bool requestFocus,
  }) async {
    if (!_host.mounted) return;
    final moduleState = _ref.read(moduleProvider).value;
    final workspaceState = _ref.read(workspaceProvider).value;
    if (moduleState == null || workspaceState == null) return;

    final module = findModule(moduleState.modules, moduleId);
    if (module == null) {
      return;
    }

    WorkspaceSession? currentSession;
    for (final session in workspaceState.sessions) {
      if (session.moduleId == moduleId) {
        currentSession = session;
        break;
      }
    }
    final desiredReadiness = readinessStateForModule(module);
    if (currentSession == null) {
      await _ref
          .read(workspaceProvider.notifier)
          .openSession(
            moduleId,
            surfaceMode: uri_resolver.surfaceModeForModule(moduleId),
            readinessState: desiredReadiness,
          );
    } else if (requestFocus) {
      await _ref.read(workspaceProvider.notifier).focusSession(moduleId);
    }
    if (!_host.mounted) return;

    _host.rebuild(() {
      activeModuleId = moduleId;
      moduleLoadFailures.remove(moduleId);
    });

    if (currentSession != null &&
        currentSession.readinessState != desiredReadiness) {
      await _ref
          .read(workspaceProvider.notifier)
          .updateSession(moduleId, readinessState: desiredReadiness);
      if (!_host.mounted) return;
    }

    if (module.status != ModuleStatus.running &&
        module.status != ModuleStatus.degraded &&
        module.status != ModuleStatus.starting) {
      await _ref
          .read(workspaceProvider.notifier)
          .updateSession(moduleId, readinessState: 'warming_up');
      if (!_host.mounted) return;
      // Jupyter runs as its own Docker container, external to launcher
      // control (startStrategy "none") -- launchModule() there can only
      // re-probe its health, not actually restart it. retryJupyter() is the
      // real fix: it reaches the container over SSH, same as the setup
      // screen's "Recover Jupyter" button.
      if (moduleId == 'jupyter') {
        await _ref.read(backendDeploymentProvider.notifier).retryJupyter();
      } else {
        await _ref.read(moduleProvider.notifier).launchModule(moduleId);
      }
    }
  }

  Module? findModule(List<Module> modules, String moduleId) {
    for (final module in modules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }
}
