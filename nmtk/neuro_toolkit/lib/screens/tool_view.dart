import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/cross_module_navigation.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';

class ToolViewScreen extends ConsumerStatefulWidget {
  final String initialModuleId;

  const ToolViewScreen({super.key, required this.initialModuleId});

  @override
  ConsumerState<ToolViewScreen> createState() => _ToolViewScreenState();
}

class _ToolViewScreenState extends ConsumerState<ToolViewScreen> {
  final Map<String, WebViewController> _controllers = {};
  final Map<String, bool> _readyStatus = {};
  final Map<String, Timer> _pollTimers = {};
  final Map<String, Uri> _pendingModuleRequests = {};
  late String _activeModuleId;

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

  @override
  void initState() {
    super.initState();
    _activeModuleId = widget.initialModuleId;
    _startPollingForActiveModules();
  }

  @override
  void didUpdateWidget(ToolViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialModuleId != oldWidget.initialModuleId) {
      setState(() {
        _activeModuleId = widget.initialModuleId;
      });
      _startPollingForActiveModules();
    }
  }

  @override
  void dispose() {
    for (var timer in _pollTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _startPollingForActiveModules() {
    final provider = ref.read(moduleStateProvider);
    for (final module in provider.activeModules) {
      if (module.isPreflightFailed || module.status == ModuleStatus.error) {
        _pollTimers[module.id]?.cancel();
        _pollTimers.remove(module.id);
        continue;
      }
      if (!(_readyStatus[module.id] ?? false) &&
          !_pollTimers.containsKey(module.id)) {
        _pollModuleHealth(module);
      }
    }
  }

  void _pollModuleHealth(Module module) {
    _pollTimers[module.id] = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      try {
        if (module.effectivePort == null ||
            module.isPreflightFailed ||
            module.status == ModuleStatus.error) {
          timer.cancel();
          _pollTimers.remove(module.id);
          return;
        }
        final healthUri = _moduleUri(module, healthCheck: true);
        final response = await http
            .get(healthUri)
            .timeout(const Duration(seconds: 1));
        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _readyStatus[module.id] = true;
            });
          }
          timer.cancel();
          _pollTimers.remove(module.id);
        }
      } catch (e) {
        if (module.status != ModuleStatus.error && !module.isPreflightFailed) {
          debugPrint('Polling health for ${module.name} failed: $e');
        }
      }
    });
  }

  WebViewController _getController(Module module) {
    if (_controllers.containsKey(module.id)) {
      return _controllers[module.id]!;
    }

    final initialUri =
        _pendingModuleRequests.remove(module.id) ?? _moduleUri(module);
    final url = initialUri.toString();

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
              'WebView error for ${module.name}: ${error.description}',
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

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
    final provider = ref.read(moduleStateProvider);
    final navigation = resolveCrossModuleNavigation(
      targetUri: requestUri,
      modules: provider.modules,
      currentModuleId: currentModule.id,
    );
    if (navigation == null) {
      return false;
    }

    final targetModule = navigation.targetModule;
    _pendingModuleRequests[targetModule.id] = navigation.targetUri;

    if (!provider.activeModuleIds.contains(targetModule.id)) {
      await provider.launchModule(targetModule.id);
    }

    if (_controllers.containsKey(targetModule.id)) {
      _pendingModuleRequests.remove(targetModule.id);
      await _controllers[targetModule.id]!.loadRequest(navigation.targetUri);
    }

    if (mounted) {
      setState(() {
        _activeModuleId = targetModule.id;
      });
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(moduleStateProvider);
    final activeModules = provider.activeModules;

    if (activeModules.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: const NmtkEmptyState(
          title: 'No Active Workspace',
          message: 'Launch a module from the Dashboard to open it here.',
          icon: Icons.laptop_outlined,
        ),
      );
    }

    // Ensure _activeModuleId is still valid
    if (!activeModules.any((m) => m.id == _activeModuleId)) {
      _activeModuleId = activeModules.isNotEmpty ? activeModules.last.id : '';
    }

    if (_activeModuleId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Module Workspace'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ModuleTabBar(
            activeModuleId: _activeModuleId,
            onTabSelected: (String id) {
              setState(() {
                _activeModuleId = id;
              });
              _startPollingForActiveModules();
            },
            onTabClosed: (String id) {
              provider.closeTab(id);
              _pollTimers[id]?.cancel();
              _pollTimers.remove(id);
              if (activeModules.length <= 1) {
                context.go('/');
              } else if (_activeModuleId == id) {
                setState(() {
                  _activeModuleId = provider.activeModuleIds.last;
                });
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
                final module = activeModules.firstWhere(
                  (m) => m.id == _activeModuleId,
                );
                _launchInBrowser(module);
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
                provider.stopModule(idToStop);
                _pollTimers[idToStop]?.cancel();
                _pollTimers.remove(idToStop);
                if (provider.activeModuleIds.isEmpty) {
                  context.go('/');
                }
              },
              tooltip: 'Stop Module',
            ),
          ),
        ],
      ),
      body: IndexedStack(
        key: const ValueKey('ModuleStack'),
        index: activeModules.indexWhere((m) => m.id == _activeModuleId),
        children: activeModules.map((module) {
          final isReady = _readyStatus[module.id] ?? false;
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
                      onPressed: () => provider.launchModule(module.id),
                      icon: Icons.refresh,
                      label: 'Retry Start',
                      tone: NmtkTone.danger,
                    ),
                  )
                : !isReady
                ? NmtkEmptyState(
                    title: 'Waiting for ${module.name}',
                    message: [
                      if (module.statusMessage != null) module.statusMessage!,
                      'Checking ${_moduleUri(module, healthCheck: true)}',
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
