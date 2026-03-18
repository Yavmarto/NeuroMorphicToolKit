import 'package:flutter/material.dart';
import '../models/quantization_report.dart';

/// Table/visual showing bit-width vs accuracy drop and sparsity.
class NmtkQuantizationTable extends StatelessWidget {
  final QuantizationReport report;

  const NmtkQuantizationTable({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report.bitWidths.isEmpty) {
      return Center(
        child: Text(
          'No quantization data',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return DataTable(
      headingRowColor: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest),
      dataRowColor: WidgetStatePropertyAll(theme.colorScheme.surface),
      border: TableBorder.all(color: theme.colorScheme.outlineVariant, width: 1),
      columnSpacing: 24,
      columns: const [
        DataColumn(label: Text('Bit Width', style: TextStyle(fontWeight: FontWeight.w600))),
        DataColumn(label: Text('Accuracy Drop', style: TextStyle(fontWeight: FontWeight.w600))),
        DataColumn(label: Text('Sparsity', style: TextStyle(fontWeight: FontWeight.w600))),
      ],
      rows: List.generate(report.bitWidths.length, (i) {
        final bits = report.bitWidths[i];
        final drop = report.accuracyDrops[i];
        final sparsity = report.sparsity[i];

        return DataRow(cells: [
          DataCell(Text(
            '$bits-bit',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          )),
          DataCell(_AccuracyDropIndicator(drop: drop)),
          DataCell(Text(
            '${(sparsity * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: theme.colorScheme.onSurface),
          )),
        ]);
      }),
    );
  }
}

/// Colored indicator for accuracy drop.
class _AccuracyDropIndicator extends StatelessWidget {
  final double drop;

  const _AccuracyDropIndicator({required this.drop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = drop * 100;
    final Color color;
    if (pct < 2) {
      color = Colors.green;
    } else if (pct < 5) {
      color = Colors.orange;
    } else {
      color = theme.colorScheme.error;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${pct.toStringAsFixed(2)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
