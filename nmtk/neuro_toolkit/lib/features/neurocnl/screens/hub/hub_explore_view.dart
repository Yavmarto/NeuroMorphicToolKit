import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_artefact_card.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_tag_filter_chip.dart';

class HubExploreView extends StatefulWidget {
  const HubExploreView({
    super.key,
    required this.items,
    required this.query,
    required this.kindFilter,
    required this.selectedTag,
    required this.popularFirst,
    required this.onQueryChanged,
    required this.onKindChanged,
    required this.onTagSelected,
    required this.onSortChanged,
    required this.onSelect,
    required this.onClearFilters,
  });

  final List<HubArtefactPreview> items;
  final String query;
  final HubArtefactKind? kindFilter;
  final String? selectedTag;
  final bool popularFirst;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<HubArtefactKind?> onKindChanged;
  final ValueChanged<String?> onTagSelected;
  final ValueChanged<bool> onSortChanged;
  final ValueChanged<HubArtefactPreview> onSelect;
  final VoidCallback onClearFilters;

  @override
  State<HubExploreView> createState() => _HubExploreViewState();
}

class _HubExploreViewState extends State<HubExploreView> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
    _searchFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant HubExploreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _searchController.text != widget.query) {
      _searchController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    widget.onQueryChanged('');
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final matching = widget.items.where((item) {
      final typeMatches =
          widget.kindFilter == null || item.kind == widget.kindFilter;
      final tagMatches =
          widget.selectedTag == null || item.tags.contains(widget.selectedTag);
      return item.visibility == HubVisibility.public &&
          typeMatches &&
          tagMatches &&
          item.searchableText.contains(widget.query.trim().toLowerCase());
    }).toList();
    matching.sort(
      (first, second) => widget.popularFirst
          ? second.popularity.compareTo(first.popularity)
          : second.recency.compareTo(first.recency),
    );
    final hasFilters =
        widget.query.isNotEmpty ||
        widget.kindFilter != null ||
        widget.selectedTag != null;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Explore NeuroHub',
                style: Zeta.of(context).textStyles.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Find public workspaces, benchmark results, and reusable pipeline nodes.',
              ),
              const SizedBox(height: 16),
              ZetaTextInput(
                key: const Key('hub-search'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                semanticLabel: 'Search NeuroHub items',
                placeholder: 'Search titles, tags, people, or metadata',
                prefix: const Icon(ZetaIcons.search),
                suffix: widget.query.isEmpty
                    ? null
                    : Tooltip(
                        message: 'Clear search',
                        child: ZetaIconButton.text(
                          icon: ZetaIcons.close,
                          size: ZetaWidgetSize.small,
                          semanticLabel: 'Clear search',
                          onPressed: _clearSearch,
                        ),
                      ),
                onChange: (value) => widget.onQueryChanged(value ?? ''),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _typeButton(null, 'All'),
                  _typeButton(HubArtefactKind.workspace, 'Workspaces'),
                  _typeButton(HubArtefactKind.benchmarkResult, 'Benchmarks'),
                  _typeButton(HubArtefactKind.customNode, 'Nodes'),
                  NmtkOutlinedButton(
                    label: widget.popularFirst
                        ? 'Popular first'
                        : 'Recent first',
                    icon: ZetaIcons.sort,
                    onPressed: () => widget.onSortChanged(!widget.popularFirst),
                  ),
                  if (hasFilters)
                    NmtkOutlinedButton(
                      label: 'Clear filters',
                      icon: ZetaIcons.close,
                      onPressed: widget.onClearFilters,
                    ),
                ],
              ),
              if (widget.selectedTag != null) ...<Widget>[
                const SizedBox(height: 12),
                HubTagFilterChip(
                  tag: widget.selectedTag!,
                  selected: true,
                  onChanged: (_) => widget.onTagSelected(null),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${matching.length} public item${matching.length == 1 ? '' : 's'}',
              ),
            ],
          ),
        ),
        Expanded(
          child: matching.isEmpty
              ? const NmtkEmptyState(
                  title: 'No matching public items',
                  message:
                      'Try another search term or clear the active filters.',
                  icon: Icons.search_off,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: matching.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => HubArtefactCard(
                    key: ValueKey<String>(matching[index].id),
                    item: matching[index],
                    selectedTag: widget.selectedTag,
                    onTap: () => widget.onSelect(matching[index]),
                    onTagSelected: widget.onTagSelected,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _typeButton(HubArtefactKind? kind, String label) => NmtkPrimaryButton(
    label: label,
    tone: widget.kindFilter == kind ? NmtkTone.info : NmtkTone.neutral,
    onPressed: () => widget.onKindChanged(kind),
  );
}
