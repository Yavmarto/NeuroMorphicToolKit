import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:neuro_toolkit/ui_core/models/commands.dart';
import 'package:neuro_toolkit/ui_core/shell_tokens.dart';

part 'command_palette_parts.dart';

/// ----------------------------------------------------------------------------
/// NMTK COMMAND PALETTE
/// ----------------------------------------------------------------------------

class NmtkCommandPalette extends StatefulWidget {
  final List<NmtkCommand> commands;
  final VoidCallback onDismiss;

  /// Placeholder text for the search field.
  final String searchHint;

  /// Message shown when no command matches the current search text.
  final String emptyMessage;

  const NmtkCommandPalette({
    super.key,
    required this.commands,
    required this.onDismiss,
    this.searchHint = 'Search commands...',
    this.emptyMessage = 'No commands found.',
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

  static const double _minTapTarget = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = NmtkShellTokens.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

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
          final margin = tokens.sectionGap;
          final paletteWidth = (constraints.maxWidth - margin * 2).clamp(
            0.0,
            600.0,
          );
          final paletteMaxHeight =
              (constraints.maxHeight - margin * 2 - viewInsets.vertical).clamp(
                220.0,
                450.0,
              );

          return SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  margin,
                  margin,
                  margin,
                  margin + viewInsets.bottom,
                ),
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
                      _buildSearchField(tokens),
                      const Divider(height: 1),
                      Flexible(child: _buildResultsList(theme, tokens)),
                      const Divider(height: 1),
                      _buildFooterHints(tokens),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchField(NmtkShellTokens tokens) {
    return Padding(
      padding: EdgeInsets.all(tokens.sectionGap),
      child: ZetaSearchBar(
        controller: _searchController,
        focusNode: _focusNode,
        placeholder: widget.searchHint,
        showSpeechToText: false,
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme, NmtkShellTokens tokens) {
    if (_filteredCommands.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(tokens.sectionGap * 2),
        child: Text(widget.emptyMessage),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _filteredCommands.length,
      itemBuilder: (context, index) {
        final cmd = _filteredCommands[index];
        final isSelected = index == _selectedIndex;
        return _buildCommandTile(theme, tokens, cmd, isSelected);
      },
    );
  }

  Widget _buildCommandTile(
    ThemeData theme,
    NmtkShellTokens tokens,
    NmtkCommand cmd,
    bool isSelected,
  ) {
    return Semantics(
      key: ValueKey<String>('nmtk-command-${cmd.id}'),
      button: true,
      selected: isSelected,
      label: _semanticLabelFor(cmd),
      child: InkWell(
        onTap: () => _executeCommand(cmd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTapTarget),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.sectionGap,
              vertical: tokens.compactGap,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.1)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  cmd.icon ??
                      Icons
                          .bolt_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  size: 18,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: tokens.compactGap + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterHints(NmtkShellTokens tokens) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.sectionGap,
        vertical: tokens.compactGap,
      ),
      child: Wrap(
        spacing: tokens.compactGap + 4,
        runSpacing: tokens.compactGap,
        children: const [
          _ShortcutHint(keyLabel: '↑↓', actionLabel: 'to navigate'),
          _ShortcutHint(keyLabel: 'Enter', actionLabel: 'to select'),
          _ShortcutHint(keyLabel: 'Esc', actionLabel: 'to close'),
        ],
      ),
    );
  }
}
