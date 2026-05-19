import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  final TextEditingController _launcherControlController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsStateProvider);
    _endpointController.text = settings.remoteEndpoint ?? '';
    _launcherControlController.text = settings.launcherControlApiBaseUrl ?? '';
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _launcherControlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
    final moduleProvider = ref.watch(moduleStateProvider);
    final analytics = ref.watch(analyticsServiceProvider);
    final controlApi = ref.watch(controlApiServiceProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        NmtkSurfaceCard(
          title: 'Launcher Settings',
          subtitle:
              'Adjust shell behavior, logging, telemetry, and per-module overrides here.',
          child: Text(
            'Launcher configuration and global preferences.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),

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

        NmtkSurfaceCard(
          title: 'Launcher Control API',
          subtitle:
              'Configure the launcher backend host used by mobile or remote clients.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Launcher Control API Base URL',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              ShadInput(
                controller: _launcherControlController,
                placeholder: const Text('http://192.168.1.50:8090'),
                onChanged: settings.setLauncherControlApiBaseUrl,
              ),
              const SizedBox(height: 8),
              Text(
                'On Android and iOS, point this at the machine running '
                '`scripts/launcher_control_service.py --host 0.0.0.0 --port 8090`.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              NmtkOutlinedButton(
                onPressed: () => context.go('/backend-setup'),
                icon: Icons.dns_outlined,
                label: 'Server Setup',
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
                  try {
                    List<String> logs;
                    try {
                      // Prefer the API path — works regardless of sandbox.
                      logs = await controlApi.fetchCrashLogLines();
                    } catch (_) {
                      // Fallback: direct file read (works on non-sandboxed
                      // desktop builds and in tests).
                      logs = await analytics.getLocalLogLines();
                    }
                    if (!context.mounted) return;
                    _showLogDialog(
                      context,
                      title: 'Local Crash Logs',
                      logs: logs,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    NmtkToasts.error(
                      context,
                      'Could not fetch local logs: $e',
                    );
                  }
                },
                icon: Icons.history,
                label: 'View Local Logs',
              ),
              NmtkOutlinedButton(
                onPressed: () async {
                  try {
                    await analytics.clearLocalLogs();
                    if (!context.mounted) return;
                    NmtkToasts.success(context, 'Local logs cleared');
                  } catch (e) {
                    if (!context.mounted) return;
                    NmtkToasts.error(
                      context,
                      'Could not clear local logs: $e',
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
        const SizedBox(height: 16),

        // ── Backend Logs ─────────────────────────────────────────────────────
        NmtkSurfaceCard(
          title: 'Backend Logs',
          subtitle: 'View everything happening across launcher backends.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              NmtkPrimaryButton(
                onPressed: () async {
                  try {
                    List<String> logs;
                    try {
                      // Prefer the API path — the launcher control service
                      // reads ~/Documents/ outside the app sandbox.
                      logs = await controlApi.fetchBackendActivityLogLines();
                    } catch (_) {
                      // Fallback: direct file read for unsandboxed builds.
                      logs = await analytics.getBackendActivityLogLines();
                    }
                    if (!context.mounted) return;
                    _showLogDialog(
                      context,
                      title: 'Backend Activity',
                      logs: logs,
                      showErrorOnlyToggle: true,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    NmtkToasts.error(
                      context,
                      'Could not fetch backend activity: $e',
                    );
                  }
                },
                icon: Icons.terminal,
                label: 'View Backend Activity',
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

  void _showLogDialog(
    BuildContext context, {
    required String title,
    required List<String> logs,
    bool showErrorOnlyToggle = false,
  }) {
    showShadDialog<void>(
      context: context,
      builder: (dialogContext) => _LogDialog(
        title: title,
        logs: logs,
        showErrorOnlyToggle: showErrorOnlyToggle,
      ),
    );
  }
}

class _LogDialog extends StatefulWidget {
  final String title;
  final List<String> logs;
  final bool showErrorOnlyToggle;

  const _LogDialog({
    required this.title,
    required this.logs,
    this.showErrorOnlyToggle = false,
  });

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  bool _errorOnly = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filteredLogs {
    var lines = widget.showErrorOnlyToggle && _errorOnly
        ? widget.logs
            .where(
              (l) =>
                  l.toLowerCase().contains('error') ||
                  l.toLowerCase().contains('exception') ||
                  l.toLowerCase().contains('failed') ||
                  l.contains('-> 4') ||
                  l.contains('-> 5'),
            )
            .toList()
        : List<String>.from(widget.logs);
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      lines = lines.where((l) => l.toLowerCase().contains(q)).toList();
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;
    final text = filtered.join('\n');

    return ShadDialog(
      title: Text(widget.title),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showErrorOnlyToggle) ...[
              Text(
                'Error Only',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              ShadSwitch(
                value: _errorOnly,
                onChanged: (value) => setState(() => _errorOnly = value),
              ),
              const SizedBox(width: 16),
            ],
            ShadButton.ghost(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                NmtkToasts.success(context, 'Logs copied to clipboard');
              },
              child: const Text('Copy All'),
            ),
            const SizedBox(width: 4),
            ShadButton.ghost(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
      child: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            ShadInput(
              controller: _searchController,
              placeholder: const Text('Filter logs…'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: text.isEmpty
                  ? const Center(child: Text('No logs to display.'))
                  : Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          text,
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 12,
                          ),
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
