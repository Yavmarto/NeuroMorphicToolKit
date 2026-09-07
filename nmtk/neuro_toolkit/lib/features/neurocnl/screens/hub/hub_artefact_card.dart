import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_artefact_presentation.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_tag_filter_chip.dart';

class HubArtefactCard extends StatelessWidget {
  // Local card-width threshold, not a screen-level breakpoint: this card is
  // laid out in a grid/list and can be far narrower than the window, well
  // below NmtkShellTokens.compactBreakpoint.
  static const double _stackTrailingWidth = 520;

  const HubArtefactCard({
    super.key,
    required this.item,
    required this.selectedTag,
    required this.onTap,
    required this.onTagSelected,
    this.trailing,
  });

  final HubArtefactPreview item;
  final String? selectedTag;
  final VoidCallback onTap;
  final ValueChanged<String?> onTagSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final presentation = HubArtefactPresentation.forKind(item.kind);
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final typeBadge = NmtkStatusBadge(
      label: item.kindLabel,
      icon: presentation.icon,
      tone: presentation.tone,
    );

    return Semantics(
      button: true,
      label: 'Open ${item.kindLabel}: ${item.title}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Allowed: single-topic surface — one selectable Hub artefact.
          child: NmtkSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackTrailing = constraints.maxWidth < _stackTrailingWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            presentation.icon,
                            size: 20,
                            color: colors.mainSubtle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.title,
                                style: textStyles.titleMedium.copyWith(
                                  color: colors.mainDefault,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.description,
                                style: textStyles.bodyMedium.copyWith(
                                  color: colors.mainSubtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!stackTrailing) ...<Widget>[
                          const SizedBox(width: 16),
                          trailing ?? typeBadge,
                        ],
                      ],
                    ),
                    if (stackTrailing) ...<Widget>[
                      const SizedBox(height: 12),
                      trailing ?? typeBadge,
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _MetadataItem(
                          icon: Icons.person_outline,
                          label: 'By ${item.author}',
                        ),
                        _MetadataItem(
                          icon: Icons.schedule_outlined,
                          label: item.updatedLabel,
                        ),
                        if (item.metric != null)
                          _MetadataItem(
                            icon: Icons.insights_outlined,
                            label: item.metric!,
                            emphasized: true,
                          ),
                      ],
                    ),
                    if (item.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Wrap(
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
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final color = emphasized ? colors.mainDefault : colors.mainSubtle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Zeta.of(context).textStyles.labelMedium.copyWith(
            color: color,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
