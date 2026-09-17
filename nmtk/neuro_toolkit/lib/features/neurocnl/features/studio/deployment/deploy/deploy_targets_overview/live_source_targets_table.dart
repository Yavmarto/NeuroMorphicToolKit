import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';

/// Table for live sensor sources (e.g. NeuroSense) — deliberately separate
/// from [HardwareTargetsTable]: sensors don't train a model or produce a
/// deploy result, so those columns don't apply here.
class LiveSourceTargetsTable extends StatelessWidget {
  const LiveSourceTargetsTable({
    super.key,
    required this.targetIds,
    required this.isConfigured,
    required this.onOpenTarget,
  });

  final List<String> targetIds;
  final bool Function(String targetId) isConfigured;
  final ValueChanged<String> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyles = Zeta.of(context).textStyles;

    Widget headerText(String label) => Text(
      label,
      style: textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
    );

    return SingleChildScrollView(
      key: const Key('live-source-targets-table'),
      scrollDirection: Axis.horizontal,
      // ZETA-MIGRATION-EXEMPT: zeta_flutter has no table/data-grid component
      // (confirmed against the installed package source) — DataTable is the
      // only option for tabular data here.
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          theme.colorScheme.surfaceContainerHighest,
        ),
        dataRowColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        border: TableBorder.all(color: theme.colorScheme.outlineVariant),
        columnSpacing: 24,
        columns: [
          DataColumn(label: headerText('Source')),
          DataColumn(label: headerText('Status')),
          DataColumn(label: headerText('')),
        ],
        rows: [
          for (final id in targetIds) _liveSourceRow(context, id),
        ],
      ),
    );
  }

  DataRow _liveSourceRow(BuildContext context, String targetId) {
    final source = sensorSourceForId(targetId);
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final configured = isConfigured(targetId);

    return DataRow(
      key: ValueKey('live-source-row-$targetId'),
      cells: [
        DataCell(
          KeyedSubtree(
            key: Key('live-source-row-$targetId'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  source?.icon ?? Icons.sensors_outlined,
                  size: 18,
                  color: colors.mainDefault,
                ),
                const SizedBox(width: 8),
                Text(source?.label ?? targetId, style: textStyles.bodyMedium),
              ],
            ),
          ),
        ),
        DataCell(
          configured
              ? const NmtkStatusBadge(
                  label: 'Configured',
                  tone: NmtkTone.success,
                  icon: ZetaIcons.check_circle_outline,
                )
              : const NmtkStatusBadge(
                  label: 'Not configured',
                  tone: NmtkTone.neutral,
                  icon: ZetaIcons.warning_outline,
                ),
        ),
        DataCell(
          ZetaButton.text(
            key: Key('live-source-open-$targetId'),
            size: ZetaWidgetSize.small,
            label: 'Configure',
            onPressed: () => onOpenTarget(targetId),
          ),
        ),
      ],
    );
  }
}
