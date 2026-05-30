import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// ----------------------------------------------------------------------------
/// NMTK COMMAND PALETTE
/// ----------------------------------------------------------------------------

class NmtkCommandPalette extends StatefulWidget {
  final List<NmtkCommand> commands;
  final VoidCallback onDismiss;

  const NmtkCommandPalette({
    super.key,
    required this.commands,
    required this.onDismiss,
  });

  @override
  State<NmtkCommandPalette> createState() => _NmtkCommandPaletteState();

  static Future<void> show(
    BuildContext context, {
    required List<NmtkCommand> commands,
  }) {
    return showDialog(
      context: context,
      barrierColor: Zeta.of(context).colors.mainDefault.withValues(alpha: 0.54),
      builder: (context) => NmtkCommandPalette(
        commands: commands,
        onDismiss: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _NmtkCommandPaletteState extends State<NmtkCommandPalette> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;
  List<NmtkCommand> _filteredCommands = [];

  @override
  void initState() {
    super.initState();
    _filteredCommands = widget.commands;
    _searchController.addListener(_onSearchChanged);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredCommands = widget.commands.where((cmd) {
        final matchLabel = cmd.label.toLowerCase().contains(query);
        final matchDesc =
            cmd.description?.toLowerCase().contains(query) ?? false;
        final matchAlias =
            cmd.aliases?.any((a) => a.toLowerCase().contains(query)) ?? false;
        return matchLabel || matchDesc || matchAlias;
      }).toList();
      _selectedIndex = 0;
    });
  }

  void _executeCommand(NmtkCommand cmd) {
    widget.onDismiss();
    cmd.onExecute();
  }

  String _semanticLabelFor(NmtkCommand cmd) {
    final parts = <String>[
      cmd.label,
      if (cmd.description != null) cmd.description!,
      if (cmd.category != null) '${cmd.category} command',
    ];
    return parts.join(', ');
  }

  void _moveSelection(int delta) {
    if (_filteredCommands.isEmpty) return;
    setState(() {
      _selectedIndex =
          (_selectedIndex + delta + _filteredCommands.length) %
          _filteredCommands.length;
    });
  }

  void _executeSelectedCommand() {
    if (_filteredCommands.isNotEmpty) {
      _executeCommand(_filteredCommands[_selectedIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(-1),
        const SingleActivator(LogicalKeyboardKey.enter):
            _executeSelectedCommand,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final paletteWidth = (constraints.maxWidth - 32).clamp(0.0, 600.0);
          final paletteMaxHeight = (constraints.maxHeight - 32).clamp(
            220.0,
            450.0,
          );

          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                key: const ValueKey<String>('nmtk-command-palette-panel'),
                width: paletteWidth,
                constraints: BoxConstraints(maxHeight: paletteMaxHeight),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.chromeBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        decoration: const InputDecoration(
                          hintText: 'Search commands...',
                          prefixIcon: Icon(Icons.search, size: 18),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: _filteredCommands.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('No commands found.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredCommands.length,
                              itemBuilder: (context, index) {
                                final cmd = _filteredCommands[index];
                                final isSelected = index == _selectedIndex;

                                return Semantics(
                                  key: ValueKey<String>(
                                    'nmtk-command-${cmd.id}',
                                  ),
                                  button: true,
                                  selected: isSelected,
                                  label: _semanticLabelFor(cmd),
                                  child: InkWell(
                                    onTap: () => _executeCommand(cmd),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.colorScheme.primary
                                                  .withValues(alpha: 0.1)
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            cmd.icon ?? Icons.bolt_rounded,
                                            size: 18,
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  cmd.label,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight: isSelected
                                                            ? FontWeight.w600
                                                            : null,
                                                        color: isSelected
                                                            ? theme
                                                                  .colorScheme
                                                                  .primary
                                                            : null,
                                                      ),
                                                ),
                                                if (cmd.description != null)
                                                  Text(
                                                    cmd.description!,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (cmd.category != null)
                                            Text(
                                              cmd.category!,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant
                                                        .withValues(alpha: 0.5),
                                                  ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _ShortcutHint(
                            keyLabel: '↑↓',
                            actionLabel: 'to navigate',
                          ),
                          _ShortcutHint(
                            keyLabel: 'Enter',
                            actionLabel: 'to select',
                          ),
                          _ShortcutHint(
                            keyLabel: 'Esc',
                            actionLabel: 'to close',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  final String keyLabel;
  final String actionLabel;

  const _ShortcutHint({required this.keyLabel, required this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _KeyCap(label: keyLabel),
        const SizedBox(width: 4),
        Text(
          actionLabel,
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(fontSize: 10),
        ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;

  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
