import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/models/workspace_session.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';
import 'package:neuro_toolkit/workspace/native_surface_registry.dart';

class ToolViewScreen extends ConsumerStatefulWidget {
  const ToolViewScreen({super.key, this.initialModuleId});

  final String? initialModuleId;

  @override
  ConsumerState<ToolViewScreen> createState() => _ToolViewScreenState();
}

class _ToolViewScreenState extends ConsumerState<ToolViewScreen> {
  final Map<String, WebViewController> _controllers =
      <String, WebViewController>{};
  final Map<String, bool> _readyStatus = <String, bool>{};
  final Map<String, Timer> _pollTimers = <String, Timer>{};
  final Map<String, Uri> _pendingModuleRequests = <String, Uri>{};

  String _activeModuleId = '';
  bool _handledInitialModule = false;

  String _serviceHost() {
    if (!kIsWeb) return 'localhost';
    final host = Uri.base.host.trim();
    if (host.isEmpty || host == '0.0.0.0') {
      return 'localhost';
    }
    return host;
  }

  String _serviceScheme() {
    if (!kIsWeb) return 'http';
    final scheme = Uri.base.scheme.trim();
    return scheme.isEmpty ? 'http' : scheme;
  }

  Uri _moduleUri(Module module, {bool healthCheck = false}) {
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
      await _ensureInitialSession();
      _startPollingForWorkspaceSessions();
    });
  }

  @override
  void didUpdateWidget(ToolViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialModuleId != oldWidget.initialModuleId) {
      _handledInitialModule = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _ensureInitialSession();
        _startPollingForWorkspaceSessions();
      });
    }
  }

  @override
  void dispose() {
    for (final timer in _pollTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Future<void> _ensureInitialSession() async {
    if (_handledInitialModule) {
      return;
    }
    _handledInitialModule = true;
    final moduleId = widget.initialModuleId;
    if (moduleId == null || moduleId.isEmpty) {
      return;
    }

    final moduleProvider = ref.read(moduleStateProvider);
    final workspaceProvider = ref.read(workspaceStateProvider);
    final module = _findModule(moduleProvider, moduleId);
    if (module == null) {
      return;
    }

    if (module.status != ModuleStatus.running &&
        module.status != ModuleStatus.degraded) {
      await moduleProvider.launchModule(moduleId);
    }
    await workspaceProvider.openSession(
      moduleId,
      surfaceMode: _surfaceModeForModule(moduleId),
      deepLink: null,
      readinessState:
          _surfaceModeForModule(moduleId) == 'native' ? 'ready' : 'opening',
    );
    if (mounted) {
      setState(() {
        _activeModuleId = moduleId;
      });
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

  void _startPollingForWorkspaceSessions() {
    final moduleProvider = ref.read(moduleStateProvider);
    final workspaceProvider = ref.read(workspaceStateProvider);
    for (final session in workspaceProvider.sessions) {
      if (session.surfaceMode == 'native') {
        _readyStatus[session.moduleId] = true;
        unawaited(
          workspaceProvider.updateSession(
            session.moduleId,
            readinessState: 'ready',
          ),
        );
        continue;
      }
      final module = _findModule(moduleProvider, session.moduleId);
      if (module == null) {
        continue;
      }
      if (module.isPreflightFailed || module.status == ModuleStatus.error) {
        _pollTimers[module.id]?.cancel();
        _pollTimers.remove(module.id);
        unawaited(
          workspaceProvider.updateSession(
            module.id,
            readinessState: 'error',
          ),
        );
        continue;
      }
      if (!(_readyStatus[module.id] ?? false) &&
          !_pollTimers.containsKey(module.id)) {
        _pollModuleHealth(module);
      }
    }
  }

  void _pollModuleHealth(Module module) {
    final workspaceProvider = ref.read(workspaceStateProvider);
    _pollTimers[module.id] = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      try {
        if (module.effectivePort == null ||
            module.isPreflightFailed ||
            module.status == ModuleStatus.error) {
          timer.cancel();
          _pollTimers.remove(module.id);
          await workspaceProvider.updateSession(
            module.id,
            readinessState: 'error',
          );
          return;
        }
        final healthUri = _moduleUri(module, healthCheck: true);
        final response =
            await http.get(healthUri).timeout(const Duration(seconds: 1));
        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _readyStatus[module.id] = true;
            });
          }
          timer.cancel();
          _pollTimers.remove(module.id);
          await workspaceProvider.updateSession(
            module.id,
            readinessState: 'ready',
          );
        }
      } catch (e) {
        debugPrint('Polling health for ${module.name} failed: $e');
      }
    });
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
          onNavigationRequest: (request) async {
            final handled = await _handleCrossModuleNavigation(
              module,
              Uri.parse(request.url),
            );
            return handled
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint(
                'WebView error for ${module.name}: ${error.description}');
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not launch $url')));
      }
    }
  }

  bool _isWebViewSupported() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
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

    if (targetModule.status != ModuleStatus.running &&
        targetModule.status != ModuleStatus.degraded) {
      await moduleProvider.launchModule(targetModule.id);
    }

    await workspaceProvider.openSession(
      targetModule.id,
      surfaceMode: _surfaceModeForModule(targetModule.id),
      deepLink: navigation.targetUri.path,
      readinessState: _surfaceModeForModule(targetModule.id) == 'native'
          ? 'ready'
          : 'opening',
    );

    if (_controllers.containsKey(targetModule.id)) {
      _pendingModuleRequests.remove(targetModule.id);
      await _controllers[targetModule.id]!.loadRequest(navigation.targetUri);
    }

    if (mounted) {
      setState(() {
        _activeModuleId = targetModule.id;
      });
    }
    await workspaceProvider.focusSession(targetModule.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final moduleProvider = ref.watch(moduleStateProvider);
    final workspaceProvider = ref.watch(workspaceStateProvider);
    final sessions = workspaceProvider.sessions;

    if (sessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: const NmtkEmptyState(
          title: 'No Active Workspace',
          message: 'Launch a module from the Dashboard to open it here.',
          icon: Icons.laptop_outlined,
        ),
      );
    }

    final focusedModuleId = workspaceProvider.focusedModuleId;
    if (focusedModuleId != null && focusedModuleId != _activeModuleId) {
      _activeModuleId = focusedModuleId;
    }
    if (!sessions.any((session) => session.moduleId == _activeModuleId)) {
      _activeModuleId = sessions.last.moduleId;
    }

    final sessionEntries = sessions
        .map((session) =>
            (session, _findModule(moduleProvider, session.moduleId)))
        .where((entry) => entry.$2 != null)
        .map((entry) => (entry.$1, entry.$2!))
        .toList(growable: false);
    if (sessionEntries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: const NmtkEmptyState(
          title: 'Workspace Unavailable',
          message:
              'The saved workspace refers to modules that are not available.',
          icon: Icons.error_outline,
          tone: NmtkTone.warning,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ModuleTabBar(
            activeModuleId: _activeModuleId,
            onTabSelected: (String id) async {
              setState(() {
                _activeModuleId = id;
              });
              await workspaceProvider.focusSession(id);
              _startPollingForWorkspaceSessions();
            },
            onTabClosed: (String id) async {
              _pollTimers[id]?.cancel();
              _pollTimers.remove(id);
              await workspaceProvider.closeSession(id);
              if (workspaceProvider.sessions.isEmpty && mounted) {
                context.go('/');
              }
            },
          ),
        ),
        actions: [
          Semantics(
            label: 'Open module in system browser',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: () {
                final active = sessionEntries.firstWhere(
                  (entry) => entry.$1.moduleId == _activeModuleId,
                );
                _launchInBrowser(active.$2);
              },
              tooltip: 'Open in System Browser',
            ),
          ),
          Semantics(
            label: 'Stop currently active module',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              onPressed: () {
                final idToStop = _activeModuleId;
                unawaited(moduleProvider.stopModule(idToStop));
                _pollTimers[idToStop]?.cancel();
                _pollTimers.remove(idToStop);
              },
              tooltip: 'Stop Module',
            ),
          ),
        ],
      ),
      body: IndexedStack(
        key: const ValueKey('WorkspaceStack'),
        index: sessionEntries
            .indexWhere((entry) => entry.$1.moduleId == _activeModuleId),
        children: sessionEntries.map((entry) {
          final session = entry.$1;
          final module = entry.$2;
          final isReady =
              _readyStatus[module.id] ?? session.surfaceMode == 'native';
          final supported = _isWebViewSupported();
          final launchBlocked =
              module.isPreflightFailed || module.status == ModuleStatus.error;

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
                      onPressed: () => moduleProvider.launchModule(module.id),
                      icon: Icons.refresh,
                      label: 'Retry Start',
                      tone: NmtkTone.danger,
                    ),
                  )
                : !isReady
                    ? NmtkEmptyState(
                        title: 'Waiting for ${module.name}',
                        message: [
                          if (module.statusMessage != null)
                            module.statusMessage!,
                          if (session.surfaceMode == 'embedded')
                            'Checking ${_moduleUri(module, healthCheck: true)}'
                          else
                            'Restoring native workspace session',
                        ].join('\n\n'),
                        icon: Icons.sync,
                        tone: NmtkTone.info,
                        action: NmtkOutlinedButton(
                          onPressed: () => _launchInBrowser(module),
                          icon: Icons.open_in_browser,
                          label: 'Open in Browser instead',
                          tone: NmtkTone.info,
                        ),
                      )
                    : session.surfaceMode == 'native'
                        ? NativeSurfaceRegistry.build(module.id, session)
                        : supported
                            ? WebViewWidget(controller: _getController(module))
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
        }).toList(),
      ),
    );
  }
}
