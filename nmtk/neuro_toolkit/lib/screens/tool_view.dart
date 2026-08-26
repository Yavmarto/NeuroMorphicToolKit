import 'dart:async';
import 'dart:io';
import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neurocnl_studio/screens/hub_popup.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/backend_tunnel_service.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';
import 'package:neuro_toolkit/src/features/module/domain/module_state.dart';
import 'package:neuro_toolkit/src/features/workspace/domain/workspace_state.dart';
import 'package:neuro_toolkit/widgets/connection_error_actions.dart';
import 'package:neuro_toolkit/widgets/module_error_view.dart';
import 'package:neuro_toolkit/widgets/module_icon.dart';
import 'package:neuro_toolkit/widgets/module_loading_view.dart';
import 'package:neuro_toolkit/widgets/module_picker_panel.dart';
import 'package:neuro_toolkit/widgets/server_setup_popup.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

part 'tool_view/inline_server_connection_control.dart';
part 'tool_view/launcher_profile_button.dart';

class ToolViewScreen extends ConsumerStatefulWidget {
  const ToolViewScreen({super.key});

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
  // Guards the entire async _initializeWorkspace() operation (not just its
  // aftermath) so overlapping rebuilds during boot — e.g. a module flipping
  // starting -> running while ensureDefaultSessionsOnce is still in flight —
  // can never queue a second concurrent run. A second concurrent run can
  // transiently churn workspaceState.focusedModuleId, which remounts the
  // active module's KeyedSubtree and re-triggers its startup dialogs.
  bool _workspaceInitializing = false;
  int _workspaceServerGeneration = 0;

  Uri? _launcherBaseUri() =>
      ref.read(selectedControlApiServiceProvider)?.baseUri;

  BackendTunnelSession? get _tunnelSession =>
      ref.read(backendTunnelServiceProvider).currentSession;

  Future<void> _showServerConnectionPopup(BuildContext context) {
    return showAdaptiveServerSetupPopup(
      context,
      initialHost: _launcherBaseUri()?.toString(),
    );
  }

  /// A compact, host-owned server control for the embedded NeuroCNL toolbar.
  /// Keeping its state and callback here means the Studio package never owns
  /// server selection or creates a parallel connection workflow.
  Widget _buildInlineServerConnectionControl(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _InlineServerConnectionControl(
          onPressed: () => _showServerConnectionPopup(context),
        ),
        const SizedBox(width: 8),
        const LauncherProfileButton(),
      ],
    );
  }

  bool _usesRemoteHostedServices() {
    if (kIsWeb) {
      return false;
    }
    final baseUri = _launcherBaseUri();
    return baseUri != null && !ControlApiService.isLoopbackHost(baseUri.host);
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
      if (baseUri != null && _usesRemoteHostedServices()) {
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
      if (baseUri != null && _usesRemoteHostedServices()) {
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
      final tunnelBase = _tunnelSession?.suiteApiUri;
      if (healthCheck) {
        return tunnelBase?.replace(path: '/api/$moduleId/health') ??
            Uri(
              scheme: _serviceScheme(),
              host: _serviceHost(),
              port: 9000,
              path: '/api/$moduleId/health',
            );
      }
      return tunnelBase?.replace(path: '/$moduleId/') ??
          Uri(
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
    if (module.effectivePort == 8008 && _tunnelSession != null) {
      return _tunnelSession!.jupyterUri.replace(path: path);
    }
    return Uri(
      scheme: _serviceScheme(),
      host: _serviceHost(),
      port: module.effectivePort,
      path: path,
    );
  }

  /// Backend API base URL to hand to a natively-embedded module so it can
  /// skip its own connect prompt — the launcher already knows this host.
  /// Only meaningful for modules sharing the monolith port (9000); other
  /// modules resolve their own backend independently.
  String? _nativeSurfaceServerUrl(Module module) {
    if (module.effectivePort != 9000) {
      return null;
    }
    return (_tunnelSession?.suiteApiUri ??
            Uri(scheme: _serviceScheme(), host: _serviceHost(), port: 9000))
        .replace(path: '/api/neurocnl')
        .toString();
  }

  String _surfaceModeForModule(String moduleId) {
    return NativeSurfaceRegistry.supportsModule(moduleId)
        ? 'native'
        : 'embedded';
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual<LauncherNavigationRequest?>(
      launcherNavigationProvider,
      _handleLauncherNavigation,
    );
    ref.listenManual<AsyncValue<ModuleState>>(
      moduleProvider,
      _handleModuleStateChanged,
      fireImmediately: true,
    );
    ref.listenManual<AsyncValue<WorkspaceState>>(
      workspaceProvider,
      _handleWorkspaceStateChanged,
      fireImmediately: true,
    );
    ref.listenManual<ControlApiService?>(
      selectedControlApiServiceProvider,
      _handleControlApiChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeWorkspace();
    });
  }

  void _handleModuleStateChanged(
    AsyncValue<ModuleState>? previous,
    AsyncValue<ModuleState> next,
  ) {
    final modules = next.value?.modules;
    if (modules == null) return;
    final eligibleModules = modules
        .where(_shouldOpenModule)
        .toList(growable: false);
    var clearedFailure = false;
    for (final module in eligibleModules) {
      final previousStatus = _prevModuleStatuses[module.id];
      final isReady =
          module.status == ModuleStatus.running ||
          module.status == ModuleStatus.degraded;
      final wasReady =
          previousStatus == ModuleStatus.running ||
          previousStatus == ModuleStatus.degraded;
      if (previousStatus != null &&
          isReady &&
          !wasReady &&
          _moduleLoadFailures.remove(module.id) != null) {
        _controllers.remove(module.id);
        clearedFailure = true;
      }
      _prevModuleStatuses[module.id] = module.status;
    }
    _reconcileActiveModule(eligibleModules, ref.read(workspaceProvider).value);
    if (clearedFailure && mounted) setState(() {});
    unawaited(_initializeWorkspace());
  }

  void _handleWorkspaceStateChanged(
    AsyncValue<WorkspaceState>? previous,
    AsyncValue<WorkspaceState> next,
  ) {
    final moduleState = ref.read(moduleProvider).value;
    final workspaceState = next.value;
    if (moduleState == null || workspaceState == null) return;
    final eligibleModules = moduleState.modules
        .where(_shouldOpenModule)
        .toList(growable: false);
    _reconcileActiveModule(eligibleModules, workspaceState);
    unawaited(_initializeWorkspace());
  }

  void _handleControlApiChanged(
    ControlApiService? previous,
    ControlApiService? next,
  ) {
    if (previous?.baseUri == next?.baseUri) return;
    _workspaceServerGeneration++;
    _workspaceInitializing = false;
    if (!mounted) return;
    setState(() {
      _controllers.clear();
      _pendingModuleRequests.clear();
      _moduleLoadFailures.clear();
      _prevModuleStatuses.clear();
    });
    unawaited(_initializeWorkspace());
  }

  void _reconcileActiveModule(
    List<Module> eligibleModules,
    WorkspaceState? workspaceState,
  ) {
    if (!mounted || eligibleModules.isEmpty || workspaceState == null) return;
    final preferred =
        _preferredModuleId(eligibleModules, workspaceState.focusedModuleId) ??
        eligibleModules.first.id;
    if (preferred == _activeModuleId) return;
    setState(() => _activeModuleId = preferred);
  }

  void _handleLauncherNavigation(
    LauncherNavigationRequest? previous,
    LauncherNavigationRequest? next,
  ) {
    if (next == null || previous?.sequence == next.sequence) return;

    switch (next.action) {
      case LauncherNavigationAction.openWorkspace:
        unawaited(_initializeWorkspace());
        return;
      case LauncherNavigationAction.openModule:
        final moduleId = next.moduleId;
        final modules = ref.read(moduleProvider).value?.modules;
        if (moduleId == null || modules == null) return;
        final module = _findModule(modules, moduleId);
        if (module == null || !_shouldOpenModule(module)) return;
        unawaited(_activateModule(moduleId, requestFocus: true));
        return;
      case LauncherNavigationAction.reloadWorkspace:
        unawaited(_reloadWorkspace());
        return;
      case LauncherNavigationAction.toggleSidebar:
        Actions.maybeInvoke(context, const ToggleSidebarIntent());
        return;
    }
  }

  Future<void> _reloadWorkspace() async {
    _workspaceServerGeneration++;
    _workspaceInitializing = false;
    setState(() {
      _controllers.clear();
      _pendingModuleRequests.clear();
      _moduleLoadFailures.clear();
      _prevModuleStatuses.clear();
    });
    await Future.wait([
      ref.refresh(moduleProvider.future),
      ref.refresh(workspaceProvider.future),
    ]);
    if (mounted) {
      await _initializeWorkspace();
    }
  }

  Future<void> _initializeWorkspace() async {
    if (!mounted) return;
    if (_workspaceInitializing) {
      return;
    }
    _workspaceInitializing = true;
    final serverGeneration = _workspaceServerGeneration;
    final baseUri = _launcherBaseUri();
    if (baseUri == null) {
      _workspaceInitializing = false;
      return;
    }
    final serverKey = baseUri.toString();
    try {
      final moduleStateAsync = ref.read(moduleProvider);
      final moduleState = moduleStateAsync.value;
      final workspaceStateAsync = ref.read(workspaceProvider);
      final workspaceState = workspaceStateAsync.value;
      if (moduleStateAsync.isLoading ||
          workspaceStateAsync.isLoading ||
          moduleState == null ||
          workspaceState == null) {
        return;
      }
      if (serverGeneration != _workspaceServerGeneration ||
          serverKey != _launcherBaseUri()?.toString()) {
        return;
      }

      final eligibleModules = moduleState.modules
          .where(_shouldOpenModule)
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
                      surfaceMode: _surfaceModeForModule(module.id),
                      readinessState: _readinessStateForModule(module),
                    ),
          )
          .toList(growable: false);
      final targetModuleId =
          _preferredModuleId(eligibleModules, workspaceState.focusedModuleId) ??
          eligibleModules.first.id;

      if (serverGeneration != _workspaceServerGeneration ||
          serverKey != _launcherBaseUri()?.toString()) {
        return;
      }
      await ref
          .read(workspaceProvider.notifier)
          .ensureDefaultSessionsOnce(
            sessions: desiredSessions,
            focusedModuleId: targetModuleId,
          );
      if (!mounted ||
          serverGeneration != _workspaceServerGeneration ||
          serverKey != _launcherBaseUri()?.toString()) {
        return;
      }

      await _activateModule(targetModuleId, requestFocus: true);
    } finally {
      _workspaceInitializing = false;
    }
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
  ) {
    final eligibleIds = eligibleModules.map((module) => module.id).toSet();
    if (focusedModuleId != null && eligibleIds.contains(focusedModuleId)) {
      return focusedModuleId;
    }
    if (eligibleIds.contains(_activeModuleId)) {
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
    if (!mounted) return;
    final moduleState = ref.read(moduleProvider).value;
    final workspaceState = ref.read(workspaceProvider).value;
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
      await ref
          .read(workspaceProvider.notifier)
          .openSession(
            moduleId,
            surfaceMode: _surfaceModeForModule(moduleId),
            readinessState: desiredReadiness,
          );
    } else if (requestFocus) {
      await ref.read(workspaceProvider.notifier).focusSession(moduleId);
    }
    if (!mounted) return;

    setState(() {
      _activeModuleId = moduleId;
      _moduleLoadFailures.remove(moduleId);
    });

    if (currentSession != null &&
        currentSession.readinessState != desiredReadiness) {
      await ref
          .read(workspaceProvider.notifier)
          .updateSession(moduleId, readinessState: desiredReadiness);
      if (!mounted) return;
    }

    if (module.status != ModuleStatus.running &&
        module.status != ModuleStatus.degraded &&
        module.status != ModuleStatus.starting) {
      await ref
          .read(workspaceProvider.notifier)
          .updateSession(moduleId, readinessState: 'warming_up');
      if (!mounted) return;
      // Jupyter runs as its own Docker container, external to launcher
      // control (startStrategy "none") -- launchModule() there can only
      // re-probe its health, not actually restart it. retryJupyter() is the
      // real fix: it reaches the container over SSH, same as the setup
      // screen's "Recover Jupyter" button.
      if (moduleId == 'jupyter') {
        await ref.read(backendDeploymentProvider.notifier).retryJupyter();
      } else {
        await ref.read(moduleProvider.notifier).launchModule(moduleId);
      }
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
      key: ValueKey<String>(
        'webview-${_launcherBaseUri()?.authority ?? 'disconnected'}-${module.id}',
      ),
      initialUrlRequest: URLRequest(
        url: WebUri.uri(initialUri),
        headers: _tunnelSession?.adminToken.isNotEmpty == true
            ? <String, String>{'X-NMTK-Admin-Token': _tunnelSession!.adminToken}
            : null,
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        transparentBackground: false,
        isInspectable: kDebugMode,
        useOnDownloadStart: true,
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
      onDownloadStartRequest: (controller, downloadRequest) async {
        final uri = downloadRequest.url;
        final urlString = uri.toString();

        if (urlString.startsWith('blob:')) {
          final base64data = await controller.evaluateJavascript(
            source:
                """
            new Promise((resolve, reject) => {
              var xhr = new XMLHttpRequest();
              xhr.open('GET', '$urlString', true);
              xhr.responseType = 'blob';
              xhr.onload = function(e) {
                if (this.status == 200) {
                  var blob = this.response;
                  var reader = new FileReader();
                  reader.readAsDataURL(blob);
                  reader.onloadend = function() {
                    resolve(reader.result);
                  }
                } else {
                  reject('Failed to fetch blob');
                }
              };
              xhr.send();
            });
          """,
          );

          if (base64data != null && base64data is String) {
            final commaIndex = base64data.indexOf(',');
            if (commaIndex != -1) {
              final b64 = base64data.substring(commaIndex + 1);
              final bytes = base64Decode(b64);
              final savePath = await FilePicker.saveFile(
                dialogTitle: 'Save File',
                fileName: downloadRequest.suggestedFilename ?? 'download',
              );
              if (savePath != null) {
                await File(savePath).writeAsBytes(bytes);
              }
            }
          }
        } else if (urlString.startsWith('data:')) {
          final commaIndex = urlString.indexOf(',');
          if (commaIndex != -1) {
            final b64 = urlString.substring(commaIndex + 1);
            final isBase64 = urlString
                .substring(0, commaIndex)
                .contains(';base64');
            final savePath = await FilePicker.saveFile(
              dialogTitle: 'Save File',
              fileName: downloadRequest.suggestedFilename ?? 'download',
            );
            if (savePath != null) {
              if (isBase64) {
                await File(savePath).writeAsBytes(base64Decode(b64));
              } else {
                await File(savePath).writeAsString(Uri.decodeComponent(b64));
              }
            }
          }
        } else {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            debugPrint('Could not launch download URL: $urlString');
          }
        }
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
        _recordModuleLoadFailure(module.id, request.url, error.description);
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
        _recordModuleLoadFailure(module.id, request.url, message);
      },
    );
  }

  void _recordModuleLoadFailure(String moduleId, Uri uri, String message) {
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
    final isRemoteHosted = _usesRemoteHostedServices();
    return ModuleErrorView(
      module: module,
      failure: failure,
      isRemoteHosted: isRemoteHosted,
      onRetry: () async {
        setState(() {
          _moduleLoadFailures.remove(module.id);
          _controllers.remove(module.id);
        });
        await _activateModule(module.id, requestFocus: false);
      },
      // Every module depends on the same one launcher server — "change
      // server" always means reconnecting the whole app, never a per-module
      // override, so it's offered regardless of local vs. remote.
      onChangeServer: () => _showServerConnectionPopup(context),
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
    if (!mounted) return false;
    if (requestUri.scheme == 'nmtk' && requestUri.host == 'system-health') {
      await showAdaptiveServerSetupPopup(
        context,
        message:
            'System Health checks the backend, storage, Jupyter, '
            'snnTorch, launcher control, and configured hardware.',
      );
      return true;
    }
    final moduleState = ref.read(moduleProvider).value;
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

    await ref
        .read(workspaceProvider.notifier)
        .openSession(
          targetModule.id,
          surfaceMode: _surfaceModeForModule(targetModule.id),
          deepLink: launcherDeepLinkFromUri(navigation.targetUri),
          readinessState: 'opening',
        );
    if (!mounted) return false;

    if (_controllers.containsKey(targetModule.id)) {
      _pendingModuleRequests.remove(targetModule.id);
      await _controllers[targetModule.id]!.loadUrl(
        urlRequest: URLRequest(url: WebUri.uri(navigation.targetUri)),
      );
      if (!mounted) return false;
    }

    await _activateModule(targetModule.id, requestFocus: true);
    return true;
  }

  Future<bool> _handleHostedModuleNavigationRequest(
    NmtkFeatureNavigationRequest request,
  ) async {
    if (!mounted) return false;
    final moduleState = ref.read(moduleProvider).value;
    final workspaceState = ref.read(workspaceProvider).value;
    if (moduleState == null || workspaceState == null) return false;

    final targetModule = moduleState.modules
        .where(
          (Module module) =>
              NmtkModuleId.fromExternal(module.id) == request.moduleId,
        )
        .cast<Module?>()
        .firstWhere((Module? module) => module != null, orElse: () => null);
    if (targetModule == null || !_shouldOpenModule(targetModule)) {
      return false;
    }

    final existingSession = workspaceState.sessions
        .where(
          (WorkspaceSession session) => session.moduleId == targetModule.id,
        )
        .cast<WorkspaceSession?>()
        .firstWhere(
          (WorkspaceSession? session) => session != null,
          orElse: () => null,
        );
    final restoreState = Map<String, dynamic>.from(request.restorationState);
    final readinessState = _readinessStateForModule(targetModule);

    if (existingSession == null) {
      await ref
          .read(workspaceProvider.notifier)
          .openSession(
            targetModule.id,
            surfaceMode: _surfaceModeForModule(targetModule.id),
            deepLink: request.deepLink,
            restoreState: restoreState,
            readinessState: readinessState,
          );
    } else {
      await ref
          .read(workspaceProvider.notifier)
          .updateSession(
            targetModule.id,
            deepLink: request.deepLink,
            restoreState: restoreState,
            readinessState: readinessState,
          );
    }
    if (!mounted) return false;

    await _activateModule(targetModule.id, requestFocus: true);
    return true;
  }

  Future<void> _reportHostedFeatureError(
    BuildContext context,
    NmtkFeatureErrorEvent event,
  ) async {
    if (!mounted) return;
    final requiresBackendSetup =
        event.kind == NmtkFeatureErrorKind.connection ||
        event.kind == NmtkFeatureErrorKind.authentication;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(event.message),
        action: requiresBackendSetup
            ? SnackBarAction(
                label: 'Backend Setup',
                onPressed: () => _showServerConnectionPopup(context),
              )
            : null,
      ),
    );
  }

  Widget _buildLoadingState(Module module) {
    return ModuleLoadingView(
      module: module,
      healthCheckUri: _moduleUri(module, healthCheck: true),
    );
  }

  /// Builds the active embedded surface for a module.
  ///
  /// Shared by the desktop [Scaffold] and narrow [NmtkMobileScaffold] paths.
  /// Both paths intentionally mount only their active module: native module
  /// trees and WebViews must be disposed when a user switches away instead of
  /// accumulating hidden frontends in memory.
  Widget _buildModuleChild(
    Module module,
    Map<String, WorkspaceSession> sessionsByModuleId, {
    Widget? workspaceHeaderAction,
  }) {
    final session = sessionsByModuleId[module.id];
    final loadFailure = _moduleLoadFailures[module.id];
    final supported = _isWebViewSupported();
    final launchBlocked =
        module.isPreflightFailed || module.status == ModuleStatus.error;
    final isReady =
        module.status == ModuleStatus.running ||
        module.status == ModuleStatus.degraded;

    // SelectionContainer.disabled: the module workspace (canvases, steppers,
    // buttons) must not inherit the app-wide SelectionArea from LauncherAppHost —
    // Scrollable's text-selection-drag autoscroll trips Flutter's "Drag
    // target size is larger than scrollable size" assert on any short/thin
    // scrollable in that subtree, causing bounce/jank on first press or drag.
    return SelectionContainer.disabled(
      child: KeyedSubtree(
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
                action: ConnectionErrorActions(
                  onRetry: () =>
                      _activateModule(module.id, requestFocus: false),
                  retryLabel: 'Retry Start',
                  // Every module depends on the same one launcher server —
                  // "change server" always means reconnecting the whole app,
                  // never a per-module override.
                  onChangeServer: () => _showServerConnectionPopup(context),
                ),
              )
            : session == null || !isReady
            ? _buildLoadingState(module)
            : loadFailure != null
            ? _buildModuleLoadFailureState(module, loadFailure)
            : session.surfaceMode == 'native'
            ? NativeSurfaceRegistry.build(
                session,
                launchContext: NmtkFeatureLaunchContext(
                  moduleId: NmtkModuleId.fromExternal(module.id),
                  backendUri: Uri.parse(
                    _nativeSurfaceServerUrl(module) ??
                        (throw StateError(
                          'The root launcher must supply a backend URL for ${module.id}.',
                        )),
                  ),
                  authentication: NmtkFeatureAuthentication(
                    adminToken: _tunnelSession?.adminToken ?? '',
                  ),
                  initialLocation:
                      session.deepLink ??
                      (module.id == 'Neurochip' ? '/?panel=deploy' : '/'),
                  restorationState: session.restoreState,
                  onNavigate: _handleHostedModuleNavigationRequest,
                  onReportError: (NmtkFeatureErrorEvent event) =>
                      _reportHostedFeatureError(context, event),
                  onEditServer: () => _showServerConnectionPopup(context),
                  workspaceHeaderAction: workspaceHeaderAction,
                ),
              )
            : supported
            ? _buildWebView(module)
            : NmtkEmptyState(
                title: 'WebView Not Supported',
                message: '${module.name} cannot be displayed on this platform.',
                icon: ZetaIcons.warning_outline,
                tone: NmtkTone.warning,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moduleStateAsync = ref.watch(moduleProvider);
    final moduleState = moduleStateAsync.value;
    final workspaceStateAsync = ref.watch(workspaceProvider);
    final workspaceState = workspaceStateAsync.value;
    final tokens = NmtkShellTokens.of(context);
    final currentServerKey =
        ref.watch(selectedControlApiServiceProvider)?.baseUri.toString() ??
        'disconnected';

    final eligibleModules = moduleState == null
        ? const <Module>[]
        : moduleState.modules.where(_shouldOpenModule).toList(growable: false);

    if (moduleState == null || workspaceState == null) {
      final loadError = moduleStateAsync.error ?? workspaceStateAsync.error;
      if (loadError != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: NmtkEmptyState(
                  title: 'Could Not Load Workspace',
                  message: nmtkUserFacingError(loadError),
                  icon: ZetaIcons.cloud_off,
                  tone: NmtkTone.danger,
                  action: ConnectionErrorActions(
                    onRetry: () {
                      ref.invalidate(moduleProvider);
                      ref.invalidate(workspaceProvider);
                    },
                    onChangeServer: () => _showServerConnectionPopup(context),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        body: Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s)),
      );
    }

    final sessions = workspaceState.sessions;

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
        return const NmtkMobileScaffold(
          mode: NmtkShellMode.command,
          navItems: [],
          selectedIndex: 0,
          pageTitle: 'NeuroToolkit',
          child: ModulePickerPanel(),
        );
      }
      return Scaffold(
        backgroundColor: tokens.shellBackground,
        body: const SafeArea(
          top: false,
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: ModulePickerPanel())],
          ),
        ),
      );
    }

    final eligibleModuleIds = eligibleModules
        .map((Module module) => module.id)
        .toSet();
    final focusedModuleId = workspaceState.focusedModuleId;

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
    final selectedIndex = navItems.indexWhere(
      (NmtkSidebarItem item) => item.id == desiredModuleId,
    );
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
      final mobileSelectedIndex = mobileNavItems.indexWhere(
        (item) => item.id == mobileActiveId,
      );
      final mobileClampedIndex = mobileSelectedIndex < 0
          ? 0
          : mobileSelectedIndex;
      final mobileActiveModule = mobileModules.isNotEmpty
          ? mobileModules[mobileClampedIndex]
          : null;
      final mobileActiveSession = mobileActiveModule != null
          ? sessionsByModuleId[mobileActiveModule.id]
          : null;
      final mobileActiveModuleIsReady =
          mobileActiveModule != null &&
          (mobileActiveModule.status == ModuleStatus.running ||
              mobileActiveModule.status == ModuleStatus.degraded);
      final showMobileInlineServerControl =
          mobileActiveModule?.id == 'neurocnl' &&
          mobileActiveModuleIsReady &&
          mobileActiveSession?.surfaceMode == 'native';

      return NmtkMobileScaffold(
        mode: NmtkShellMode.command,
        navItems: mobileNavItems,
        selectedIndex: mobileClampedIndex,
        onNavItemSelected: (i) {
          if (i < mobileNavItems.length) {
            setState(() => _activeModuleId = mobileNavItems[i].id);
          }
        },
        showBottomNavigation: false,
        // Only the active module's content is built here — unlike an
        // IndexedStack (which would build and keep every eligible module's
        // full subtree alive simultaneously, including full nested apps for
        // native-surface modules and real WebViews), this matches the
        // desktop branch above and builds one module at a time.
        child: mobileModules.isEmpty
            ? const SizedBox.shrink()
            : PageTransitionSwitcher(
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    '$currentServerKey:${mobileActiveModule!.id}',
                  ),
                  child: _buildModuleChild(
                    mobileActiveModule,
                    sessionsByModuleId,
                    workspaceHeaderAction: showMobileInlineServerControl
                        ? _InlineServerConnectionControl(
                            onPressed: () =>
                                _showServerConnectionPopup(context),
                            iconOnly: true,
                          )
                        : null,
                  ),
                ),
              ),
      );
    }

    final activeModule = eligibleModules[clampedIndex];
    final activeSession = sessionsByModuleId[activeModule.id];
    final activeModuleIsReady =
        activeModule.status == ModuleStatus.running ||
        activeModule.status == ModuleStatus.degraded;
    final showInlineServerControl =
        activeModule.id == 'neurocnl' &&
        activeModuleIsReady &&
        activeSession?.surfaceMode == 'native';

    return Scaffold(
      backgroundColor: tokens.shellBackground,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: PageTransitionSwitcher(
                transitionBuilder: (child, animation, secondaryAnimation) =>
                    FadeThroughTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      child: child,
                    ),
                child: KeyedSubtree(
                  key: ValueKey<String>('$currentServerKey:$desiredModuleId'),
                  child: _buildModuleChild(
                    activeModule,
                    sessionsByModuleId,
                    workspaceHeaderAction: showInlineServerControl
                        ? _buildInlineServerConnectionControl(context)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
