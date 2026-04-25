import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _endpointController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsStateProvider);
    _endpointController.text = settings.remoteEndpoint ?? '';
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
    final moduleProvider = ref.watch(moduleStateProvider);
    final analytics = ref.watch(analyticsServiceProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NmtkSurfaceCard(
            title: 'Appearance',
            subtitle: 'Control how the launcher theme is rendered.',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                onChanged: (ThemeMode? newValue) {
                  if (newValue != null) {
                    settings.setThemeMode(newValue);
                  }
                },
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          NmtkSurfaceCard(
            title: 'Logging',
            subtitle: 'Tune launcher logging verbosity for diagnostics.',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log Level'),
              trailing: DropdownButton<LogLevel>(
                value: settings.logLevel,
                onChanged: (LogLevel? newValue) {
                  if (newValue != null) {
                    settings.setLogLevel(newValue);
                  }
                },
                items: LogLevel.values.map((LogLevel level) {
                  return DropdownMenuItem<LogLevel>(
                    value: level,
                    child: Text(level.name.toUpperCase()),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          NmtkSurfaceCard(
            title: 'Analytics & Telemetry',
            subtitle:
                'Decide how much anonymous health data the launcher can send.',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Opt-in Telemetry'),
                  subtitle: const Text(
                    'Share anonymous usage data and performance metrics.',
                  ),
                  value: settings.telemetryEnabled,
                  onChanged: (value) => settings.setTelemetryEnabled(value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    labelText: 'Remote Reporting Endpoint',
                    hintText: 'https://example.com/api/logs',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => settings.setRemoteEndpoint(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          NmtkSurfaceCard(
            title: 'Local Crash Logs',
            subtitle: 'Inspect launcher crash history without leaving the app.',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                NmtkPrimaryButton(
                  onPressed: () async {
                    final logs = await analytics.getLocalLogs();
                    if (mounted) {
                      _showLogDialog(context, logs);
                    }
                  },
                  icon: Icons.history,
                  label: 'View Local Logs',
                ),
                NmtkOutlinedButton(
                  onPressed: () async {
                    await analytics.clearLocalLogs();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Local logs cleared')),
                      );
                    }
                  },
                  icon: Icons.delete_outline,
                  label: 'Clear Local Logs',
                  tone: NmtkTone.danger,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          NmtkSurfaceCard(
            title: 'Modules Configuration',
            subtitle: 'Toggle modules and override launcher-assigned ports.',
            child: Column(
              children: [
                for (final module in moduleProvider.modules)
                  ModuleSettingsTile(module: module),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLogDialog(BuildContext context, String logs) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local Crash Logs'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class ModuleSettingsTile extends ConsumerStatefulWidget {
  final Module module;

  const ModuleSettingsTile({super.key, required this.module});

  @override
  ConsumerState<ModuleSettingsTile> createState() => _ModuleSettingsTileState();
}

class _ModuleSettingsTileState extends ConsumerState<ModuleSettingsTile> {
  late TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(
      text: widget.module.customPort?.toString() ??
          widget.module.port?.toString() ??
          '',
    );
  }

  @override
  void didUpdateWidget(ModuleSettingsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module.customPort != widget.module.customPort ||
        oldWidget.module.port != widget.module.port) {
      _portController.text = widget.module.customPort?.toString() ??
          widget.module.port?.toString() ??
          '';
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moduleProvider = ref.read(moduleStateProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NmtkSurfaceCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          title: Text(widget.module.name),
          subtitle: Text(
            'Port: ${widget.module.customPort ?? widget.module.port ?? 'None'}',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled'),
                    value: widget.module.isEnabled,
                    onChanged: (bool value) {
                      moduleProvider.updateModuleSettings(
                        widget.module.id,
                        isEnabled: value,
                        customPort: widget.module.customPort,
                      );
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start on Launch'),
                    subtitle: const Text(
                      'Automatically start this module when the app opens '
                      '(adds ~3–8 s to startup if cold).',
                    ),
                    value: widget.module.startOnLaunch,
                    onChanged: (bool value) {
                      moduleProvider.updateModuleSettings(
                        widget.module.id,
                        startOnLaunch: value,
                      );
                    },
                  ),
                  if (widget.module.port != null)
                    TextField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: 'Custom Port',
                        hintText: 'Default: ${widget.module.port}',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.save),
                          onPressed: () {
                            final parsed = int.tryParse(_portController.text);
                            moduleProvider.updateModuleSettings(
                              widget.module.id,
                              isEnabled: widget.module.isEnabled,
                              customPort: parsed,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Port updated')),
                            );
                          },
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (value) {
                        final parsed = int.tryParse(value);
                        moduleProvider.updateModuleSettings(
                          widget.module.id,
                          isEnabled: widget.module.isEnabled,
                          customPort: parsed,
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
