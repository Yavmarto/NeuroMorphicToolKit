import 'package:flutter/material.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class DatasetStatusChip extends StatelessWidget {
  const DatasetStatusChip({
    super.key,
    required this.label,
    required this.status,
  });

  final String label;
  final DatasetServerStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final (Color bg, Color fg) = switch (status) {
      DatasetServerStatus.ready => (
        colors.surfacePositiveSubtle,
        colors.mainPositive,
      ),
      DatasetServerStatus.downloading => (
        colors.surfaceInfoSubtle,
        colors.mainInfo,
      ),
      DatasetServerStatus.error => (
        colors.surfaceNegativeSubtle,
        colors.mainNegative,
      ),
      DatasetServerStatus.notDownloaded => (
        colors.surfaceHover,
        colors.mainSubtle,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
