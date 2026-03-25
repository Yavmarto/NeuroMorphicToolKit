import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';

class ToolViewScreen extends StatefulWidget {
  final String initialModuleId;

  const ToolViewScreen({super.key, required this.initialModuleId});

  @override
  State<ToolViewScreen> createState() => _ToolViewScreenState();
}

class _ToolViewScreenState extends State<ToolViewScreen> {
  final Map<String, WebViewController> _controllers = {};
  final Map<String, bool> _readyStatus = {};
  final Map<String, Timer> _pollTimers = {};
  late String _activeModuleId;

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
    final provider = context.read<ModuleProvider>();
    for (final module in provider.activeModules) {
      if (!(_readyStatus[module.id] ?? false) && !_pollTimers.containsKey(module.id)) {
        _pollModuleHealth(module);
      }
    }
  }

  void _pollModuleHealth(Module module) {
    _pollTimers[module.id] = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        if (module.port == null) return;
        final response = await http
            .get(Uri.parse('http://localhost:${module.port}/health'))
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
        debugPrint('Polling health for ${module.name} failed: $e');
      }
    });
  }

  WebViewController _getController(Module module) {
    if (_controllers.containsKey(module.id)) {
      return _controllers[module.id]!;
    }

    final url = module.hasFrontend
        ? 'http://localhost:${module.port}'
        : 'http://localhost:${module.port}/docs';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error for ${module.name}: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    _controllers[module.id] = controller;
    return controller;
  }

  Future<void> _launchInBrowser(Module module) async {
    final url = module.hasFrontend
        ? 'http://localhost:${module.port}'
        : 'http://localhost:${module.port}/docs';
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $url')),
        );
      }
    }
  }

  bool _isWebViewSupported() {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ModuleProvider>(
      builder: (context, provider, child) {
        final activeModules = provider.activeModules;

        if (activeModules.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Workspace')),
            body: const Center(
              child: Text('No modules launched. Go to Dashboard to launch a module.'),
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
                onTabSelected: (id) {
                  setState(() {
                    _activeModuleId = id;
                  });
                  _startPollingForActiveModules();
                },
                onTabClosed: (id) {
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
              IconButton(
                icon: const Icon(Icons.open_in_browser),
                onPressed: () {
                  final module = activeModules.firstWhere((m) => m.id == _activeModuleId);
                  _launchInBrowser(module);
                },
                tooltip: 'Open in System Browser',
              ),
              IconButton(
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
            ],
          ),
          body: IndexedStack(
            key: const ValueKey('ModuleStack'),
            index: activeModules.indexWhere((m) => m.id == _activeModuleId),
            children: activeModules.map((module) {
              final isReady = _readyStatus[module.id] ?? false;
              final supported = _isWebViewSupported();

              return Container(
                key: ValueKey(module.id),
                child: !isReady
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text('Waiting for ${module.name} to start...'),
                            const SizedBox(height: 8),
                            Text('Checking http://localhost:${module.port}/health',
                                style: Theme.of(context).textTheme.bodySmall,),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _launchInBrowser(module),
                              icon: const Icon(Icons.open_in_browser),
                              label: const Text('Open in Browser instead'),
                            ),
                          ],
                        ),
                      )
                    : supported
                        ? WebViewWidget(controller: _getController(module))
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.warning, size: 48, color: Colors.orange),
                                const SizedBox(height: 16),
                                const Text('WebView not supported on this platform.'),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _launchInBrowser(module),
                                  icon: const Icon(Icons.open_in_browser),
                                  label: const Text('Open in System Browser'),
                                ),
                              ],
                            ),
                          ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
