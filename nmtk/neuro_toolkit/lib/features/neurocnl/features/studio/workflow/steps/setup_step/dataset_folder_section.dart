import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/dataset_file_tile.dart';

class DatasetFolderSection extends StatefulWidget {
  const DatasetFolderSection({
    super.key,
    required this.folder,
    required this.selectedDatasetId,
    required this.onFileTapped,
  });

  final DatasetFolder folder;
  final String? selectedDatasetId;
  final void Function(DatasetEntry entry) onFileTapped;

  @override
  State<DatasetFolderSection> createState() => _DatasetFolderSectionState();
}

class _DatasetFolderSectionState extends State<DatasetFolderSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: colors.surfaceHover.withValues(alpha: 0.4),
                ),
                child: Row(
                  children: [
                    Icon(
                      ZetaIcons.folder_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.folder.folderName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.folder.hasReadyFiles)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfacePositiveSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.folder.files.where((f) => f.isReady).length}/${widget.folder.files.length} cached',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.mainPositive,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? ZetaIcons.expand_less : ZetaIcons.expand_more,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              ...widget.folder.files.map(
                (file) => DatasetFileTile(
                  entry: file,
                  selected: widget.selectedDatasetId == file.id,
                  onTap: () => widget.onFileTapped(file),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ZetaColors get colors => Zeta.of(context).colors;
}
