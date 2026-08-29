import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_artefact_presentation.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_tag_filter_chip.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/neurohub_workspace_preview.dart';

class HubArtefactDetailView extends StatelessWidget {
  const HubArtefactDetailView({
    super.key,
    required this.item,
    required this.selectedTag,
    required this.onTagSelected,
    required this.onOpenInStudio,
    required this.onRunBenchmark,
    required this.onDownloadNode,
  });

  final HubArtefactPreview item;
  final String? selectedTag;
  final ValueChanged<String?> onTagSelected;
  final VoidCallback onOpenInStudio;
  final VoidCallback onRunBenchmark;
  final VoidCallback onDownloadNode;

  @override
  Widget build(BuildContext context) {
    final presentation = HubArtefactPresentation.forKind(item.kind);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        // Allowed: single-topic surface — the selected artefact summary.
        NmtkSurfaceCard(
          title: item.title,
          subtitle: 'by ${item.author} · ${item.updatedLabel}',
          leading: Icon(presentation.icon),
          trailing: NmtkStatusBadge(
            label: item.kindLabel,
            icon: presentation.icon,
            tone: presentation.tone,
          ),
          child: Text(item.description),
        ),
        if (item.rawWorkspace != null) ...<Widget>[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: NmtkPrimaryButton(
              label: 'Fork a copy',
              icon: Icons.fork_right,
              onPressed: onOpenInStudio,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 320,
            child: NeurohubWorkspacePreview(payload: item.rawWorkspace!),
          ),
        ],
        const SizedBox(height: 24),
        NmtkSection(title: 'Overview', child: Text(item.detail.overview)),
        const SizedBox(height: 24),
        NmtkSection(
          title: item.kind == HubArtefactKind.workspace
              ? 'Workspace content'
              : item.kind == HubArtefactKind.benchmarkResult
              ? 'Run content'
              : 'Node content',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: item.detail.fields
                .map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(width: 132, child: Text(field.label)),
                        Expanded(child: Text(field.value)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 24),
        NmtkSection(
          title: 'Tags',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: item.tags
                .map(
                  (tag) => HubTagFilterChip(
                    tag: tag,
                    selected: selectedTag == tag,
                    onChanged: (selected) =>
                        onTagSelected(selected ? tag : null),
                  ),
                )
                .toList(),
          ),
        ),
        if (item.rawWorkspace == null &&
            item.kind == HubArtefactKind.workspace) ...<Widget>[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: NmtkPrimaryButton(
              label: 'Open in Studio',
              icon: Icons.open_in_new,
              onPressed: onOpenInStudio,
            ),
          ),
        ],
        if (item.kind == HubArtefactKind.benchmarkResult) ...<Widget>[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: NmtkPrimaryButton(
              label: 'Run this benchmark',
              icon: Icons.play_arrow_outlined,
              onPressed: onRunBenchmark,
            ),
          ),
        ],
        if (item.kind == HubArtefactKind.customNode) ...<Widget>[
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: NmtkPrimaryButton(
              label: 'Download node',
              icon: Icons.download_outlined,
              onPressed: onDownloadNode,
            ),
          ),
        ],
      ],
    );
  }
}
