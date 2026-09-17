import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/support.dart';

class DatasetFileTile extends StatelessWidget {
  const DatasetFileTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final DatasetEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final bgColor = selected
        ? colors.mainPrimary.withValues(alpha: 0.06)
        : // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
          Colors.transparent;
    final borderColor = selected
        ? colors.mainPrimary.withValues(alpha: 0.30)
        : // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
          Colors.transparent;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            bottom: const BorderSide(color: AppTheme.border, width: 0.5),
            left: BorderSide(color: borderColor, width: selected ? 3 : 0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ZetaIcons.file,
                  size: 18,
                  color: selected
                      ? colors.mainPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? colors.mainPrimary : null,
                    ),
                  ),
                ),
                if (entry.sizeBytes != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    _formatBytes(entry.sizeBytes!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                if (selected)
                  Icon(
                    ZetaIcons.check_circle,
                    size: 18,
                    color: colors.mainPrimary,
                  )
                else
                  DatasetStatusChip(
                    label: _statusLabel(entry.status),
                    status: entry.status,
                  ),
              ],
            ),
            if (entry.isDownloading) ...[
              const SizedBox(height: 8),
              DownloadProgressBar(
                progress: entry.downloadProgress,
                sizeBytes: entry.sizeBytes,
              ),
            ],
            if (entry.errorMessage != null &&
                entry.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry.errorMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.mainNegative),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(DatasetServerStatus status) => switch (status) {
    DatasetServerStatus.ready => entry.isLocalImport ? 'Imported' : 'On server',
    DatasetServerStatus.downloading => 'Downloading...',
    DatasetServerStatus.error => 'Failed',
    DatasetServerStatus.notDownloaded => 'Download',
  };

  String _formatBytes(int bytes) => formatBytesStatic(bytes);
}
