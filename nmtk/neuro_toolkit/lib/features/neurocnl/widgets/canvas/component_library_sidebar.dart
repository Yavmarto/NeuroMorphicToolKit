import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/theme/nir_node_styles.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';

class ComponentLibrarySidebar extends ConsumerStatefulWidget {
  const ComponentLibrarySidebar({super.key});

  @override
  ConsumerState<ComponentLibrarySidebar> createState() =>
      _ComponentLibrarySidebarState();
}

class _ComponentLibrarySidebarState
    extends ConsumerState<ComponentLibrarySidebar> {
  final Set<String> _expandedCategories = {'neuron'};

  void _toggleCategory(String category) {
    setState(() {
      if (_expandedCategories.contains(category)) {
        _expandedCategories.remove(category);
      } else {
        _expandedCategories.add(category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(nirNodeTypesProvider);
    final grouped = <String, List<NirNodeType>>{};
    for (final type in types) {
      grouped.putIfAbsent(type.category, () => <NirNodeType>[]).add(type);
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: grouped.entries
          .map(
            (entry) => _CategorySection(
              category: entry.key,
              types: entry.value,
              isExpanded: _expandedCategories.contains(entry.key),
              onToggle: () => _toggleCategory(entry.key),
            ),
          )
          .toList(),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.types,
    required this.isExpanded,
    required this.onToggle,
  });

  final String category;
  final List<NirNodeType> types;
  final bool isExpanded;
  final VoidCallback onToggle;

  String _titleForCategory(String raw) {
    switch (raw) {
      case 'io':
        return 'Input / Output';
      case 'neuron':
        return 'Neuron / State';
      case 'transform':
        return 'Transforms';
      case 'pooling':
        return 'Pooling';
      case 'utility':
        return 'Utility';
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = nirCategoryColor(context, category);
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons
                      .category_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _titleForCategory(category),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? ZetaIcons.expand_less : ZetaIcons.expand_more,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...types.map((type) => _NirTypeTile(type: type)),
        const Divider(height: 1),
      ],
    );
  }
}

class _NirTypeTile extends ConsumerWidget {
  const _NirTypeTile({required this.type});

  final NirNodeType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Draggable<NirNodeType>(
      data: type,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: _PaletteItemCard(type: type, isDragging: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _PaletteItemCard(type: type),
      ),
      child: _PaletteItemCard(type: type),
    );
  }
}

class _PaletteItemCard extends StatelessWidget {
  const _PaletteItemCard({required this.type, this.isDragging = false});
  final NirNodeType type;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final color = nirCategoryColor(context, type.category);
    return Container(
      width: isDragging ? 180 : null,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDragging ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: isDragging ? Border.all(color: color, width: 1.5) : null,
      ),
      child: Row(
        children: [
          Icon(type.icon, size: 12, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              type.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDragging ? FontWeight.w600 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isDragging)
            Icon(
              Icons.drag_indicator,
              size: 14,
              color: color,
            ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
        ],
      ),
    );
  }
}
