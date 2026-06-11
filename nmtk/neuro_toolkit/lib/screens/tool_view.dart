import 'dart:async';
import 'dart:io';
import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/widgets/module_error_view.dart';
import 'package:neuro_toolkit/widgets/module_icon.dart';
import 'package:neuro_toolkit/widgets/module_loading_view.dart';
import 'package:neuro_toolkit/widgets/module_picker_panel.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';

class ToolViewScreen extends ConsumerStatefulWidget {
  const ToolViewScreen({super.key, this.initialModuleId});

  final String? initialModuleId;

  @override
  ConsumerState<ToolViewScreen> createState() => _ToolViewScreenState();
}

// Module IDs that are desktop-only and must not appear in the mobile bottom nav.
const _kMobileHiddenModuleIds = {'Neurobench'};

class _ToolViewScreenState extends ConsumerState<ToolViewScreen> {
  final Map<String, InAppWebViewController> _controllers =
      <String, InAppWebViewController>{};
  final Map<String, Uri> _pendingModuleRequests = <String, Uri>{};
  final Map<String, ModuleLoadFailure> _moduleLoadFailures =
      <String, ModuleLoadFailure>{};

  // Tracks each module's status from the previous build so we can detect
  // non-running → running transitions and auto-clear only *stale* failures
  // (those recorded while the module was down). Failures that occurred while
  // the module was already running are kept until the user clicks Retry.
  final Map<String, ModuleStatus> _prevModuleStatuses =
      <String, ModuleStatus>{};

  String _activeModuleId = '';
  bool _workspaceInitialized = false;

  Uri _launcherBaseUri() => ref.read(controlApiServiceProvider).baseUri;

  bool _usesRemoteHostedServices() {
    if (kIsWeb) {
      return false;
    }
    return !ControlApiService.isLoopbackHost(_launcherBaseUri().host);
  }

  static String get _configuredServicesHost =>
      const String.fromEnvironment('NMTK_SERVICES_HOST', defaultValue: '');

  String _serviceHost() {
    if (!kIsWeb) {
      final override = _configuredServicesHost.trim();
      if (override.isNotEmpty && !ControlApiService.isLoopbackHost(override)) {
        return override;
      }
      final baseUri = _launcherBaseUri();
      if (_usesRemoteHostedServices()) {
        return baseUri.host;
      }
      return 'localhost';
    }
    final host = Uri.base.host.trim();
    if (host.isEmpty || host == '0.0.0.0') {
      return 'localhost';
    }
    return host;
  }

  String _serviceScheme() {
    if (!kIsWeb) {
      final baseUri = _launcherBaseUri();
      if (_usesRemoteHostedServices()) {
        return baseUri.scheme.isEmpty ? 'http' : baseUri.scheme;
      }
      return 'http';
    }
    final scheme = Uri.base.scheme.trim();
    return scheme.isEmpty ? 'http' : scheme;
  }

  Uri _moduleUri(Module module, {bool healthCheck = false}) {
    final String moduleId = module.id.toLowerCase();

    // If it's on the monolith port (9000), we use path-based routing.
    if (module.effectivePort == 9000) {
      if (healthCheck) {
        return Uri(
          scheme: _serviceScheme(),
          host: _serviceHost(),
          port: 9000,
          path: '/api/$moduleId/health',
        );
      }
      return Uri(
        scheme: _serviceScheme(),
        host: _serviceHost(),
        port: 9000,
        path: '/$moduleId/',
      );
    }

    // Standalone modules on non-monolith ports.
    // Use deployment.healthPath when available so modules like Jupyter (which
    // expose /api/health rather than /health) are polled correctly.
    final String healthPath = module.deployment?.healthPath.isNotEmpty == true
        ? module.deployment!.healthPath
        : '/health';
    final path = healthCheck ? healthPath : (module.hasFrontend ? '' : '/docs');
    return Uri(
      scheme: _serviceScheme(),
      host: _serviceHost(),
      port: module.effectivePort,
      path: path,
    );
  }

  String _surfaceModeForModule(String moduleId) {
    return NativeSurfaceRegistry.supportsModule(moduleId)
        ? 'native'
        : 'embedded';
  }

  @override
  void initState() {
    super.initState();
    _activeModuleId = widget.initialModuleId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeWorkspace();
    });
  }

  @override
  void didUpdateWidget(ToolViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialModuleId != oldWidget.initialModuleId) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeWorkspace(forceFocus: true);
      });
    }
  }

  Future<void> _initializeWorkspace({bool forceFocus = false}) async {
    final moduleStateAsync = ref.read(moduleNotifierProvider);
    final moduleState = moduleStateAsync.value;
    final workspaceStateAsync = ref.read(workspaceNotifierProvider);
    final workspaceState = workspaceStateAsync.value;
    if (moduleStateAsync.isLoading ||
        workspaceStateAsync.isLoading ||
        moduleState == null ||
        workspaceState == null) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _initializeWorkspace(forceFocus: forceFocus);
        });
      }
      return;
    }

    final eligibleModules =
        moduleState.modules.where(_shouldOpenModule).toList(growable: false);
    if (eligibleModules.isEmpty) {
      return;
    }

    final existingSessions = <String, WorkspaceSession>{
      for (final session in workspaceState.sessions) session.moduleId: session,
    };
    final desiredSessions = eligibleModules
        .map(
          (Module module) =>
              (existingSessions[module.id] ?? _defaultSessionFor(module))
                  .copyWith(
            surfaceMode: _surfaceModeForModule(module.id),
            readinessState: _readinessStateForModule(module),
          ),
        )
        .toList(growable: false);
    final targetModuleId = _preferredModuleId(
            eligibleModules, workspaceState.focusedModuleId, forceFocus) ??
        eligibleModules.first.id;

    await ref
        .read(workspaceNotifierProvider.notifier)
        .ensureDefaultSessionsOnce(
          sessions: desiredSessions,
          focusedModuleId: targetModuleId,
        );

    _workspaceInitialized = true;
    await _activateModule(targetModuleId, requestFocus: true);
  }

  WorkspaceSession _defaultSessionFor(Module module) {
    return WorkspaceSession(
      moduleId: module.id,
      surfaceMode: _surfaceModeForModule(module.id),
      restoreState: const <String, dynamic>{},
      readinessState: _readinessStateForModule(module),
    );
  }

  String? _preferredModuleId(
    List<Module> eligibleModules,
    String? focusedModuleId,
    bool forceFocus,
  ) {
    final eligibleIds = eligibleModules.map((module) => module.id).toSet();
    final requestedModuleId = widget.initialModuleId;
    if (requestedModuleId != null && eligibleIds.contains(requestedModuleId)) {
      return requestedModuleId;
    }
    if (!forceFocus &&
        focusedModuleId != null &&
        eligibleIds.contains(focusedModuleId)) {
      return focusedModuleId;
    }
    if (!forceFocus && eligibleIds.contains(_activeModuleId)) {
      return _activeModuleId;
    }
    return null;
  }

  bool _shouldOpenModule(Module module) {
    if (!module.isEnabled || !module.showInLauncherNav) {
      return false;
    }
    return module.hasFrontend ||
        NativeSurfaceRegistry.supportsModule(module.id);
  }

  String _readinessStateForModule(Module module) {
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

  Future<void> _activateModule(
    String moduleId, {
    required bool requestFocus,
  }) async {
    final moduleState = ref.read(moduleNotifierProvider).value;
    final workspaceState = ref.read(workspaceNotifierProvider).value;
    if (moduleState == null || workspaceState == null) return;

    final module = _findModule(moduleState.modules, moduleId);
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
    final desiredReadiness = _readinessStateForModule(module);
    if (currentSession == null) {
      await ref.read(workspaceNotifierProvider.notifier).openSession(
            moduleId,
            surfaceMode: _surfaceModeForModule(moduleId),
            readinessState: desiredReadiness,
          );
    } else if (requestFocus) {
      await ref.read(workspaceNotifierProvider.notifier).focusSession(moduleId);
    }
    if (mounted) {
      setState(() {
        _activeModuleId = moduleId;
        _moduleLoadFailures.remove(moduleId);
      });
    }

    if (currentSession != null &&
        currentSession.readinessState != desiredReadiness) {
      await ref.read(workspaceNotifierProvider.notifier).updateSession(
            moduleId,
            readinessState: desiredReadiness,
          );
    }

    if (module.status != ModuleStatus.running &&
        module.status != ModuleStatus.degraded &&
        module.status != ModuleStatus.starting) {
      await ref.read(workspaceNotifierProvider.notifier).updateSession(
            moduleId,
            readinessState: 'warming_up',
          );
      await ref.read(moduleNotifierProvider.notifier).launchModule(moduleId);
    }
  }

  Module? _findModule(List<Module> modules, String moduleId) {
    for (final module in modules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }

  /// Builds the embedded module surface backed by `flutter_inappwebview`.
  ///
  /// We use `flutter_inappwebview` rather than `webview_flutter` because the
  /// latter's macOS/WKWebView backend (a) never implements the native file
  /// open-panel delegate, so any in-page `<input type="file">` — e.g.
  /// JupyterLab's *Upload Files* button — silently does nothing, and (b) has
  /// long-standing compositing repaint issues that make hovering the embedded
  /// toolbar flicker. `flutter_inappwebview` wires up the WKUIDelegate open
  /// panel (and the Android file chooser) and composites cleanly, fixing both
  /// at the platform level — no CSS/JS injection workaround required.
  ///
  /// The widget is keyed by module id and lives inside the [IndexedStack], so
  /// the underlying native webview is created once and preserved across tab
  /// switches and provider rebuilds (no reload on rebuild).
  Widget _buildWebView(Module module) {
    final initialUri =
        _pendingModuleRequests.remove(module.id) ?? _moduleUri(module);
    return InAppWebView(
      key: ValueKey<String>('webview-${module.id}'),
      initialUrlRequest: URLRequest(url: WebUri.uri(initialUri)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        transparentBackground: false,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (controller) {
        _controllers[module.id] = controller;
      },
      onLoadStart: (controller, url) {
        if (!mounted) {
          return;
        }
        setState(() {
          _moduleLoadFailures.remove(module.id);
        });
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final requestUrl = navigationAction.request.url;
        if (requestUrl == null) {
          return NavigationActionPolicy.ALLOW;
        }
        final handled = await _handleCrossModuleNavigation(
          module,
          Uri.parse(requestUrl.toString()),
        );
        return handled
            ? NavigationActionPolicy.CANCEL
            : NavigationActionPolicy.ALLOW;
      },
      onReceivedError: (controller, request, error) {
        debugPrint('WebView error for ${module.name}: ${error.description}');
        // Only main-frame failures should surface the module error view.
        // Embedded SPAs like JupyterLab routinely fire sub-resource errors
        // (optional extension probes, favicons) that must not be treated as a
        // page load failure.
        if (request.isForMainFrame == false) {
          return;
        }
        _recordModuleLoadFailure(
          module.id,
          request.url,
          error.description,
        );
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        // Same main-frame guard as above: a 404 on a JupyterLab sub-resource
        // is not a frontend load failure.
        if (request.isForMainFrame == false) {
          return;
        }
        final statusCode = errorResponse.statusCode;
        final message = statusCode == null
            ? 'Embedded module request failed before the page could load.'
            : 'Embedded module returned HTTP $statusCode instead of a frontend page.';
        _recordModuleLoadFailure(
          module.id,
          request.url,
          message,
        );
      },
    );
  }

  void _recordModuleLoadFailure(
    String moduleId,
    Uri uri,
    String message,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _moduleLoadFailures[moduleId] = ModuleLoadFailure(
        uri: uri,
        message: message,
      );
    });
  }

  Widget _buildModuleLoadFailureState(
    Module module,
    ModuleLoadFailure failure,
  ) {
    return ModuleErrorView(
      module: module,
      failure: failure,
      isRemoteHosted: _usesRemoteHostedServices(),
      onRetry: () async {
        setState(() {
          _moduleLoadFailures.remove(module.id);
          _controllers.remove(module.id);
        });
        await _activateModule(module.id, requestFocus: false);
      },
    );
  }

  bool _isWebViewSupported() {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  Future<bool> _handleCrossModuleNavigation(
    Module currentModule,
    Uri requestUri,
  ) async {
    final moduleState = ref.read(moduleNotifierProvider).value;
    if (moduleState == null) return false;

    final navigation = resolveCrossModuleNavigation(
      targetUri: requestUri,
      modules: moduleState.modules,
      currentModuleId: currentModule.id,
    );
    if (navigation == null) {
      return false;
    }

    final targetModule = navigation.targetModule;
    _pendingModuleRequests[targetModule.id] = navigation.targetUri;

    await ref.read(workspaceNotifierProvider.notifier).openSession(
          targetModule.id,
          surfaceMode: _surfaceModeForModule(targetModule.id),
          deepLink: launcherDeepLinkFromUri(navigation.targetUri),
          readinessState: 'opening',
        );

    if (_controllers.containsKey(targetModule.id)) {
      _pendingModuleRequests.remove(targetModule.id);
      await _controllers[targetModule.id]!.loadUrl(
        urlRequest: URLRequest(url: WebUri.uri(navigation.targetUri)),
      );
    }

    await _activateModule(targetModule.id, requestFocus: true);
    return true;
  }

  Future<bool> _handleHostedModuleNavigationRequest(
    NmtkHostNavigationRequest request,
  ) async {
    final moduleState = ref.read(moduleNotifierProvider).value;
    final workspaceState = ref.read(workspaceNotifierProvider).value;
    if (moduleState == null || workspaceState == null) return false;

    final targetModule = _findModule(moduleState.modules, request.moduleId);
    if (targetModule == null || !_shouldOpenModule(targetModule)) {
      return false;
    }

    final existingSession = workspaceState.sessions
        .where(
            (WorkspaceSession session) => session.moduleId == targetModule.id)
        .cast<WorkspaceSession?>()
        .firstWhere(
          (WorkspaceSession? session) => session != null,
          orElse: () => null,
        );
    final restoreState = Map<String, dynamic>.from(request.restoreState);
    final readinessState = _readinessStateForModule(targetModule);

    if (existingSession == null) {
      await ref.read(workspaceNotifierProvider.notifier).openSession(
            targetModule.id,
            surfaceMode: _surfaceModeForModule(targetModule.id),
            deepLink: request.deepLink,
            restoreState: restoreState,
            readinessState: readinessState,
          );
    } else {
      await ref.read(workspaceNotifierProvider.notifier).updateSession(
            targetModule.id,
            deepLink: request.deepLink,
            restoreState: restoreState,
            readinessState: readinessState,
          );
    }

    await _activateModule(targetModule.id, requestFocus: true);
    return true;
  }

  static bool _isModuleReady(ModuleStatus status) =>
      status == ModuleStatus.running || status == ModuleStatus.degraded;

  Widget _buildLoadingState(Module module) {
    return ModuleLoadingView(
      module: module,
      healthCheckUri: _moduleUri(module, healthCheck: true),
    );
  }

  /// Builds the child widget for a single module slot in the [IndexedStack].
  ///
  /// Extracted so it can be shared between the desktop [Scaffold] path and the
  /// [NmtkMobileScaffold] path without duplicating the recovery/failure logic.
  Widget _buildModuleChild(
    Module module,
    Map<String, WorkspaceSession> sessionsByModuleId,
  ) {
    // Auto-clear stale WebView failures when a module *recovers* — i.e.
    // transitions from a non-ready state back to running/degraded.  We
    // deliberately do NOT clear failures that were recorded while the
    // module was already running (those are fresh errors, not stale ones
    // from a prior crash), because clearing them would restart the WebView
    // and cause an infinite flicker loop.
    //
    // Strategy: compare current status against the status we saw in the
    // previous build.  A non-ready → ready transition signals recovery.
    // The failure object itself is captured so the postFrameCallback only
    // removes it if a newer failure has not already replaced it.
    final prevStatus = _prevModuleStatuses[module.id];
    final currentStatus = module.status;
    _prevModuleStatuses[module.id] = currentStatus;

    final isNowReady = currentStatus == ModuleStatus.running ||
        currentStatus == ModuleStatus.degraded;
    final wasPreviouslyReady = prevStatus == ModuleStatus.running ||
        prevStatus == ModuleStatus.degraded;

    if (isNowReady &&
        !wasPreviouslyReady &&
        prevStatus != null &&
        _moduleLoadFailures.containsKey(module.id)) {
      final staleFailure = _moduleLoadFailures[module.id];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Guard: only clear the exact failure that triggered this recovery.
        // If the user navigated away and a newer failure was recorded,
        // leave it in place.
        if (_moduleLoadFailures[module.id] == staleFailure) {
          setState(() {
            _moduleLoadFailures.remove(module.id);
            _controllers.remove(module.id);
          });
        }
      });
    }

    final session = sessionsByModuleId[module.id];
    final loadFailure = _moduleLoadFailures[module.id];
    final supported = _isWebViewSupported();
    final launchBlocked =
        module.isPreflightFailed || module.status == ModuleStatus.error;
    final isReady = module.status == ModuleStatus.running ||
        module.status == ModuleStatus.degraded;

    return Container(
      key: ValueKey(module.id),
      child: launchBlocked
          ? NmtkEmptyState(
              title: '${module.name} Could Not Start',
              message: [
                module.statusMessage ?? 'This module could not be started.',
                if (module.capabilityWarnings.isNotEmpty)
                  module.capabilityWarnings.join('\n'),
              ].join('\n\n'),
              icon: ZetaIcons.error_outline,
              tone: NmtkTone.danger,
              action: NmtkPrimaryButton(
                onPressed: () => _activateModule(
                  module.id,
                  requestFocus: false,
                ),
                icon: ZetaIcons.refresh,
                label: 'Retry Start',
                tone: NmtkTone.danger,
              ),
            )
          : session == null || !isReady
              ? _buildLoadingState(module)
              : loadFailure != null
                  ? _buildModuleLoadFailureState(module, loadFailure)
                  : session.surfaceMode == 'native'
                      ? NmtkHostNavigationScope(
                          navigator: _handleHostedModuleNavigationRequest,
                          child: NativeSurfaceRegistry.build(
                            module.id,
                            session,
                          ),
                        )
                      : supported
                          ? _buildWebView(module)
                          : NmtkEmptyState(
                              title: 'WebView Not Supported',
                              message:
                                  '${module.name} cannot be displayed on this platform.',
                              icon: ZetaIcons.warning_outline,
                              tone: NmtkTone.warning,
                            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moduleStateAsync = ref.watch(moduleNotifierProvider);
    final moduleState = moduleStateAsync.value;
    final workspaceStateAsync = ref.watch(workspaceNotifierProvider);
    final workspaceState = workspaceStateAsync.value;
    final tokens = NmtkShellTokens.of(context);

    // Compute eligibleModules early so ref.listen can close over it.
    final eligibleModules = moduleState == null
        ? const <Module>[]
        : moduleState.modules.where(_shouldOpenModule).toList(growable: false);

    // Unconditional ref.listen — must be called on every build, before any returns.
    ref.listen(workspaceNotifierProvider, (prev, next) {
      final ws = next.value;
      if (ws == null || eligibleModules.isEmpty) return;
      final eligibleIds = eligibleModules.map((m) => m.id).toSet();
      String newId = _activeModuleId;
      if (ws.focusedModuleId != null &&
          eligibleIds.contains(ws.focusedModuleId) &&
          ws.focusedModuleId != _activeModuleId) {
        newId = ws.focusedModuleId!;
      } else if (!eligibleIds.contains(_activeModuleId)) {
        newId = eligibleModules.first.id;
      }
      if (newId != _activeModuleId) setState(() => _activeModuleId = newId);
    });

    if (moduleState == null || workspaceState == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sessions = workspaceState.sessions;

    if (!_workspaceInitialized &&
        !moduleStateAsync.isLoading &&
        !workspaceStateAsync.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeWorkspace();
      });
    }

    // Build the horizontal workspace destinations from the eligible module
    // manifest, not only the currently open workspace sessions.
    final navItems = eligibleModules
        .map(
          (Module module) => NmtkSidebarItem(
            id: module.id,
            label: module.name,
            icon: ModuleIcon.forModule(module),
            selectedIcon: ModuleIcon.forModule(module, selected: true),
          ),
        )
        .toList(growable: false);

    final isMobile = MediaQuery.sizeOf(context).width < 840;

    if (eligibleModules.isEmpty) {
      if (isMobile) {
        return NmtkMobileScaffold(
          navItems: const [],
          selectedIndex: 0,
          pageTitle: 'NeuroToolkit',
          onSettingsPressed: () => context.push('/settings'),
          child: const ModulePickerPanel(),
        );
      }
      return Scaffold(
        backgroundColor: tokens.shellBackground,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NmtkTopAppBar(
                mode: NmtkShellMode.command,
                title: const Text('NeuroToolkit'),
                destinations: const [],
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                actions: [
                  NmtkTopAppBarAction(
                    icon: ZetaIcons.settings,
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              const Expanded(child: ModulePickerPanel()),
            ],
          ),
        ),
      );
    }

    final eligibleModuleIds =
        eligibleModules.map((Module module) => module.id).toSet();
    final focusedModuleId = workspaceState.focusedModuleId;

    // Sync _activeModuleId to workspace focus without calling setState during
    // build. Mutations are deferred to a post-frame callback so the framework
    // never sees state changes mid-layout (avoids assertion failures).
    final desiredModuleId = () {
      if (focusedModuleId != null &&
          eligibleModuleIds.contains(focusedModuleId) &&
          focusedModuleId != _activeModuleId) {
        return focusedModuleId;
      }
      if (!eligibleModuleIds.contains(_activeModuleId)) {
        return eligibleModules.first.id;
      }
      return _activeModuleId;
    }();
    if (desiredModuleId != _activeModuleId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activeModuleId = desiredModuleId);
      });
    }

    final selectedIndex = navItems
        .indexWhere((NmtkSidebarItem item) => item.id == desiredModuleId);
    final clampedIndex = selectedIndex < 0 ? 0 : selectedIndex;

    final sessionsByModuleId = <String, WorkspaceSession>{
      for (final session in sessions) session.moduleId: session,
    };

    if (isMobile) {
      // On mobile, filter out desktop-only modules (e.g. Neurobench) from the
      // bottom nav and the content stack. Both lists must stay in sync so that
      // selectedIndex correctly maps a nav tap to its content pane.
      final mobileModules = eligibleModules
          .where((m) => !_kMobileHiddenModuleIds.contains(m.id))
          .toList(growable: false);
      final mobileNavItems = mobileModules
          .map(
            (Module module) => NmtkSidebarItem(
              id: module.id,
              label: module.name,
              icon: ModuleIcon.forModule(module),
              selectedIcon: ModuleIcon.forModule(module, selected: true),
            ),
          )
          .toList(growable: false);
      // If the currently active module is hidden on mobile, fall back to the
      // first visible module so the user always sees a valid pane.
      final mobileActiveId = _kMobileHiddenModuleIds.contains(desiredModuleId)
          ? (mobileModules.isNotEmpty
              ? mobileModules.first.id
              : desiredModuleId)
          : desiredModuleId;
      final mobileSelectedIndex =
          mobileNavItems.indexWhere((item) => item.id == mobileActiveId);
      final mobileClampedIndex =
          mobileSelectedIndex < 0 ? 0 : mobileSelectedIndex;
      return NmtkMobileScaffold(
        navItems: mobileNavItems,
        selectedIndex: mobileClampedIndex,
        onNavItemSelected: (i) {
          if (i < mobileNavItems.length) {
            setState(() => _activeModuleId = mobileNavItems[i].id);
          }
        },
        onSettingsPressed: null,
        showBottomNavigation: false,
        child: IndexedStack(
          key: const ValueKey('WorkspaceStack'),
          index: mobileClampedIndex,
          children: mobileModules
              .map((module) => _buildModuleChild(module, sessionsByModuleId))
              .toList(growable: false),
        ),
      );
    }

    final activeModule = eligibleModules[clampedIndex];

    return Scaffold(
      backgroundColor: tokens.shellBackground,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NmtkTopAppBar(
              mode: NmtkShellMode.command,
              title: const Text('NeuroToolkit'),
              destinations: navItems
                  .map((item) => NavigationDestinationData(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: item.label,
                      ))
                  .toList(),
              selectedIndex: clampedIndex,
              onDestinationSelected: (i) async {
                await _activateModule(navItems[i].id, requestFocus: true);
              },
              actions: [
                NmtkTopAppBarAction(
                  icon: Icons.settings_rounded,
                  tooltip: 'Settings',
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
            Expanded(
              child: PageTransitionSwitcher(
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                  animation: animation,
                  secondaryAnimation: secondaryAnimation,
                  child: child,
                ),
                child: KeyedSubtree(
                  key: ValueKey<String>(desiredModuleId),
                  child: _buildModuleChild(activeModule, sessionsByModuleId),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
