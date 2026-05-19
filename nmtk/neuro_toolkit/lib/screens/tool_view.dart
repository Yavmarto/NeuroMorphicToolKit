import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/widgets/module_error_view.dart';
import 'package:neuro_toolkit/widgets/module_icon.dart';
import 'package:neuro_toolkit/widgets/module_loading_view.dart';
import 'package:neuro_toolkit/widgets/module_picker_panel.dart';
import 'package:neuro_toolkit/widgets/tool_view_header_actions.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';
import 'package:neuro_toolkit/providers/command_provider.dart';

class ToolViewScreen extends ConsumerStatefulWidget {
  const ToolViewScreen({super.key, this.initialModuleId});

  final String? initialModuleId;

  @override
  ConsumerState<ToolViewScreen> createState() => _ToolViewScreenState();
}

class _ToolViewScreenState extends ConsumerState<ToolViewScreen> {
  final Map<String, WebViewController> _controllers =
      <String, WebViewController>{};
  final Map<String, Uri> _pendingModuleRequests = <String, Uri>{};
  final Map<String, ModuleLoadFailure> _moduleLoadFailures =
      <String, ModuleLoadFailure>{};

  String _activeModuleId = '';
  bool _workspaceInitialized = false;

  Uri _launcherBaseUri() => ref.read(controlApiServiceProvider).baseUri;

  bool _usesRemoteHostedServices() {
    if (kIsWeb) {
      return false;
    }
    return !ControlApiService.isLoopbackHost(_launcherBaseUri().host);
  }

  String _serviceHost() {
    if (!kIsWeb) {
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

    // Legacy fallback for standalone modules
    final path = healthCheck ? '/health' : (module.hasFrontend ? '' : '/docs');
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
    final moduleProvider = ref.read(moduleStateProvider);
    final workspaceProvider = ref.read(workspaceStateProvider);
    if (moduleProvider.isLoading || workspaceProvider.isLoading) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _initializeWorkspace(forceFocus: forceFocus);
        });
      }
      return;
    }

    final eligibleModules =
        moduleProvider.modules.where(_shouldOpenModule).toList(growable: false);
    if (eligibleModules.isEmpty) {
      return;
    }

    final existingSessions = <String, WorkspaceSession>{
      for (final session in workspaceProvider.sessions)
        session.moduleId: session,
    };
    final desiredSessions = eligibleModules
        .map(
          (module) =>
              (existingSessions[module.id] ?? _defaultSessionFor(module))
                  .copyWith(
            surfaceMode: _surfaceModeForModule(module.id),
            readinessState: _readinessStateForModule(module),
          ),
        )
        .toList(growable: false);
    final targetModuleId =
        _preferredModuleId(eligibleModules, workspaceProvider, forceFocus) ??
            eligibleModules.first.id;

    await workspaceProvider.ensureDefaultSessionsOnce(
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
    WorkspaceProvider workspaceProvider,
    bool forceFocus,
  ) {
    final eligibleIds = eligibleModules.map((module) => module.id).toSet();
    final requestedModuleId = widget.initialModuleId;
    if (requestedModuleId != null && eligibleIds.contains(requestedModuleId)) {
      return requestedModuleId;
    }
    final focusedModuleId = workspaceProvider.focusedModuleId;
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
    final moduleProvider = ref.read(moduleStateProvider);
    final workspaceProvider = ref.read(workspaceStateProvider);
    final module = _findModule(moduleProvider, moduleId);
    if (module == null) {
      return;
    }

    WorkspaceSession? currentSession;
    for (final session in workspaceProvider.sessions) {
      if (session.moduleId == moduleId) {
        currentSession = session;
        break;
      }
    }
    final desiredReadiness = _readinessStateForModule(module);
    if (currentSession == null) {
      await workspaceProvider.openSession(
        moduleId,
        surfaceMode: _surfaceModeForModule(moduleId),
        readinessState: desiredReadiness,
      );
    } else if (requestFocus) {
      await workspaceProvider.focusSession(moduleId);
    }
    if (mounted) {
      setState(() {
        _activeModuleId = moduleId;
        _moduleLoadFailures.remove(moduleId);
      });
    }

    if (currentSession != null &&
        currentSession.readinessState != desiredReadiness) {
      await workspaceProvider.updateSession(
        moduleId,
        readinessState: desiredReadiness,
      );
    }

    if (module.status != ModuleStatus.running &&
        module.status != ModuleStatus.degraded &&
        module.status != ModuleStatus.starting) {
      await workspaceProvider.updateSession(
        moduleId,
        readinessState: 'warming_up',
      );
      await moduleProvider.launchModule(moduleId);
    }
  }

  Module? _findModule(ModuleProvider provider, String moduleId) {
    for (final module in provider.modules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }

  WebViewController _getController(Module module) {
    if (_controllers.containsKey(module.id)) {
      return _controllers[module.id]!;
    }

    final initialUri =
        _pendingModuleRequests.remove(module.id) ?? _moduleUri(module);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) {
              return;
            }
            setState(() {
              _moduleLoadFailures.remove(module.id);
            });
          },
          onNavigationRequest: (request) async {
            final handled = await _handleCrossModuleNavigation(
              module,
              Uri.parse(request.url),
            );
            return handled
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
          onHttpError: (HttpResponseError error) {
            final response = error.response;
            final request = error.request;
            final uri = response?.uri ?? request?.uri ?? _moduleUri(module);
            final statusCode = response?.statusCode;
            final message = statusCode == null
                ? 'Embedded module request failed before the page could load.'
                : 'Embedded module returned HTTP $statusCode instead of a frontend page.';
            _recordModuleLoadFailure(
              module.id,
              uri,
              message,
            );
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint(
              'WebView error for ${module.name}: ${error.description}',
            );
            if (error.isForMainFrame == false) {
              return;
            }
            final failedUrl = error.url;
            _recordModuleLoadFailure(
              module.id,
              failedUrl == null ? _moduleUri(module) : Uri.parse(failedUrl),
              error.description,
            );
          },
        ),
      )
      ..loadRequest(initialUri);

    _controllers[module.id] = controller;
    return controller;
  }

  Future<void> _launchInBrowser(Module module) async {
    final uri = _moduleUri(module);
    final url = uri.toString();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        NmtkToasts.error(context, 'Could not launch $url');
      }
    }
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
      onOpenInBrowser: () => _launchInBrowser(module),
    );
  }

  bool _isWebViewSupported() {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  void _showModulePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: const ModulePickerPanel(),
      ),
    );
  }

  Future<bool> _handleCrossModuleNavigation(
    Module currentModule,
    Uri requestUri,
  ) async {
    final moduleProvider = ref.read(moduleStateProvider);
    final workspaceProvider = ref.read(workspaceStateProvider);
    final navigation = resolveCrossModuleNavigation(
      targetUri: requestUri,
      modules: moduleProvider.modules,
      currentModuleId: currentModule.id,
    );
    if (navigation == null) {
      return false;
    }

    final targetModule = navigation.targetModule;
    _pendingModuleRequests[targetModule.id] = navigation.targetUri;

    await workspaceProvider.openSession(
      targetModule.id,
      surfaceMode: _surfaceModeForModule(targetModule.id),
      deepLink: launcherDeepLinkFromUri(navigation.targetUri),
      readinessState: 'opening',
    );

    if (_controllers.containsKey(targetModule.id)) {
      _pendingModuleRequests.remove(targetModule.id);
      await _controllers[targetModule.id]!.loadRequest(navigation.targetUri);
    }

    await _activateModule(targetModule.id, requestFocus: true);
    return true;
  }

  Future<bool> _handleHostedModuleNavigationRequest(
    NmtkHostNavigationRequest request,
  ) async {
    final moduleProvider = ref.read(moduleStateProvider);
    final workspaceProvider = ref.read(workspaceStateProvider);
    final targetModule = _findModule(moduleProvider, request.moduleId);
    if (targetModule == null || !_shouldOpenModule(targetModule)) {
      return false;
    }

    final existingSession = workspaceProvider.sessions
        .where((session) => session.moduleId == targetModule.id)
        .cast<WorkspaceSession?>()
        .firstWhere(
          (session) => session != null,
          orElse: () => null,
        );
    final restoreState = Map<String, dynamic>.from(request.restoreState);
    final readinessState = _readinessStateForModule(targetModule);

    if (existingSession == null) {
      await workspaceProvider.openSession(
        targetModule.id,
        surfaceMode: _surfaceModeForModule(targetModule.id),
        deepLink: request.deepLink,
        restoreState: restoreState,
        readinessState: readinessState,
      );
    } else {
      await workspaceProvider.updateSession(
        targetModule.id,
        deepLink: request.deepLink,
        restoreState: restoreState,
        readinessState: readinessState,
      );
    }

    await _activateModule(targetModule.id, requestFocus: true);
    return true;
  }

  Widget _buildLoadingState(Module module) {
    return ModuleLoadingView(
      module: module,
      healthCheckUri: _moduleUri(module, healthCheck: true),
      onOpenInBrowser: () => _launchInBrowser(module),
    );
  }

  Widget _buildHeaderActions(
    BuildContext context,
    ModuleProvider moduleProvider,
    Module? activeModule,
  ) {
    return ToolViewHeaderActions(
      moduleProvider: moduleProvider,
      activeModule: activeModule,
      onShowModulePicker: () => _showModulePicker(context),
      onOpenInBrowser: _launchInBrowser,
    );
  }

  @override
  Widget build(BuildContext context) {
    final moduleProvider = ref.watch(moduleStateProvider);
    final workspaceProvider = ref.watch(workspaceStateProvider);
    final sessions = workspaceProvider.sessions;
    final eligibleModules =
        moduleProvider.modules.where(_shouldOpenModule).toList(growable: false);

    if (!_workspaceInitialized &&
        !moduleProvider.isLoading &&
        !workspaceProvider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _initializeWorkspace();
      });
    }

    // Build sidebar nav items from the eligible module manifest, not only the
    // currently open workspace sessions.
    final navItems = eligibleModules
        .map(
          (module) => NmtkSidebarItem(
            id: module.id,
            label: module.name,
            icon: ModuleIcon.forModule(module),
            selectedIcon: ModuleIcon.forModule(module, selected: true),
          ),
        )
        .toList(growable: false);

    final selectedIndex =
        navItems.indexWhere((item) => item.id == _activeModuleId);
    final clampedIndex = _activeModuleId == 'settings'
        ? eligibleModules.length
        : (selectedIndex < 0 ? 0 : selectedIndex);

    if (eligibleModules.isEmpty) {
      return NmtkDesktopScaffold(
        pageTitle: 'NeuroToolkit',
        navItems: const [],
        selectedIndex: 0,
        mode: NmtkShellMode.command,
        footerNavItems: const [
          NmtkSidebarItem(
            id: 'settings',
            label: 'Settings',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
          ),
        ],
        onFooterNavItemSelected: (_) => context.go('/settings'),
        child: const ModulePickerPanel(),
      );
    }

    final eligibleModuleIds =
        eligibleModules.map((module) => module.id).toSet();
    final focusedModuleId = workspaceProvider.focusedModuleId;

    // Only sync focus from the provider if we are not currently in Settings.
    // Explicit navigation to modules via _activateModule will still work as it
    // calls setState internally.
    if (_activeModuleId != 'settings') {
      if (focusedModuleId != null &&
          eligibleModuleIds.contains(focusedModuleId) &&
          focusedModuleId != _activeModuleId) {
        _activeModuleId = focusedModuleId;
      }
      if (!eligibleModuleIds.contains(_activeModuleId)) {
        _activeModuleId = eligibleModules.first.id;
      }
    }

    final sessionsByModuleId = <String, WorkspaceSession>{
      for (final session in sessions) session.moduleId: session,
    };

    final activeModule = eligibleModules.firstWhere(
      (module) => module.id == _activeModuleId,
      orElse: () => eligibleModules.first,
    );

    // ── Normal workspace ─────────────────────────────────────────────────────
    return NmtkDesktopScaffold(
      pageTitle: _activeModuleId == 'settings' ? 'Settings' : activeModule.name,
      navItems: navItems,
      selectedIndex: clampedIndex < navItems.length ? clampedIndex : -1,
      onNavItemSelected: (i) async {
        await _activateModule(navItems[i].id, requestFocus: true);
      },
      footerNavItems: const [
        NmtkSidebarItem(
          id: 'settings',
          label: 'Settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
        ),
      ],
      onFooterNavItemSelected: (_) =>
          setState(() => _activeModuleId = 'settings'),
      headerActions: _buildHeaderActions(context, moduleProvider, activeModule),
      mode: NmtkShellMode.command,
      child: IndexedStack(
        key: const ValueKey('WorkspaceStack'),
        index: clampedIndex,
        children: eligibleModules.map((module) {
          // When a module's backend recovers (status transitions back to
          // running/degraded), auto-clear any stale WebView load failure so
          // the user doesn't have to click Retry manually. Also evict the
          // stale controller so the page reloads fresh from the recovered URL.
          if (_moduleLoadFailures.containsKey(module.id) &&
              (module.status == ModuleStatus.running ||
                  module.status == ModuleStatus.degraded)) {
            _moduleLoadFailures.remove(module.id);
            _controllers.remove(module.id);
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
                      module.statusMessage ??
                          'This module could not be started.',
                      if (module.capabilityWarnings.isNotEmpty)
                        module.capabilityWarnings.join('\n'),
                    ].join('\n\n'),
                    icon: Icons.error_outline,
                    tone: NmtkTone.danger,
                    action: NmtkPrimaryButton(
                      onPressed: () => _activateModule(
                        module.id,
                        requestFocus: false,
                      ),
                      icon: Icons.refresh,
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
                                ? WebViewWidget(
                                    controller: _getController(module),
                                  )
                                : NmtkEmptyState(
                                    title: 'WebView Not Supported',
                                    message:
                                        'Open ${module.name} in your system browser on this platform.',
                                    icon: Icons.warning_amber_rounded,
                                    tone: NmtkTone.warning,
                                    action: NmtkPrimaryButton(
                                      onPressed: () => _launchInBrowser(module),
                                      icon: Icons.open_in_browser,
                                      label: 'Open in System Browser',
                                      tone: NmtkTone.warning,
                                    ),
                                  ),
          );
        }).toList()
          ..add(
            Container(
              key: const ValueKey('settings'),
              child: _activeModuleId == 'settings'
                  ? const SettingsScreen()
                  : const SizedBox.shrink(),
            ),
          ),
      ),
    );
  }
}
