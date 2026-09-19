import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_profile_section.dart';

class HubProfileView extends StatelessWidget {
  const HubProfileView({
    super.key,
    required this.items,
    required this.selectedTag,
    required this.onSelect,
    required this.onTagSelected,
    required this.onToggleVisibility,
  });

  final List<HubArtefactPreview> items;
  final String? selectedTag;
  final ValueChanged<HubArtefactPreview> onSelect;
  final ValueChanged<String?> onTagSelected;
  final ValueChanged<HubArtefactPreview> onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    final hasRealWorkspaces = items.any((item) => item.rawWorkspace != null);
    final owned = hasRealWorkspaces
        ? items
              .where(
                (item) =>
                    item.visibility == HubVisibility.private ||
                    item.author == kHubCurrentUserName ||
                    item.id.contains('gesture-model'),
              )
              .toList()
        : items.where((item) => item.author == kHubCurrentUserName).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        if (!hasRealWorkspaces) ...[
          // Allowed: single-topic surface — user profile summary.
          NmtkSurfaceCard(
            title: 'Maya Chen',
            subtitle: 'Signed in as Maya Chen · @maya-chen',
            leading: CircleAvatar(
              child: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            child: Text(
              'Your public work is discoverable in Explore. Keep drafts private until they are ready.',
            ),
          ),
          const SizedBox(height: 24),
        ],
        HubProfileSection(
          title: 'Workspaces',
          kind: HubArtefactKind.workspace,
          items: owned,
          selectedTag: selectedTag,
          onSelect: onSelect,
          onTagSelected: onTagSelected,
          onToggleVisibility: onToggleVisibility,
        ),
        const SizedBox(height: 24),
        HubProfileSection(
          title: 'Benchmark results',
          kind: HubArtefactKind.benchmarkResult,
          items: owned,
          selectedTag: selectedTag,
          onSelect: onSelect,
          onTagSelected: onTagSelected,
          onToggleVisibility: onToggleVisibility,
        ),
        const SizedBox(height: 24),
        HubProfileSection(
          title: 'Nodes',
          kind: HubArtefactKind.customNode,
          items: owned,
          selectedTag: selectedTag,
          onSelect: onSelect,
          onTagSelected: onTagSelected,
          onToggleVisibility: onToggleVisibility,
        ),
      ],
    );
  }
}
