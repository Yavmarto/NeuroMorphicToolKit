import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/src/features/settings/domain/settings_state.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsStateAsync = ref.watch(settingsProvider);
    final settingsState = settingsStateAsync.value;
    if (settingsState == null) {
      return const Center(child: CircularProgressIndicator());
    }

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
                        key:
                            ValueKey('select-theme-${settingsState.themeMode}'),
                        initialValue: settingsState.themeMode,
                        items: [
                          ZetaDropdownItem(
                              value: ThemeMode.system, label: 'System'),
                          ZetaDropdownItem(
                              value: ThemeMode.light, label: 'Light'),
                          ZetaDropdownItem(
                              value: ThemeMode.dark, label: 'Dark'),
                        ],
                        onChange: (ThemeMode? v) {
                          if (v != null) {
                            ref.read(settingsProvider.notifier).setThemeMode(v);
                          }
                        },
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Server',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: _LauncherControlUrlField(settings: settingsState),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Setup & environments',
                    secondaryText:
                        'Launcher server, backend target, Python environments',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaButton.outline(
                        onPressed: () => context.go('/setup'),
                        leadingIcon: Icons
                            .settings_suggest_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
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
                        key: ValueKey(
                            'select-loglevel-${settingsState.logLevel}'),
                        initialValue: settingsState.logLevel,
                        items: LogLevel.values
                            .map(
                              (level) => ZetaDropdownItem<LogLevel>(
                                value: level,
                                label: level.name.toUpperCase(),
                              ),
                            )
                            .toList(),
                        onChange: (LogLevel? v) {
                          if (v != null) {
                            ref.read(settingsProvider.notifier).setLogLevel(v);
                          }
                        },
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Local Crash Logs',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaButton.primary(
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
                        leadingIcon: ZetaIcons.history,
                        label: 'View',
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Clear Local Logs',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaButton.outline(
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
                        leadingIcon: ZetaIcons.delete_outline,
                        label: 'Clear',
                      ),
                    ),
                  ),
                  ZetaListItem(
                    primaryText: 'Server Logs',
                    trailing: SizedBox(
                      width: trailingWidth,
                      child: ZetaButton.primary(
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
                        leadingIcon: Icons
                            .terminal, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
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

class _LauncherControlUrlField extends ConsumerStatefulWidget {
  const _LauncherControlUrlField({required this.settings});

  final SettingsState settings;

  @override
  ConsumerState<_LauncherControlUrlField> createState() =>
      _LauncherControlUrlFieldState();
}

class _LauncherControlUrlFieldState
    extends ConsumerState<_LauncherControlUrlField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settings.launcherControlApiBaseUrl ?? '',
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _LauncherControlUrlField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) {
      return;
    }
    final nextValue = widget.settings.launcherControlApiBaseUrl ?? '';
    if (_controller.text != nextValue) {
      _controller.text = nextValue;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZetaTextInput(
      key: const ValueKey('launcher-control-url'),
      controller: _controller,
      focusNode: _focusNode,
      placeholder: 'http://192.168.1.50:8091',
      onChange:
          ref.read(settingsProvider.notifier).setLauncherControlApiBaseUrl,
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
    // No listener needed — ListenableBuilder in build() handles reactivity
    // without calling setState during a parent rebuild, which would throw
    // "setState() called during build" when ZetaTextInput.didUpdateWidget
    // resets the controller value while an ancestor is being rebuilt.
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _filteredLogs(String query) {
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
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      lines = lines.where((l) => l.toLowerCase().contains(q)).toList();
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder scopes rebuilds to this subtree only, so a
    // _searchController notification that fires during a parent rebuild
    // marks this element dirty rather than calling setState on _LogDialogState.
    return ListenableBuilder(
      listenable: _searchController,
      builder: (context, _) {
        final filtered = _filteredLogs(_searchController.text);
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
                              style: Zeta.of(context)
                                  .textStyles
                                  .bodySmall
                                  .copyWith(
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
      },
    );
  }
}
