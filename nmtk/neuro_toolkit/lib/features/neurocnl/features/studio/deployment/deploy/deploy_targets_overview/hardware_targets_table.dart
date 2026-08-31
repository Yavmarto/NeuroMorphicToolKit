import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/support.dart';

class HardwareTargetsTable extends ConsumerWidget {
  const HardwareTargetsTable({
    super.key,
    this.tableKey = const Key('hardware-targets-table'),
    required this.targetIds,
    required this.selectedDeviceLabels,
    required this.selectedDeviceData,
    required this.onOpenTarget,
  });

  final Key tableKey;
  final List<String> targetIds;
  final Map<String, String> selectedDeviceLabels;
  final Map<String, Object> selectedDeviceData;
  final ValueChanged<String> onOpenTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textStyles = Zeta.of(context).textStyles;

    Widget headerText(String label) => Text(
      label,
      style: textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
    );

    return SingleChildScrollView(
      key: tableKey,
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
          DataColumn(label: headerText('Target')),
          DataColumn(label: headerText('Status')),
          DataColumn(label: headerText('Results')),
          DataColumn(label: headerText('Training')),
          DataColumn(label: headerText('')),
        ],
        rows: [
          for (final id in targetIds) _hardwareTargetRow(context, ref, id),
        ],
      ),
    );
  }

  DataRow _hardwareTargetRow(
    BuildContext context,
    WidgetRef ref,
    String targetId,
  ) {
    final target = targetForId(targetId);
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;
    final deviceLabel = selectedDeviceLabels[targetId];
    // No shared results model exists across the four hardware workspaces
    // (Akida/PYNQ/Lava each carry their own bespoke, differently-shaped
    // result state; SC-NeuroCore FPGA never produces one at all) — this is
    // the same "has a result" check the Review step's target list already
    // uses (`deploy_results_provider.dart`), not a per-target metric.
    final hasResult = ref.watch(deployTargetHasResultProvider(targetId));

    // DataRow.key only feeds Table's internal row-diffing — it never attaches
    // to a widget `find.byKey` can see, so the row also needs a KeyedSubtree
    // around one of its cells for that.
    return DataRow(
      key: ValueKey('hardware-target-row-$targetId'),
      cells: [
        DataCell(
          KeyedSubtree(
            key: Key('hardware-target-row-$targetId'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(target.icon, size: 18, color: colors.mainDefault),
                const SizedBox(width: 8),
                Text(target.label, style: textStyles.bodyMedium),
                if (targetId == 'lava') ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message:
                        'Hybrid target: runs as a software simulator by '
                        'default, becomes real Loihi2 hardware when '
                        'toggled inside Configure.',
                    child: Icon(
                      ZetaIcons.swap,
                      size: 14,
                      color: colors.mainSubtle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        DataCell(
          deviceLabel == null || deviceLabel.isEmpty
              ? const NmtkStatusBadge(
                  label: 'Not paired',
                  tone: NmtkTone.neutral,
                  icon: ZetaIcons.warning_outline,
                )
              : NmtkStatusBadge(
                  label: deviceLabel,
                  tone: NmtkTone.info,
                  icon: ZetaIcons.check_circle_outline,
                ),
        ),
        DataCell(
          hasResult
              ? const NmtkStatusBadge(
                  label: 'Ran',
                  tone: NmtkTone.success,
                  icon: ZetaIcons.check_circle_outline,
                )
              : Text(
                  'Not run yet',
                  style: textStyles.bodySmall.copyWith(
                    color: colors.mainSubtle,
                  ),
                ),
        ),
        DataCell(
          Text(
            target.trainable ? 'Trains a model' : 'No training step',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
        ),
        DataCell(
          ZetaButton.text(
            key: Key('hardware-target-open-$targetId'),
            size: ZetaWidgetSize.small,
            label: 'Configure',
            onPressed: () => onOpenTarget(targetId),
          ),
        ),
      ],
    );
  }
}
