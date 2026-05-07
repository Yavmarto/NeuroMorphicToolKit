import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    return showShadDialog(
      context: context,
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
        final matchDesc = cmd.description?.toLowerCase().contains(query) ?? false;
        final matchAlias = cmd.aliases?.any((a) => a.toLowerCase().contains(query)) ?? false;
        return matchLabel || matchDesc || matchAlias;
      }).toList();
      _selectedIndex = 0;
    });
  }

  void _executeCommand(NmtkCommand cmd) {
    widget.onDismiss();
    cmd.onExecute();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _filteredCommands.length;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + _filteredCommands.length) % _filteredCommands.length;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_filteredCommands.isNotEmpty) {
          _executeCommand(_filteredCommands[_selectedIndex]);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onDismiss();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);

    return KeyboardListener(
      focusNode: FocusNode(), // Dummy node for global keys
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 450),
          margin: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.chromeBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: ShadInput(
                  controller: _searchController,
                  focusNode: _focusNode,
                  placeholder: const Text('Search commands...'),
                  leading: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.search, size: 18),
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

                          return InkWell(
                            onTap: () => _executeCommand(cmd),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary.withOpacity(0.1)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    cmd.icon ?? Icons.bolt_rounded,
                                    size: 18,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cmd.label,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: isSelected ? FontWeight.w600 : null,
                                            color: isSelected ? theme.colorScheme.primary : null,
                                          ),
                                        ),
                                        if (cmd.description != null)
                                          Text(
                                            cmd.description!,
                                            style: theme.textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (cmd.category != null)
                                    Text(
                                      cmd.category!,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _KeyCap(label: '↑↓'),
                    const SizedBox(width: 4),
                    const Text('to navigate', style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 12),
                    _KeyCap(label: 'Enter'),
                    const SizedBox(width: 4),
                    const Text('to select', style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 12),
                    _KeyCap(label: 'Esc'),
                    const SizedBox(width: 4),
                    const Text('to close', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;

  const _KeyCap({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
