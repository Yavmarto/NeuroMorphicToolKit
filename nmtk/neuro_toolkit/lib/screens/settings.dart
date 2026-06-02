import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
    final analytics = ref.watch(analyticsServiceProvider);
    final controlApi = ref.watch(controlApiServiceProvider);
    final zeta = Zeta.of(context);
    final spacing = zeta.spacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trailingWidth = constraints.maxWidth * 0.28;

        return ListView(
          padding: EdgeInsets.all(spacing.xl_2),
          children: [
            NmtkSection(
              title: 'Settings',
              titleStyle: zeta.textStyles.heading3,
              child: const SizedBox.shrink(),
            ),
            SizedBox(height: spacing.large),
            NmtkSection(
              title: 'General',
              titleStyle: zeta.textStyles.titleLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZetaListItem(
                    primaryText: 'Theme',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaSelectInput<ThemeMode>(
                        key: ValueKey('select-theme-${settings.themeMode}'),
                        initialValue: settings.themeMode,
                        items: [
                          ZetaDropdownItem(
                              value: ThemeMode.system, label: 'System'),
                          ZetaDropdownItem(
                              value: ThemeMode.light, label: 'Light'),
                          ZetaDropdownItem(
                              value: ThemeMode.dark, label: 'Dark'),
                        ],
                        onChange: (ThemeMode? v) {
                          if (v != null) settings.setThemeMode(v);
                        },
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Server',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaTextInput(
                        key: const ValueKey('launcher-control-url'),
                        initialValue: ref
                                .read(settingsStateProvider)
                                .launcherControlApiBaseUrl ??
                            '',
                        placeholder: 'http://192.168.1.50:8091',
                        onChange: settings.setLauncherControlApiBaseUrl,
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Setup & environments',
                    secondaryText:
                        'Launcher server, backend target, Python environments',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: NmtkOutlinedButton(
                        onPressed: () => context.go('/setup'),
                        icon: Icons.settings_suggest_outlined,
                        label: 'Open',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.large),
            NmtkSection(
              title: 'Logging',
              titleStyle: zeta.textStyles.titleLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZetaListItem(
                    primaryText: 'Log Level',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaSelectInput<LogLevel>(
                        key: ValueKey('select-loglevel-${settings.logLevel}'),
                        initialValue: settings.logLevel,
                        items: LogLevel.values
                            .map(
                              (level) => ZetaDropdownItem<LogLevel>(
                                value: level,
                                label: level.name.toUpperCase(),
                              ),
                            )
                            .toList(),
                        onChange: (LogLevel? v) {
                          if (v != null) settings.setLogLevel(v);
                        },
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Local Crash Logs',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: NmtkPrimaryButton(
                        onPressed: () async {
                          try {
                            List<String> logs;
                            try {
                              logs = await controlApi.fetchCrashLogLines();
                            } catch (_) {
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
                        label: 'View',
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Clear Local Logs',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: NmtkOutlinedButton(
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
                        label: 'Clear',
                        tone: NmtkTone.danger,
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Server Logs',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: NmtkPrimaryButton(
                        onPressed: () async {
                          try {
                            List<String> logs;
                            try {
                              logs = await controlApi
                                  .fetchBackendActivityLogLines();
                            } catch (_) {
                              logs =
                                  await analytics.getBackendActivityLogLines();
                            }
                            if (!context.mounted) return;
                            _showLogDialog(
                              context,
                              title: 'Server Logs',
                              logs: logs,
                              showErrorOnlyToggle: true,
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            NmtkToasts.error(
                              context,
                              'Could not fetch server logs: $e',
                            );
                          }
                        },
                        icon: Icons.terminal,
                        label: 'View',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showLogDialog(
    BuildContext context, {
    required String title,
    required List<String> logs,
    bool showErrorOnlyToggle = false,
  }) {
    showDialog<void>(
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

    return AlertDialog(
      title: Text(widget.title),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showErrorOnlyToggle) ...[
              Text(
                'Error Only',
                style: Zeta.of(context).textStyles.bodySmall,
              ),
              const SizedBox(width: 8),
              Switch(
                value: _errorOnly,
                onChanged: (value) => setState(() => _errorOnly = value),
              ),
              const SizedBox(width: 16),
            ],
            ZetaButton.text(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                NmtkToasts.success(context, 'Logs copied to clipboard');
              },
              label: 'Copy All',
            ),
            const SizedBox(width: 4),
            ZetaButton.text(
              onPressed: () => Navigator.pop(context),
              label: 'Close',
            ),
          ],
        ),
      ],
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            ZetaTextInput(
              controller: _searchController,
              placeholder: 'Filter logs...',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: text.isEmpty
                  ? const Center(child: Text('No logs to display.'))
                  : Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          text,
                          style: Zeta.of(context).textStyles.bodySmall.copyWith(
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
