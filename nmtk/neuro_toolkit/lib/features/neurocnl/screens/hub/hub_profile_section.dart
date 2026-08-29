import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_artefact_card.dart';

class HubProfileSection extends StatelessWidget {
  const HubProfileSection({
    super.key,
    required this.title,
    required this.kind,
    required this.items,
    required this.selectedTag,
    required this.onSelect,
    required this.onTagSelected,
    required this.onToggleVisibility,
  });

  final String title;
  final HubArtefactKind kind;
  final List<HubArtefactPreview> items;
  final String? selectedTag;
  final ValueChanged<HubArtefactPreview> onSelect;
  final ValueChanged<String?> onTagSelected;
  final ValueChanged<HubArtefactPreview> onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    final sectionItems = items.where((item) => item.kind == kind).toList();
    return NmtkSection(
      title: title,
      subtitle:
          '${sectionItems.length} item${sectionItems.length == 1 ? '' : 's'}',
      child: Column(
        children: sectionItems
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HubArtefactCard(
                  item: item,
                  selectedTag: selectedTag,
                  onTap: () => onSelect(item),
                  onTagSelected: onTagSelected,
                  trailing: NmtkOutlinedButton(
                    label: item.visibility == HubVisibility.public
                        ? 'Public'
                        : 'Private',
                    icon: item.visibility == HubVisibility.public
                        ? ZetaIcons.visibility
                        : ZetaIcons.lock,
                    onPressed: () => onToggleVisibility(item),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
