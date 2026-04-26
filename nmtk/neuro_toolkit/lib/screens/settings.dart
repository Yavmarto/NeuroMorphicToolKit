import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';

/// Settings screen — content-only widget (no Scaffold; chrome is provided by
/// NmtkDesktopScaffold in ToolViewScreen / the ShellRoute wrapper).
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
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Appearance ──────────────────────────────────────────────────────
        NmtkSurfaceCard(
          title: 'Appearance',
          subtitle: 'Control how the launcher theme is rendered.',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Theme', style: theme.textTheme.bodyMedium),
              ShadSelect<ThemeMode>(
                selectedOptionBuilder: (context, value) => Text(
                  switch (value) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  },
                ),
                options: const [
                  ShadOption(value: ThemeMode.system, child: Text('System')),
                  ShadOption(value: ThemeMode.light, child: Text('Light')),
                  ShadOption(value: ThemeMode.dark, child: Text('Dark')),
                ],
                initialValue: settings.themeMode,
                onChanged: (ThemeMode? newValue) {
                  if (newValue != null) settings.setThemeMode(newValue);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Logging ─────────────────────────────────────────────────────────
        NmtkSurfaceCard(
          title: 'Logging',
          subtitle: 'Tune launcher logging verbosity for diagnostics.',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Log Level', style: theme.textTheme.bodyMedium),
              ShadSelect<LogLevel>(
                selectedOptionBuilder: (context, value) =>
                    Text(value.name.toUpperCase()),
                options: LogLevel.values
                    .map(
                      (level) => ShadOption<LogLevel>(
                        value: level,
                        child: Text(level.name.toUpperCase()),
                      ),
                    )
                    .toList(),
                initialValue: settings.logLevel,
                onChanged: (LogLevel? newValue) {
                  if (newValue != null) settings.setLogLevel(newValue);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Analytics & Telemetry ────────────────────────────────────────────
        NmtkSurfaceCard(
          title: 'Analytics & Telemetry',
          subtitle:
              'Decide how much anonymous health data the launcher can send.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Opt-in Telemetry',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Share anonymous usage data and performance metrics.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ShadSwitch(
                    value: settings.telemetryEnabled,
                    onChanged: settings.setTelemetryEnabled,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remote Reporting Endpoint',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  ShadInput(
                    controller: _endpointController,
                    placeholder: const Text('https://example.com/api/logs'),
                    onChanged: settings.setRemoteEndpoint,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Local Crash Logs ─────────────────────────────────────────────────
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
                  if (!context.mounted) return;
                  _showLogDialog(context, logs);
                },
                icon: Icons.history,
                label: 'View Local Logs',
              ),
              NmtkOutlinedButton(
                onPressed: () async {
                  await analytics.clearLocalLogs();
                  if (!context.mounted) return;
                  NmtkToasts.success(context, 'Local logs cleared');
                },
                icon: Icons.delete_outline,
                label: 'Clear Local Logs',
                tone: NmtkTone.danger,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Modules Configuration ────────────────────────────────────────────
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
    );
  }

  void _showLogDialog(BuildContext context, String logs) {
    showShadDialog<void>(
      context: context,
      builder: (dialogContext) => ShadDialog(
        title: const Text('Local Crash Logs'),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              logs,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ModuleSettingsTile
// ---------------------------------------------------------------------------

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
    final theme = Theme.of(context);

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Enabled toggle ───────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Enabled',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      ShadSwitch(
                        value: widget.module.isEnabled,
                        onChanged: (bool value) {
                          moduleProvider.updateModuleSettings(
                            widget.module.id,
                            isEnabled: value,
                            customPort: widget.module.customPort,
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ── Start on Launch toggle ───────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start on Launch',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Automatically start this module when the app opens '
                              '(adds ~3–8 s to startup if cold).',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ShadSwitch(
                        value: widget.module.startOnLaunch,
                        onChanged: (bool value) {
                          moduleProvider.updateModuleSettings(
                            widget.module.id,
                            startOnLaunch: value,
                          );
                        },
                      ),
                    ],
                  ),
                  // ── Custom port input ────────────────────────────────────
                  if (widget.module.port != null) ...[
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Port (default: ${widget.module.port})',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ShadInput(
                                controller: _portController,
                                placeholder: Text(
                                  'Default: ${widget.module.port}',
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
                            ),
                            const SizedBox(width: 8),
                            ShadButton.ghost(
                              size: ShadButtonSize.sm,
                              onPressed: () {
                                final parsed =
                                    int.tryParse(_portController.text);
                                moduleProvider.updateModuleSettings(
                                  widget.module.id,
                                  isEnabled: widget.module.isEnabled,
                                  customPort: parsed,
                                );
                                NmtkToasts.success(context, 'Port updated');
                              },
                              child: const Icon(Icons.save, size: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
