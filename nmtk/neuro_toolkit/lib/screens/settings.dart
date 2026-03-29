import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/models/module.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _endpointController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _endpointController.text = settings.remoteEndpoint ?? '';
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final moduleProvider = context.watch<ModuleProvider>();
    final analytics = AnalyticsService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAppearanceSection(settings),
          const Divider(),
          _buildLoggingSection(settings),
          const Divider(),
          _buildTelemetrySection(settings),
          const Divider(),
          _buildCrashLogSection(analytics),
          const Divider(),
          _buildModulesSection(moduleProvider, settings),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appearance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ListTile(
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
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text('Dark'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoggingSection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Logging',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ListTile(
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
      ],
    );
  }

  Widget _buildModulesSection(
      ModuleProvider moduleProvider, SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modules Configuration',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...moduleProvider.modules.map((module) {
          return ModuleSettingsTile(module: module);
        }),
      ],
    );
  }

  Widget _buildTelemetrySection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analytics & Telemetry',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SwitchListTile(
          title: const Text('Opt-in Telemetry'),
          subtitle:
              const Text('Share anonymous usage data and performance metrics'),
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
    );
  }

  Widget _buildCrashLogSection(AnalyticsService analytics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Local Crash Logs',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final logs = await analytics.getLocalLogs();
            if (mounted) {
              _showLogDialog(context, logs);
            }
          },
          icon: const Icon(Icons.history),
          label: const Text('View Local Logs'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await analytics.clearLocalLogs();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Local logs cleared')),
              );
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Local Logs'),
        ),
      ],
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

class ModuleSettingsTile extends StatefulWidget {
  final Module module;

  const ModuleSettingsTile({super.key, required this.module});

  @override
  State<ModuleSettingsTile> createState() => _ModuleSettingsTileState();
}

class _ModuleSettingsTileState extends State<ModuleSettingsTile> {
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
    final moduleProvider = context.read<ModuleProvider>();

    return ExpansionTile(
      title: Text(widget.module.name),
      subtitle: Text(
          'Port: ${widget.module.customPort ?? widget.module.port ?? 'None'}'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            children: [
              SwitchListTile(
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
    );
  }
}
