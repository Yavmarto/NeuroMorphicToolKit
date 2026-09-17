import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';

/// One selectable row in the "My workspace repos" list.
///
/// The repo set is already filtered server-side (topic `neurohub-workspace`
/// or a `workspace-` name prefix), so the client renders it as-is.
class WorkspaceRepoCard extends StatelessWidget {
  const WorkspaceRepoCard({super.key, required this.workspace, this.onTap});

  final NeurohubWorkspaceSummary workspace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    final permission = switch (workspace.permission) {
      'admin' => 'Owner',
      'write' => 'Can edit',
      _ => 'Read only',
    };

    return Semantics(
      button: true,
      label: 'Open workspace ${workspace.displayName}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Allowed: single-topic surface — one selectable workspace row.
          child: NmtkSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.folder_copy_outlined,
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
                        workspace.displayName,
                        style: textStyles.titleMedium.copyWith(
                          color: colors.mainDefault,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${workspace.owner}/${workspace.slug}',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.mainSubtle,
                        ),
                      ),
                      if (workspace.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          workspace.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodyMedium.copyWith(
                            color: colors.mainSubtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NmtkStatusBadge(label: permission),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
