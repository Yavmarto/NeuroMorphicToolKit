import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_palette_search.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_palette_search_field.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

/// Filter-by-layer/component-name search control for the network view.
///
/// Follows the shared Studio list-search pattern: the field is a
/// [CanvasPaletteSearchField], candidates are ranked by
/// [filterCanvasPaletteItems] (exact label → prefix → substring → keyword →
/// fuzzy), and the filtered list renders directly beneath the field with a
/// "No matching layers" empty state. Picking a result focuses that layer in the
/// graph; the list stays keyboard-operable (↑/↓ to move, Enter to pick, Esc to
/// clear) so the same control works without a pointer.
class NetworkLayerSearch extends StatefulWidget {
  const NetworkLayerSearch({
    super.key,
    required this.nodes,
    this.selectedNodeId,
    this.onSelected,
    this.hintText = 'Search layers…',
  });

  /// Layers/components to search. Order is preserved for equal-score matches.
  final List<CanvasNode> nodes;

  /// Currently focused layer, highlighted in the result list.
  final String? selectedNodeId;

  /// Called with the picked layer, or null when the query is cleared.
  final ValueChanged<CanvasNode?>? onSelected;

  final String hintText;

  @override
  State<NetworkLayerSearch> createState() => _NetworkLayerSearchState();
}

class _NetworkLayerSearchState extends State<NetworkLayerSearch> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  int _highlighted = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _label(CanvasNode node) => node.label ?? node.componentId;

  static Iterable<String> _keywords(CanvasNode node) => <String>[
    node.componentId,
    if (node.nirType != null) node.nirType!,
    if (node.metadata['category'] != null) node.metadata['category'].toString(),
  ];

  String _categoryOf(CanvasNode node) =>
      node.metadata['category']?.toString() ?? 'utility';

  List<CanvasNode> get _matches => filterCanvasPaletteItems<CanvasNode>(
    widget.nodes,
    _query,
    label: _label,
    keywords: _keywords,
  );

  bool get _showResults => _query.trim().isNotEmpty;

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _highlighted = 0;
    });
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
    widget.onSelected?.call(null);
  }

  void _moveHighlight(int delta) {
    final matches = _matches;
    if (matches.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, matches.length - 1);
    });
  }

  void _submit() {
    final matches = _matches;
    if (matches.isEmpty) return;
    _select(matches[_highlighted.clamp(0, matches.length - 1)]);
  }

  void _select(CanvasNode node) {
    _controller.text = _label(node);
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() {
      _query = '';
      _highlighted = 0;
    });
    widget.onSelected?.call(node);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final highlighted = matches.isEmpty
        ? 0
        : _highlighted.clamp(0, matches.length - 1);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveHighlight(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveHighlight(-1),
        const SingleActivator(LogicalKeyboardKey.escape): _clear,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CanvasPaletteSearchField(
            controller: _controller,
            hintText: widget.hintText,
            onChanged: _onChanged,
            onSubmitted: _submit,
          ),
          if (_showResults) ...[
            const SizedBox(height: 6),
            _buildResults(context, matches, highlighted),
          ],
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    List<CanvasNode> matches,
    int highlighted,
  ) {
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Text(
          'No matching layers',
          style: Zeta.of(context).textStyles.bodySmall.copyWith(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final node = matches[index];
          return _NetworkLayerSearchRow(
            node: node,
            label: _label(node),
            category: _categoryOf(node),
            color: canvasCategoryColor(_categoryOf(node)),
            highlighted: index == highlighted,
            selected: node.id == widget.selectedNodeId,
            onTap: () => _select(node),
          );
        },
      ),
    );
  }
}

class _NetworkLayerSearchRow extends StatelessWidget {
  const _NetworkLayerSearchRow({
    required this.node,
    required this.label,
    required this.category,
    required this.color,
    required this.highlighted,
    required this.selected,
    required this.onTap,
  });

  final CanvasNode node;
  final String label;
  final String category;
  final Color color;
  final bool highlighted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    final accent = tokens.studioPalette.accent;
    final background = selected
        ? accent.withValues(alpha: 0.14)
        : highlighted
        ? AppTheme.surfaceVariant
        : Colors.transparent;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Zeta.of(context).textStyles.labelSmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
